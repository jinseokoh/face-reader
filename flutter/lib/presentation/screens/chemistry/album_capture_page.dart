import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/face_metadata_client.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/domain/models/face_metadata.dart';
import 'package:facely/domain/services/face_metrics_lateral.dart';
import 'package:facely/domain/services/photo_quality.dart';
import 'package:facely/presentation/screens/chemistry/face_metric_overlay_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

/// 앨범 캡처 전체 flow 를 한 wrapper Scaffold 안에 두기 위한 fullSize modal.
///
/// 카메라 (face_mesh_page) path 와 시각적으로 동일한 wrapper:
///   - 검정 배경 Scaffold
///   - 검정 AppBar + 흰 글씨 "얼굴 정면" / "얼굴 45° 측면" 타이틀
///   - X 닫기 버튼
///
/// 내부에서 image_picker.pickImage 를 호출하면 OS native picker 가 떠도
/// 그 위에 우리 sheet (검정 AppBar 포함) 가 그대로 유지되어 통일감 확보.
///
/// step 진행:
///   ready          — picker 호출 전·중 (자동으로 frontal picker 즉시 호출)
///   processing*    — mesh 추론 중 로딩
///   selectFace     — 얼굴이 여럿이면 분석할 얼굴을 고른다 (§61)
///   preview*       — 선택된 사진 + mesh overlay + [분석] 버튼
///
/// 품질 검사(§60, `photo_quality.dart`): 얼굴 없음·너무 작음·너무 어두움은
/// 점수를 만들지 않고 문구만 보여준다. 정면 사진의 각도가 정면이 아니면
/// 측면과 같은 방식으로 [다른 사진 선택] 만 준다.
///
/// 사용자가 frontal preview 의 [정면 분석] 누르면 lateral 첨부 dialog →
/// 측면 picker → preview → [측면 분석] → [CaptureResult] 반환 후 pop.
class AlbumCapturePage extends ConsumerStatefulWidget {
  const AlbumCapturePage({super.key});

  @override
  ConsumerState<AlbumCapturePage> createState() => _AlbumCapturePageState();
}

class _AlbumCapturePageState extends ConsumerState<AlbumCapturePage> {
  final _picker = ImagePicker();
  _AlbumStep _step = _AlbumStep.ready;
  _AlbumPhoto? _frontal;
  _AlbumPhoto? _lateral;
  Future<FaceMetadata?>? _metadataFuture;
  String? _error;

  /// 여러 얼굴 선택 대기 (§61).
  _FaceChoice? _choice;

  bool get _isLateralPhase =>
      _step == _AlbumStep.processingLateral ||
      _step == _AlbumStep.previewLateral ||
      (_step == _AlbumStep.selectFace && (_choice?.lateral ?? false));

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: Text(
              _isLateralPhase ? '얼굴 45° 측면' : '얼굴 정면',
              style: AppText.modalTitle.copyWith(color: Colors.white),
            ),
            actions: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const FaIcon(FontAwesomeIcons.xmark, color: Colors.white, size: 20),
              ),
            ],
          ),
          body: _buildBody(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 진입 직후 frontal picker 자동 호출.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickFrontal());
  }

  Future<void> _afterFrontalConfirm() async {
    // 카메라 path 의 측면 instructional modal 과 동일한 스타일 — lateral.png
    // illustration + "얼굴 45° 측면" 타이틀 + 안내 + [건너뛰기 TextButton] +
    // [측면사진 선택 검정 ElevatedButton].
    final wantLateral = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/lateral.png',
                height: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                '얼굴 45° 측면',
                style: AppText.modalTitle.copyWith(
                  color: const Color(0xFF1F1F1F),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '코 모양 판단을 위해 한쪽 귀가 안보이는 '
                ' 측면 사진을 올려주세요. 패스하면, 특징이 없는 평범한 코 모양으로 판단합니다.',
                style: AppText.body.copyWith(
                  color: AppColors.accent,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF555555),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          '패스',
                          style: AppText.subTitle
                              .copyWith(color: AppColors.accent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1F1F1F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          '측면사진 선택',
                          style: AppText.subTitle
                              .copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (wantLateral == true) {
      await _pickLateral();
    } else {
      _runAnalysis();
    }
  }

  Future<FaceMetadata?> _analyzeMetadata(File file) async {
    try {
      final meta = await FaceMetadataClient().analyze(file);
      debugPrint('[Album] DeepFace ok age=${meta.age} '
          'gender=${meta.gender} ethnicity=${meta.ethnicity}');
      return meta;
    } on FaceAnalyzeException catch (e) {
      // 503 은 고장이 아니라 서버가 동시 처리 상한으로 거절한 것 — 확인 화면이
      // 안내를 띄울 수 있게 삼키지 않고 넘긴다. 그 외 실패는 종전대로 non-fatal.
      if (e.statusCode == 503) rethrow;
      debugPrint('[Album] DeepFace failed (non-fatal): $e');
      return null;
    } catch (e) {
      debugPrint('[Album] DeepFace failed (non-fatal): $e');
      return null;
    }
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: AppText.body.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    switch (_step) {
      case _AlbumStep.ready:
      case _AlbumStep.processingFrontal:
      case _AlbumStep.processingLateral:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      case _AlbumStep.selectFace:
        return _buildFaceChoice(_choice!);
      case _AlbumStep.previewFrontal:
        return _buildPreview(_frontal!, isLateralPhase: false);
      case _AlbumStep.previewLateral:
        return _buildPreview(_lateral!, isLateralPhase: true);
    }
  }

  /// 얼굴이 여럿인 사진 — 번호 상자를 눌러 분석할 얼굴을 고른다 (§61).
  Widget _buildFaceChoice(_FaceChoice c) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: LayoutBuilder(builder: (context, constraints) {
            final scale = math.min(
              constraints.maxWidth / c.width,
              constraints.maxHeight / c.height,
            );
            return SizedBox(
              width: c.width * scale,
              height: c.height * scale,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(c.path), fit: BoxFit.fill),
                  for (var i = 0; i < c.faces.length; i++)
                    Positioned(
                      left: c.faces[i].boundingBox.left * scale,
                      top: c.faces[i].boundingBox.top * scale,
                      width: c.faces[i].boundingBox.width * scale,
                      height: c.faces[i].boundingBox.height * scale,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _continueWithFace(
                          c.path,
                          c.faces[i],
                          lateral: c.lateral,
                          faceCount: c.faces.length,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          alignment: Alignment.topLeft,
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            child: Text('얼굴 ${i + 1}', style: AppText.caption),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.black.withValues(alpha: 0.6),
            child: Text(
              '얼굴이 ${c.faces.length}명 있습니다.\n분석할 얼굴을 눌러 주세요.',
              style: AppText.body.copyWith(color: Colors.white, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(_AlbumPhoto photo, {required bool isLateralPhase}) {
    final onConfirm = isLateralPhase ? _runAnalysis : _afterFrontalConfirm;
    // 측면 사진의 yaw 가 3/4·profile 이 아니면 측면 8개를 잴 수 없다. 막지는
    // 않고, 문구를 바꾸고 [결과 확인] 대신 [다른 사진 선택]·[측면 무시] 두
    // 갈래를 준다.
    final yawClass = classifyYaw(photo.yaw);
    final usable = isLateralPhase
        ? yawClass == YawClass.threeQuarter || yawClass == YawClass.profile
        : yawClass == YawClass.frontal;
    final lateralUsable = usable;
    final description = isLateralPhase
        ? (usable ? '측면 사진 분석한 결과입니다.' : '측면 분석에 적합한 사진이 아닙니다.')
        : (usable ? '정면 사진 분석한 결과입니다.' : '정면 분석에 적합한 사진이 아닙니다.');

    return Stack(
      fit: StackFit.expand,
      children: [
        // 사진을 contain 으로 맞춘 화면 픽셀 크기의 상자 위에 오버레이를 그린다.
        // FittedBox 로 사진 픽셀 공간을 축소하면 라벨 글자까지 함께 줄어들므로,
        // 화면 크기를 직접 계산해 카메라 화면과 같은 글자 크기로 그린다.
        Center(
          child: LayoutBuilder(builder: (context, constraints) {
            final scale = math.min(
              constraints.maxWidth / photo.width,
              constraints.maxHeight / photo.height,
            );
            return SizedBox(
              width: photo.width * scale,
              height: photo.height * scale,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(photo.pngBytes, fit: BoxFit.fill),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: FaceMetricOverlayPainter(
                        result: photo.meshResult,
                        phase: isLateralPhase
                            ? MetricOverlayPhase.lateral
                            : MetricOverlayPhase.frontal,
                        rotationCompensation: 0,
                        lensDirection: CameraLensDirection.back,
                        overlayColor: Colors.greenAccent,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.black.withValues(alpha: 0.6),
            child: Text(
              description,
              style: AppText.body.copyWith(
                color: lateralUsable ? Colors.white : Colors.redAccent,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: MediaQuery.of(context).padding.bottom + 8,
          child: Center(
            child: lateralUsable
                ? SizedBox(
                    width: 200,
                    child: _previewButton('결과 확인', onConfirm),
                  )
                : isLateralPhase
                    ? Row(
                        children: [
                          Expanded(
                            child:
                                _previewButton('다른 사진 선택', _repickLateral),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _previewButton('측면 무시', _skipLateral),
                          ),
                        ],
                      )
                    : SizedBox(
                        width: 200,
                        child: _previewButton('다른 사진 선택', _repickFrontal),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _previewButton(String label, VoidCallback onPressed) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.85),
          foregroundColor: const Color(0xFF333333),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label, style: AppText.subTitle),
      ),
    );
  }

  /// 각도가 안 맞는 측면 사진을 버리고 정면만으로 분석한다.
  void _skipLateral() {
    _lateral = null;
    _runAnalysis();
  }

  /// 측면 사진을 다시 고른다. picker 를 취소하면 지금 preview 에 그대로 남는다.
  Future<void> _repickLateral() async {
    final pick = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (!mounted || pick == null) return;
    await _startPhoto(pick.path, lateral: true);
  }

  /// 각도가 정면이 아닌 정면 사진을 다시 고른다. 취소하면 preview 에 남는다.
  Future<void> _repickFrontal() async {
    final pick = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (!mounted || pick == null) return;
    await _startPhoto(pick.path, lateral: false);
  }

  Future<void> _pickFrontal() async {
    final pick = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (!mounted) return;
    if (pick == null) {
      // 사용자가 picker 취소 — sheet 자체 닫음.
      Navigator.of(context).pop();
      return;
    }
    await _startPhoto(pick.path, lateral: false);
  }

  Future<void> _pickLateral() async {
    final pick = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (!mounted) return;
    if (pick == null) {
      // lateral picker 취소 → 정면만으로 분석.
      _runAnalysis();
      return;
    }
    await _startPhoto(pick.path, lateral: true);
  }

  /// Exception 의 "Exception: " 접두를 떼고 문구만.
  static String _messageOf(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception: '), '');

  /// 얼굴 검출 → 하나면 바로 진행, 여럿이면 선택 화면 (§61).
  Future<void> _startPhoto(String path, {required bool lateral}) async {
    setState(() => _step =
        lateral ? _AlbumStep.processingLateral : _AlbumStep.processingFrontal);
    try {
      final (faces, w, h) = await _detectFaces(path);
      if (faces.length > 1) {
        if (!mounted) return;
        setState(() {
          _choice = _FaceChoice(
              path: path, faces: faces, width: w, height: h, lateral: lateral);
          _step = _AlbumStep.selectFace;
        });
        return;
      }
      await _continueWithFace(path, faces.first, lateral: lateral, faceCount: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _messageOf(e));
    }
  }

  /// 고른 얼굴로 mesh·품질 검사 → preview. 정면이면 성별·연령 추정도 띄운다
  /// (여러 얼굴 사진은 고른 얼굴만 잘라 보낸다).
  Future<void> _continueWithFace(
    String path,
    Face face, {
    required bool lateral,
    required int faceCount,
  }) async {
    setState(() {
      _choice = null;
      _step =
          lateral ? _AlbumStep.processingLateral : _AlbumStep.processingFrontal;
    });
    try {
      final photo = await _processAlbumPhoto(path, face);
      if (!lateral) {
        // DeepFace background kickoff — preview·측면 picker 시간 동안 병렬 진행.
        final input =
            faceCount > 1 ? await _cropForMetadata(path, face) : File(path);
        _metadataFuture = _analyzeMetadata(input);
      }
      if (!mounted) return;
      setState(() {
        if (lateral) {
          _lateral = photo;
          _step = _AlbumStep.previewLateral;
        } else {
          _frontal = photo;
          _step = _AlbumStep.previewFrontal;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _messageOf(e));
    }
  }

  /// ML Kit 얼굴 검출 + 사진 크기. 얼굴이 없으면 throw.
  Future<(List<Face>, int, int)> _detectFaces(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    final List<Face> faces;
    try {
      faces = await faceDetector.processImage(inputImage);
    } finally {
      // processImage 실패 시에도 네이티브 detector 해제.
      await faceDetector.close();
    }
    if (faces.isEmpty) {
      throw Exception('얼굴을 찾을 수 없습니다.\n다른 사진을 선택해 주세요.');
    }
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    return (faces, w, h);
  }

  /// 고른 얼굴 주변(1.6배)만 잘라 임시 PNG 로 — 성별·연령 추정 입력.
  Future<File> _cropForMetadata(String path, Face face) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final r = expandedCropRect(face.boundingBox, image.width, image.height);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
          image, r, Rect.fromLTWH(0, 0, r.width, r.height), Paint());
      final cropped = await recorder
          .endRecording()
          .toImage(r.width.round(), r.height.round());
      try {
        final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw Exception('이미지 인코딩 실패');
        final file = File(
            '${Directory.systemTemp.path}/facely_face_${DateTime.now().microsecondsSinceEpoch}.png');
        await file.writeAsBytes(png.buffer.asUint8List());
        return file;
      } finally {
        cropped.dispose();
      }
    } finally {
      image.dispose();
    }
  }

  /// 고른 얼굴 상자 → MediaPipe FaceMesh → 품질 검사(§60) → yaw 계산.
  Future<_AlbumPhoto> _processAlbumPhoto(String path, Face face) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final original = frame.image;

    // ── Square-pad before MediaPipe ─────────────────────────────────────
    // MediaPipe Face Mesh 가 non-square input 에서 landmark Y 좌표를
    // distortion 시킨다 (내부 192×192 fit 시 non-uniform scale). 9:20 핸드폰
    // 화면 캡쳐 같은 tall portrait 가 들어오면 faceAspectRatio z 가 +3 이상으로
    // 폭발해서 oval 도 oblong 으로 분류된다.
    // → 짧은 축을 흰색으로 padding 해서 square 로 만든 후 MediaPipe 에 넘긴다.
    // ML Kit bbox 도 같은 offset 으로 shift.
    final origW = original.width;
    final origH = original.height;
    final ui.Image squareImage;
    final double padOffsetX;
    final double padOffsetY;
    if (origW == origH) {
      squareImage = original;
      padOffsetX = 0;
      padOffsetY = 0;
    } else {
      final maxDim = math.max(origW, origH);
      padOffsetX = (maxDim - origW) / 2.0;
      padOffsetY = (maxDim - origH) / 2.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, maxDim.toDouble(), maxDim.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.drawImage(original, Offset(padOffsetX, padOffsetY), Paint());
      final picture = recorder.endRecording();
      squareImage = await picture.toImage(maxDim, maxDim);
      original.dispose();
    }

    // square 분기에서는 squareImage == original 이라 finally 의 dispose 한 번으로
    // 둘 다 해제된다. 미해제 시 사진당 full-res 네이티브 비트맵이 누적돼 궁합
    // (2장 연속 분석) 같은 흐름에서 메모리 압박 → iOS jetsam kill 을 유발.
    // landmark 없음·인코딩 실패 등 throw 경로에서도 해제되도록 try-finally.
    try {
      final byteData =
          await squareImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw Exception('이미지를 디코딩할 수 없습니다');
      final rgba = Uint8List.sublistView(byteData.buffer.asUint8List());

      final imgW = squareImage.width.toDouble();
      final imgH = squareImage.height.toDouble();
      final bbox = face.boundingBox;
      final shifted = Rect.fromLTRB(
        bbox.left + padOffsetX,
        bbox.top + padOffsetY,
        bbox.right + padOffsetX,
        bbox.bottom + padOffsetY,
      );
      final clamped = Rect.fromLTRB(
        shifted.left.clamp(0.0, imgW),
        shifted.top.clamp(0.0, imgH),
        shifted.right.clamp(0.0, imgW),
        shifted.bottom.clamp(0.0, imgH),
      );
      // §60 — 얼굴 크기·밝기. 통과 못 하면 점수를 만들지 않는다.
      final issue = photoQualityIssue(
        face: clamped,
        imageW: origW,
        imageH: origH,
        meanLuma: meanLumaInRect(
            rgba, squareImage.width, squareImage.height, clamped),
      );
      if (issue != null) throw Exception(issue);
      final box = FaceMeshBox.fromLTWH(
        left: clamped.left,
        top: clamped.top,
        width: clamped.width,
        height: clamped.height,
      );

      final processor = await FaceMeshProcessor.create(
        delegate: FaceMeshDelegate.xnnpack,
        enableRoiTracking: false,
        minDetectionConfidence: 0.5,
        minTrackingConfidence: 0.5,
      );
      final meshImage = FaceMeshImage(
        pixels: rgba,
        width: squareImage.width,
        height: squareImage.height,
      );
      final FaceMeshResult result;
      try {
        result = processor.process(
          meshImage,
          box: box,
          boxScale: 1.2,
          boxMakeSquare: true,
          rotationDegrees: 0,
        );
      } finally {
        // process 실패 시에도 네이티브 processor 해제.
        processor.close();
      }

      if (result.landmarks.isEmpty) {
        throw Exception('얼굴 랜드마크를 추출할 수 없습니다.\n다른 사진을 선택해 주세요.');
      }

      final pngData =
          await squareImage.toByteData(format: ui.ImageByteFormat.png);
      if (pngData == null) throw Exception('이미지 인코딩 실패');
      final pngBytes = Uint8List.sublistView(pngData.buffer.asUint8List());

      final yaw = estimateYaw(result.landmarks);
      final outW = squareImage.width;
      final outH = squareImage.height;
      debugPrint('[Album] processed image=${outW}x$outH '
          '(orig=${origW}x$origH padOffset=${padOffsetX.toStringAsFixed(0)},${padOffsetY.toStringAsFixed(0)}) '
          'yaw=${yaw.toStringAsFixed(3)} class=${classifyYaw(yaw)}');

      return _AlbumPhoto(
        pngBytes: pngBytes,
        meshResult: result,
        width: outW,
        height: outH,
        yaw: yaw,
      );
    } finally {
      squareImage.dispose();
    }
  }

  void _runAnalysis() {
    if (!mounted || _frontal == null) return;
    final result = CaptureResult(
      frontalLandmarks: _frontal!.meshResult.landmarks,
      lateralLandmarks: _lateral?.meshResult.landmarks,
      imageWidth: _frontal!.width,
      imageHeight: _frontal!.height,
      stillBytes: _frontal!.pngBytes,
      source: AnalysisSource.album,
      metadataFuture: _metadataFuture,
    );
    Navigator.of(context).pop(result);
  }
}

class _AlbumPhoto {
  final Uint8List pngBytes;
  final FaceMeshResult meshResult;
  final int width;
  final int height;
  final double yaw;

  _AlbumPhoto({
    required this.pngBytes,
    required this.meshResult,
    required this.width,
    required this.height,
    required this.yaw,
  });
}

/// 여러 얼굴 선택 대기 상태 (§61).
class _FaceChoice {
  final String path;
  final List<Face> faces;
  final int width;
  final int height;
  final bool lateral;
  const _FaceChoice({
    required this.path,
    required this.faces,
    required this.width,
    required this.height,
    required this.lateral,
  });
}

enum _AlbumStep {
  ready,
  processingFrontal,
  selectFace,
  previewFrontal,
  processingLateral,
  previewLateral,
}
