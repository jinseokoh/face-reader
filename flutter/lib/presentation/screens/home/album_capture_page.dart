import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/data/services/face_metadata_client.dart';
import 'package:face_reader/domain/models/capture_result.dart';
import 'package:face_reader/domain/models/face_metadata.dart';
import 'package:face_reader/domain/services/face_metrics_lateral.dart';
import 'package:face_reader/presentation/screens/home/face_mesh_painter.dart';
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

enum _AlbumStep {
  ready,
  processingFrontal,
  previewFrontal,
  processingLateral,
  previewLateral,
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
  void initState() {
    super.initState();
    // 진입 직후 frontal picker 자동 호출.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickFrontal());
  }

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
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          body: _buildBody(),
        ),
      ),
    );
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
        ? '측면 윤곽을 확인 후 분석을 시작하세요.'
        : '정면 윤곽을 확인 후 분석을 시작하세요.';
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
                icon: const Icon(Icons.camera_alt, size: 20),
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

  Future<void> _afterFrontalConfirm() async {
    final wantLateral = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('측면 사진 첨부'),
        content: const Text(
            '코 모양 분석을 위해 측면 사진을 추가하시겠습니까?\n'
            '추가하지 않으면 코는 "정상 범주"로 처리됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('건너뛰기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('측면 추가'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (wantLateral == true) {
      await _pickLateral();
    } else {
      _runAnalysis();
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
    final image = frame.image;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception('이미지를 디코딩할 수 없습니다');
    final rgba = Uint8List.sublistView(byteData.buffer.asUint8List());

    final bbox = faces.first.boundingBox;
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final clamped = Rect.fromLTRB(
      bbox.left.clamp(0.0, imgW),
      bbox.top.clamp(0.0, imgH),
      bbox.right.clamp(0.0, imgW),
      bbox.bottom.clamp(0.0, imgH),
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
      width: image.width,
      height: image.height,
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

    final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (pngData == null) throw Exception('이미지 인코딩 실패');
    final pngBytes = Uint8List.sublistView(pngData.buffer.asUint8List());

    final yaw = estimateYaw(result.landmarks);
    debugPrint('[Album] processed image=${image.width}x${image.height} '
        'yaw=${yaw.toStringAsFixed(3)} class=${classifyYaw(yaw)}');

    return _AlbumPhoto(
      pngBytes: pngBytes,
      meshResult: result,
      width: image.width,
      height: image.height,
      yaw: yaw,
    );
  }
}
