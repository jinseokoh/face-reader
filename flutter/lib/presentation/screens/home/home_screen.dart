import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:face_reader/core/theme.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/data/services/analytics_service.dart';
import 'package:face_reader/data/services/face_metadata_client.dart';
import 'package:face_reader/domain/models/capture_result.dart';
import 'package:face_reader/domain/models/face_metadata.dart';
import 'package:face_reader/domain/services/face_metrics_lateral.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'album_preview_page.dart';
import 'demographic_confirm_screen.dart';
import 'face_mesh_page.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// One processed album image — bundle of bytes + landmarks + yaw classification.
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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isProcessing = false;
  OverlayEntry? _topMessageEntry;
  // Album flow 의 DeepFace 분석은 frontal pick 직후 background kickoff →
  // 측면 첨부 dialog + lateral pick + preview confirm 시간 동안 병렬 진행.
  Future<FaceMetadata?>? _albumMetadataFuture;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Text(
              '관상은 과학이다.',
              style: TextStyle(
                fontFamily: 'SongMyung',
                color: AppTheme.textPrimary,
                fontSize: 48,
                fontWeight: FontWeight.bold,
                height: 1.15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            const Text(
              'Facely, 안면 계측 데이터 기반 인공지능 관상앱.',
              style: AppText.displaySubtitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 56),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HomeActionButton(
                    label: '카메라로 촬영',
                    icon: Icons.camera_alt_outlined,
                    onPressed: _isProcessing ? null : _openCamera,
                  ),
                  const SizedBox(height: 12),
                  _HomeActionButton(
                    label: '앨범에서 선택',
                    icon: Icons.photo_library_outlined,
                    onPressed: _isProcessing ? null : _openAlbum,
                    busy: _isProcessing,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '얼굴 사진을 올리면 나이·성별·인종을 자동으로 추정하고\n관상 분석 전에 한 번 더 확인할 수 있습니다.',
                style: AppText.body.copyWith(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dismissTopMessage();
    super.dispose();
  }

  void _dismissTopMessage() {
    _topMessageEntry?.remove();
    _topMessageEntry = null;
  }

  Future<void> _openAlbum() async {
    AnalyticsService.instance.logAlbumOpen();
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final loggedIn = await showLoginBottomSheet(context, ref);
      if (!loggedIn) return;
    }

    final picker = ImagePicker();

    // Step 1: frontal photo
    _showTopMessage('정면 사진을 선택하세요.');
    final frontalPick = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (frontalPick == null) {
      _dismissTopMessage();
      return;
    }

    setState(() => _isProcessing = true);
    _AlbumPhoto frontal;
    try {
      frontal = await _processAlbumPhoto(frontalPick.path);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _dismissTopMessage();
        _showError(e.toString());
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isProcessing = false);

    // frontal 확정 직후 DeepFace background kickoff. 측면 첨부 여부 dialog +
    // lateral pick + preview confirm 시간 동안 병렬 진행.
    _albumMetadataFuture = _analyzeMetadata(File(frontalPick.path));

    // Preview must not show the top snackbar.
    _dismissTopMessage();
    // Show frontal preview; user taps "정면 분석" to continue to lateral step.
    final frontalConfirmed = await _showPreview(
      phase: AlbumPreviewPhase.frontal,
      photo: frontal,
    );
    if (!mounted || frontalConfirmed != true) return;

    // Step 2: lateral photo (OPTIONAL — 콧부리 분석 전용)
    // 생략 시 코 모양은 "정상 범주"로 fallback.
    final wantLateral = await _askAttachLateral();
    _AlbumPhoto? lateral;
    if (wantLateral == true) {
      _showTopMessage('두 눈은 보이지만 한쪽 귀가 살짝 안 보이는 측면 사진을 올려주세요.');
      final lateralPick = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (lateralPick != null) {
        setState(() => _isProcessing = true);
        try {
          lateral = await _processAlbumPhoto(lateralPick.path);
        } catch (e) {
          if (mounted) {
            setState(() => _isProcessing = false);
            _dismissTopMessage();
            _showError(e.toString());
          }
          return;
        }
        if (!mounted) return;
        setState(() => _isProcessing = false);

        _dismissTopMessage();
        final lateralConfirmed = await _showPreview(
          phase: AlbumPreviewPhase.lateral,
          photo: lateral,
        );
        if (!mounted || lateralConfirmed != true) return;
      }
    }

    _dismissTopMessage();
    await _runAnalysis(frontal: frontal, lateral: lateral);
  }

  /// 측면(3/4) 사진 첨부 여부 확인. cancel이면 null.
  Future<bool?> _askAttachLateral() async {
    return showDialog<bool>(
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
  }

  Future<void> _openCamera() async {
    AnalyticsService.instance.logCameraOpen();
    final result = await showModalBottomSheet<CaptureResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FaceMeshPage(),
    );
    if (!mounted || result == null) return;
    await _pushDemographicConfirm(result);
  }

  Future<void> _pushDemographicConfirm(CaptureResult result) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DemographicConfirmScreen(
          capture: result,
          metadataFuture: result.metadataFuture,
        ),
      ),
    );
  }

  /// Run the full ML-Kit-bbox + MediaPipe pipeline on a single image file and
  /// return everything needed to either display it or analyze it.
  Future<_AlbumPhoto> _processAlbumPhoto(String path) async {
    // ML Kit: face bbox
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

    // Decode → raw RGBA
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception('이미지를 디코딩할 수 없습니다');
    final rgba = Uint8List.sublistView(byteData.buffer.asUint8List());

    // BBox clamped + scaled
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

    // MediaPipe single-frame inference
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

    // Re-encode for display
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

  Future<void> _runAnalysis({
    required _AlbumPhoto frontal,
    _AlbumPhoto? lateral,
  }) async {
    final result = CaptureResult(
      frontalLandmarks: frontal.meshResult.landmarks,
      lateralLandmarks: lateral?.meshResult.landmarks,
      imageWidth: frontal.width,
      imageHeight: frontal.height,
      stillBytes: frontal.pngBytes,
      source: AnalysisSource.album,
      metadataFuture: _albumMetadataFuture,
    );
    // 사용 후 reset — 다음 album session 이 깨끗하게 시작되도록.
    _albumMetadataFuture = null;
    if (!mounted) return;
    await _pushDemographicConfirm(result);
  }

  /// DeepFace `/analyze` 호출 wrapper. R2 PUT + analyze 까지 실행. 실패 시
  /// null 로 완료 (분석 자체는 진행, picker default 로 fallback).
  Future<FaceMetadata?> _analyzeMetadata(File file) async {
    try {
      final meta = await FaceMetadataClient().analyze(file);
      debugPrint('[Home] DeepFace ok age=${meta.age} '
          'gender=${meta.gender} ethnicity=${meta.ethnicity}');
      return meta;
    } catch (e) {
      debugPrint('[Home] DeepFace failed (non-fatal): $e');
      return null;
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  Future<bool?> _showPreview({
    required AlbumPreviewPhase phase,
    required _AlbumPhoto photo,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AlbumPreviewPage(
        imageBytes: photo.pngBytes,
        meshResult: photo.meshResult,
        imageWidth: photo.width,
        imageHeight: photo.height,
        phase: phase,
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  void _showTopMessage(String msg) {
    _dismissTopMessage();
    final mq = MediaQuery.of(context);
    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: mq.padding.top + 12,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.textPrimary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              msg,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    _topMessageEntry = entry;
  }
}

class _HomeActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  const _HomeActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.textPrimary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.surface,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
    );
  }
}
