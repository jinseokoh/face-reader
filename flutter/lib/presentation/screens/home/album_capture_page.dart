import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/face_metadata_client.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/domain/models/face_metadata.dart';
import 'package:facely/domain/services/face_metrics_lateral.dart';
import 'package:facely/presentation/screens/home/face_mesh_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

/// 앨범 캡처 전체 flow 를 한 wrapper Scaffold 안에 두기 위한 fullSize modal.
///
/// 카메라 (face_mesh_page) path 와 시각적으로 동일한 wrapper:
///   - 검정 배경 Scaffold
///   - 검정 AppBar + 흰 글씨 "얼굴 정면" / "얼굴 측면" 타이틀
///   - X 닫기 버튼
///
/// 내부에서 image_picker.pickImage 를 호출하면 OS native picker 가 떠도
/// 그 위에 우리 sheet (검정 AppBar 포함) 가 그대로 유지되어 통일감 확보.
///
/// step 진행:
///   ready          — picker 호출 전·중 (자동으로 frontal picker 즉시 호출)
///   processing*    — mesh 추론 중 로딩
///   preview*       — 선택된 사진 + mesh overlay + [분석] 버튼
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

  bool get _isLateralPhase =>
      _step == _AlbumStep.processingLateral ||
      _step == _AlbumStep.previewLateral;

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
              _isLateralPhase ? '얼굴 측면' : '얼굴 정면',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
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
    // illustration + "얼굴 측면" 타이틀 + 안내 + [건너뛰기 TextButton] +
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
              const Text(
                '얼굴 측면',
                style: TextStyle(
                  color: Color(0xFF1F1F1F),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '코 모양 판단을 위해 한쪽 귀가 안보이는 '
                ' 측면 사진을 올려주세요. 패스하면, 특징이 없는 평범한 코 모양으로 판단합니다.',
                style: TextStyle(
                  color: Color(0xFF555555),
                  fontSize: 14,
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
                        child: const Text(
                          '패스',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
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
                        child: const Text(
                          '측면사진 선택',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
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
            style: const TextStyle(color: Colors.white, fontSize: 16),
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
      case _AlbumStep.previewFrontal:
        return _buildPreview(_frontal!, isLateralPhase: false);
      case _AlbumStep.previewLateral:
        return _buildPreview(_lateral!, isLateralPhase: true);
    }
  }

  Widget _buildPreview(_AlbumPhoto photo, {required bool isLateralPhase}) {
    final description = isLateralPhase
        ? '버튼을 클릭하면, 측면 사진을 분석합니다.'
        : '버튼을 클릭하면, 정면 사진을 분석합니다.';
    final buttonLabel = isLateralPhase ? '측면 분석' : '정면 분석';
    final onConfirm = isLateralPhase ? _runAnalysis : _afterFrontalConfirm;

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: photo.width.toDouble(),
              height: photo.height.toDouble(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(photo.pngBytes, fit: BoxFit.fill),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: FaceMeshPainter(
                        result: photo.meshResult,
                        rotationCompensation: 0,
                        lensDirection: CameraLensDirection.back,
                        overlayColor: Colors.greenAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, height: 1.4),
              textAlign: TextAlign.left,
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.85),
                  foregroundColor: const Color(0xFF333333),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const FaIcon(FontAwesomeIcons.camera, size: 18),
                label: Text(
                  buttonLabel,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
    setState(() => _step = _AlbumStep.processingFrontal);
    try {
      final photo = await _processAlbumPhoto(pick.path);
      // DeepFace background kickoff — preview·측면 picker 시간 동안 병렬 진행.
      _metadataFuture = _analyzeMetadata(File(pick.path));
      if (!mounted) return;
      setState(() {
        _frontal = photo;
        _step = _AlbumStep.previewFrontal;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
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
    setState(() => _step = _AlbumStep.processingLateral);
    try {
      final photo = await _processAlbumPhoto(pick.path);
      if (!mounted) return;
      setState(() {
        _lateral = photo;
        _step = _AlbumStep.previewLateral;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// ML Kit FaceDetector → MediaPipe FaceMesh → yaw 계산 까지 한 사진을
  /// 분석 입력으로 변환. home_screen 의 이전 _processAlbumPhoto 와 동일 로직.
  Future<_AlbumPhoto> _processAlbumPhoto(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    final faces = await faceDetector.processImage(inputImage);
    await faceDetector.close();
    if (faces.isEmpty) {
      throw Exception('얼굴을 찾을 수 없습니다.\n다른 사진을 선택해 주세요.');
    }

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

    final byteData =
        await squareImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception('이미지를 디코딩할 수 없습니다');
    final rgba = Uint8List.sublistView(byteData.buffer.asUint8List());

    final imgW = squareImage.width.toDouble();
    final imgH = squareImage.height.toDouble();
    final bbox = faces.first.boundingBox;
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
    final result = processor.process(
      meshImage,
      box: box,
      boxScale: 1.2,
      boxMakeSquare: true,
      rotationDegrees: 0,
    );
    processor.close();

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

    // square 분기에서는 squareImage == original 이라 이 한 번의 dispose 로 둘 다
    // 해제된다. 미해제 시 사진당 full-res 네이티브 비트맵이 누적돼 궁합(2장
    // 연속 분석) 같은 흐름에서 메모리 압박 → iOS jetsam kill 을 유발.
    squareImage.dispose();

    return _AlbumPhoto(
      pngBytes: pngBytes,
      meshResult: result,
      width: outW,
      height: outH,
      yaw: yaw,
    );
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

enum _AlbumStep {
  ready,
  processingFrontal,
  previewFrontal,
  processingLateral,
  previewLateral,
}
