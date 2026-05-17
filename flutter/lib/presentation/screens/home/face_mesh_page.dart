import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/data/services/face_metadata_client.dart';
import 'package:face_reader/domain/models/capture_result.dart';
import 'package:face_reader/domain/models/face_analysis.dart';
import 'package:face_reader/domain/models/face_metadata.dart';
import 'package:face_reader/domain/services/face_metrics_lateral.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:path_provider/path_provider.dart';

import 'face_mesh_painter.dart';

class FaceMeshPage extends ConsumerStatefulWidget {
  const FaceMeshPage({super.key});

  @override
  ConsumerState<FaceMeshPage> createState() => _FaceMeshPageState();
}

enum _CapturePhase { frontal, lateral }

class _FaceMeshPageState extends ConsumerState<FaceMeshPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  FaceMeshProcessor? _meshProcessor;
  FaceMeshResult? _meshResult;
  bool _isProcessing = false;
  bool _isInitialized = false;
  String? _error;

  bool _isCapturing = false;
  final List<List<FaceMeshLandmark>> _capturedFrames = [];
  // Still image captured via takePicture() at the moment the user taps the
  // analyze button. Used to produce a 128px WebP thumbnail attached to the
  // FaceReadingReport — same pipeline as the album flow.
  Uint8List? _captureStillBytes;
  // DeepFace `/analyze` 가 frontal still 확보 직후 background 로 kickoff 되어
  // 측면 캡처·picker UI 시간 동안 병렬 진행. 실패해도 null 로 완료 → caller
  // 가 default 로 fallback. 한 capture 세션당 한 번만 발사.
  Future<FaceMetadata?>? _metadataFuture;

  // Two-stage capture: first the frontal selfie, then a 3/4-yaw lateral shot
  // for nose-bridge / chin-profile / lip-protrusion metrics. Lateral is
  // optional — user may skip and get a frontal-only report.
  _CapturePhase _phase = _CapturePhase.frontal;
  List<FaceMeshLandmark>? _frontalLandmarks;
  int? _frontalImageWidth;
  int? _frontalImageHeight;
  // Live yaw class updated from the mesh stream — drives the lateral
  // capture-ready indicator.
  YawClass _currentYawClass = YawClass.frontal;
  double _currentYaw = 0;

  // Transient phase-title overlay ("정면 사진" / "측면 사진") — flips in and
  // fades out as a context cue when the capture phase changes.
  String? _phaseTitle;
  int _phaseTitleToken = 0;
  // false 면 tap-to-dismiss modal — frontal→lateral 전환 시 사용자가
  // "측면 시작" 누를 때까지 instructional overlay 가 유지된다.
  bool _phaseTitleDismissible = true;
  // phase title 이 modal 로 떠 있는 동안에는 lateral camera 가 background 에서
  // 흐르고 있어도 yaw-driven auto-countdown 이 발동하면 안 된다.
  bool get _phaseTitleBlocking =>
      _phaseTitle != null && !_phaseTitleDismissible;

  // Actual camera frame dimensions (may differ from previewSize on iOS)
  Size? _frameSize;

  List<FaceMeshLandmark>? _prevLandmarks;
  Color _overlayColor = Colors.redAccent;
  int _rotationCompensation = 0;

  // overlay 가 green 으로 안정되면 자동 카운트다운 (3→2→1→캡처). green 이
  // 깨지면 즉시 reset. 사용자가 button 을 누를 필요 없음.
  Timer? _countdownTimer;
  int? _countdownRemaining;

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
              _phase == _CapturePhase.frontal ? '얼굴 정면' : '얼굴 측면',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              IconButton(
                onPressed: _close,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          body: _buildBody(),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _cameraController?.dispose();
    _meshProcessor?.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    // Show the "정면 사진" title as a context cue once the page settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showPhaseTitle('얼굴 정면');
    });
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

    if (!_isInitialized || _cameraController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final controller = _cameraController!;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview + mesh overlay
        Builder(builder: (context) {
          final previewSize = controller.value.previewSize;
          if (previewSize == null) return const SizedBox();
          // Portrait aspect ratio: always shorter / longer so ratio < 1
          final shorter = min(previewSize.width, previewSize.height);
          final longer = max(previewSize.width, previewSize.height);
          final aspectRatio = shorter / longer;

          return Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),
                  if (_meshResult != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: FaceMeshPainter(
                            result: _meshResult!,
                            rotationCompensation: _rotationCompensation,
                            lensDirection: _cameras[_cameraIndex].lensDirection,
                            overlayColor: _overlayColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        // Bottom buttons: dependent on capture phase.
        if (_isInitialized) _buildCaptureControls(),
        // Instruction banner (on top of camera) — switches text in lateral phase.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.black.withValues(alpha: 0.6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _phase == _CapturePhase.frontal
                      ? '폰을 수직으로 세우고 얼굴 좌표계가 녹색으로 변할때 까지 움직이세요.'
                      : _lateralBannerText(),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, height: 1.4),
                  textAlign: TextAlign.left,
                ),
                if (_phase == _CapturePhase.lateral) ...[
                  const SizedBox(height: 6),
                  _YawHint(
                    yaw: _currentYaw,
                    yawClass: _currentYawClass,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Auto-countdown big number (3→2→1) — fires when overlay is stably
        // green. Cancelled if green is broken.
        if (_countdownRemaining != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final scale = Tween<double>(begin: 0.6, end: 1.0)
                        .animate(anim);
                    return FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: scale, child: child),
                    );
                  },
                  child: Container(
                    key: ValueKey(_countdownRemaining),
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.55),
                      border: Border.all(
                        color: Colors.greenAccent.withValues(alpha: 0.85),
                        width: 4,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$_countdownRemaining',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 88,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Transient phase-title overlay (fires at page open and at
        // frontal→lateral transition) — card-flip animation. modal 일 땐
        // "측면 시작" 버튼 받게 IgnorePointer 비활성.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _phaseTitle == null || _phaseTitleDismissible,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                final rotate = Tween<double>(begin: 1.2, end: 0.0)
                    .chain(CurveTween(curve: Curves.easeOutCubic))
                    .animate(anim);
                return FadeTransition(
                  opacity: anim,
                  child: AnimatedBuilder(
                    animation: rotate,
                    builder: (context, c) => Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(rotate.value),
                      child: c,
                    ),
                    child: child,
                  ),
                );
              },
              child: _phaseTitle == null
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : Center(
                      key: ValueKey(_phaseTitle),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 24),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_phaseMeshAsset(_phaseTitle!) != null) ...[
                              Image.asset(
                                _phaseMeshAsset(_phaseTitle!)!,
                                height: 200,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 16),
                            ],
                            Text(
                              _phaseTitle!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 3,
                              ),
                            ),
                            if (!_phaseTitleDismissible) ...[
                              const SizedBox(height: 14),
                              const Text(
                                '한쪽 귀가 살짝 안 보일 때까지\n고개를 천천히 옆으로 돌려주세요.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  onPressed: _dismissPhaseTitle,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF333333),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 28),
                                  ),
                                  child: const Text(
                                    '측면 시작',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureControls() {
    final bottom = MediaQuery.of(context).padding.bottom + 24;

    if (_phase == _CapturePhase.frontal) {
      // Stage 1 — original single-button frontal capture.
      final green = _meshResult != null &&
          _computeOverlayColor(_meshResult!) == Colors.greenAccent;
      final ready = green && !_isCapturing;
      return Positioned(
        left: 20,
        right: 20,
        bottom: bottom,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: ready ? _startCapture : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isCapturing
                    ? const Color(0xFFFF9800)
                    : (ready
                        ? Colors.white.withValues(alpha: 0.95)
                        : Colors.white.withValues(alpha: 0.5)),
                foregroundColor:
                    _isCapturing ? Colors.white : const Color(0xFF333333),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isCapturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt, size: 20),
              label: Text(
                _isCapturing ? '${_capturedFrames.length}/5' : '정면 캡쳐',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      );
    }

    // Stage 2 — lateral capture: skip button + capture (gated on yaw).
    final ready = _currentYawClass == YawClass.threeQuarter && !_isCapturing;
    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Skip — frontal-only fallback
          SizedBox(
            height: 52,
            child: TextButton(
              onPressed: _isCapturing ? null : _skipLateral,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('건너뛰기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          // Capture (gated on yaw)
          SizedBox(
            width: 180,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: ready ? _startCapture : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isCapturing
                    ? const Color(0xFFFF9800)
                    : (ready
                        ? Colors.white.withValues(alpha: 0.95)
                        : Colors.white.withValues(alpha: 0.5)),
                foregroundColor:
                    _isCapturing ? Colors.white : const Color(0xFF333333),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isCapturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt, size: 20),
              label: Text(
                _isCapturing
                    ? '${_capturedFrames.length}/5'
                    : (ready ? '측면 캡처' : '고개 회전 중...'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _close() {
    _closeCamera();
    Navigator.of(context).pop();
  }

  Future<void> _closeCamera() async {
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
    await _cameraController?.dispose();
    _cameraController = null;
    _meshProcessor?.close();
    _meshProcessor = null;
    _meshResult = null;
    _prevLandmarks = null;
    _isInitialized = false;
    _isProcessing = false;
  }

  Color _computeOverlayColor(FaceMeshResult result) {
    final landmarks = result.landmarks;
    if (landmarks.isEmpty) return Colors.redAccent;

    final highConfidence = result.score >= 0.85;

    bool stable = false;
    if (_prevLandmarks != null && _prevLandmarks!.length == landmarks.length) {
      double totalDist = 0;
      for (int i = 0; i < landmarks.length; i++) {
        final dx = landmarks[i].x - _prevLandmarks![i].x;
        final dy = landmarks[i].y - _prevLandmarks![i].y;
        totalDist += sqrt(dx * dx + dy * dy);
      }
      final avgDist = totalDist / landmarks.length;
      stable = avgDist < 0.005;
    }

    if (landmarks.length > 454) {
      final faceWidth = (landmarks[454].x - landmarks[234].x).abs();
      final largEnough = faceWidth > 0.25;

      final yawOk = _phase == _CapturePhase.frontal
          ? _currentYawClass == YawClass.frontal
          : _currentYawClass == YawClass.threeQuarter;

      if (highConfidence && stable && largEnough && yawOk) {
        return Colors.greenAccent;
      }
    }

    return Colors.redAccent;
  }

  /// Compute rotation compensation following the official mediapipe_face_mesh
  /// camera demo (flutter_vision_ai_demos).
  int? _computeRotationCompensation() {
    const Map<DeviceOrientation, int> deviceOrientationDegrees = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    final controller = _cameraController;
    if (controller == null) return null;

    final camera = _cameras[_cameraIndex];
    final deviceRotation = deviceOrientationDegrees[controller.value.deviceOrientation];
    if (deviceRotation == null) return null;

    if (Platform.isAndroid) {
      if (camera.lensDirection == CameraLensDirection.front) {
        return (camera.sensorOrientation + deviceRotation) % 360;
      }
      return (camera.sensorOrientation - deviceRotation + 360) % 360;
    }

    if (Platform.isIOS) {
      return deviceRotation;
    }

    return null;
  }

  Future<void> _finishCapture() async {
    _isCapturing = false;
    if (_capturedFrames.isEmpty) return;

    final averaged = averageLandmarks(_capturedFrames);
    final lastResult = _meshResult;

    // Phase 1: Frontal capture done — transition directly to lateral with an
    // animated "측면 사진" title overlay giving the user a clear context cue.
    if (_phase == _CapturePhase.frontal) {
      if (!mounted) return;
      setState(() {
        _frontalLandmarks = averaged;
        _frontalImageWidth = lastResult?.imageWidth;
        _frontalImageHeight = lastResult?.imageHeight;
        _phase = _CapturePhase.lateral;
        _capturedFrames.clear();
      });
      // 측면 안내는 tap-to-proceed modal — 자동 dismiss 안 됨. 사용자가
      // "측면 시작" 누르기 전까지 background camera 의 auto-countdown 도 차단.
      _showPhaseTitle('얼굴 측면', autoDismiss: false);
      return;
    }

    // Phase 2: Lateral capture done — run full analysis with both.
    await _runAnalysis(lateralLandmarks: averaged);
    _capturedFrames.clear();
  }

  /// overlay 색이 바뀔 때마다 호출. green & idle 상태면 카운트다운 시작,
  /// red 로 깨지면 즉시 reset. 한 frame 의 색 정보만 보고 동작.
  /// modal phase title 이 떠 있는 동안엔 background camera 가 흐르고 있어도
  /// 카운트다운을 발동시키지 않는다 (사용자가 안내 안 봤을 수도 있음).
  void _evaluateAutoCountdown(Color overlayColor) {
    final isGreen = overlayColor == Colors.greenAccent;
    final inProgress = _countdownRemaining != null;

    if (_phaseTitleBlocking) {
      if (inProgress) _cancelCountdown();
      return;
    }

    if (isGreen && !_isCapturing && !inProgress) {
      _startCountdown();
    } else if (!isGreen && inProgress) {
      _cancelCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdownRemaining = 3);
    _countdownTimer =
        Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final r = _countdownRemaining;
      if (r == null) {
        timer.cancel();
        return;
      }
      if (r <= 1) {
        timer.cancel();
        setState(() => _countdownRemaining = null);
        // green 유지 확인 후 캡처. _startCapture 가 _isCapturing 체크함.
        if (_overlayColor == Colors.greenAccent && !_isCapturing) {
          _startCapture();
        }
        return;
      }
      setState(() => _countdownRemaining = r - 1);
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdownRemaining != null) {
      setState(() => _countdownRemaining = null);
    }
  }

  /// DeepFace `/analyze` 호출 wrapper. PNG bytes → 임시 파일 → R2 PUT + analyze.
  /// 실패 시 null 반환 (분석 자체는 진행). 임시 파일은 호출 후 정리.
  Future<FaceMetadata?> _analyzeMetadata(Uint8List bytes) async {
    File? tempFile;
    try {
      final dir = await getTemporaryDirectory();
      tempFile = File(
          '${dir.path}/face_analyze_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(bytes);
      final meta = await FaceMetadataClient().analyze(tempFile);
      debugPrint('[FaceMesh] DeepFace ok age=${meta.age} '
          'gender=${meta.gender} ethnicity=${meta.ethnicity}');
      return meta;
    } catch (e) {
      debugPrint('[FaceMesh] DeepFace failed (non-fatal): $e');
      return null;
    } finally {
      try {
        await tempFile?.delete();
      } catch (_) {}
    }
  }

  Future<void> _initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No cameras found');
        return;
      }

      _cameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;

      _meshProcessor = await FaceMeshProcessor.create(
        delegate: FaceMeshDelegate.xnnpack,
        enableRoiTracking: true,
        enableSmoothing: true,
        minDetectionConfidence: 0.5,
        minTrackingConfidence: 0.5,
      );

      await _startCamera();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _lateralBannerText() {
    switch (_currentYawClass) {
      case YawClass.frontal:
        return '한쪽 귀가 거의 안보일때까지 얼굴을 돌려주세요.';
      case YawClass.threeQuarter:
        return '좋아요! 그대로 「측면 캡처」를 눌러주세요.';
      case YawClass.profile:
        return '거의 옆얼굴이에요. 조금만 정면으로 돌아오세요.';
      case YawClass.unusable:
        return '얼굴이 거의 안 보여요. 조금만 정면 쪽으로 돌려주세요.';
    }
  }

  void _onCameraFrame(CameraImage image) {
    if (_isProcessing || _meshProcessor == null) return;
    _isProcessing = true;

    // Capture actual frame dimensions on first frame
    if (_frameSize == null) {
      final camera = _cameras[_cameraIndex];
      final rot = camera.sensorOrientation;
      final swapped = (rot == 90 || rot == 270);
      final w = swapped ? image.height.toDouble() : image.width.toDouble();
      final h = swapped ? image.width.toDouble() : image.height.toDouble();
      _frameSize = Size(w, h);
      final ps = _cameraController?.value.previewSize;
      final shorter = min(ps!.width, ps.height);
      final longer = max(ps.width, ps.height);
      // ignore: avoid_print
      print('[FaceMesh] platform=${Platform.operatingSystem}  '
          'rawFrame=${image.width}x${image.height}  '
          'previewSize=$ps  aspectRatio=${(shorter / longer).toStringAsFixed(4)}  '
          'bytesPerRow=${image.planes[0].bytesPerRow}  '
          'sensorOrientation=$rot  rotationCompensation=$_rotationCompensation  '
          'isFront=${_cameras[_cameraIndex].lensDirection == CameraLensDirection.front}');
    }

    _processFrame(image).then((result) {
      if (mounted && result != null) {
        // Log Dart-level landmark values (once)
        if (_frameSize != null && result.landmarks.isNotEmpty && _meshResult == null) {
          final lm0 = result.landmarks[0];
          final lm234 = result.landmarks[234];
          final lm454 = result.landmarks[454];
          // ignore: avoid_print
          print('[FaceMesh-Dart] imageW=${result.imageWidth} imageH=${result.imageHeight} '
              'lm0=(${lm0.x.toStringAsFixed(4)},${lm0.y.toStringAsFixed(4)}) '
              'lm234=(${lm234.x.toStringAsFixed(4)},${lm234.y.toStringAsFixed(4)}) '
              'lm454=(${lm454.x.toStringAsFixed(4)},${lm454.y.toStringAsFixed(4)})');
        }
        final color = _computeOverlayColor(result);
        final yaw = result.landmarks.isNotEmpty
            ? estimateYaw(result.landmarks)
            : 0.0;
        final yawClass = result.landmarks.isNotEmpty
            ? classifyYaw(yaw)
            : YawClass.unusable;
        setState(() {
          _meshResult = result;
          _overlayColor = color;
          _currentYaw = yaw;
          _currentYawClass = yawClass;
          // Processor already applied rotation via rotationDegrees,
          // so landmarks are in screen-upright space — no painter rotation needed.
          _rotationCompensation = 0;
        });
        _prevLandmarks = List.of(result.landmarks);
        _evaluateAutoCountdown(color);
        if (_isCapturing && result.landmarks.isNotEmpty) {
          _capturedFrames.add(List.of(result.landmarks));
          debugPrint(
              '[Camera] frame ${_capturedFrames.length}/5 (phase=$_phase yawClass=$yawClass)');
          if (_capturedFrames.length >= 5) {
            _finishCapture();
          }
        }
      }
      _isProcessing = false;
    }).catchError((e) {
      _isProcessing = false;
    });
  }


  Future<FaceMeshResult?> _processFrame(CameraImage image) async {
    final rotComp = _computeRotationCompensation();
    if (rotComp == null) return null;
    _rotationCompensation = rotComp;

    try {
      if (Platform.isAndroid) {
        final planes = image.planes;
        if (planes.isEmpty) return null;

        final Uint8List yPlane;
        final Uint8List vuPlane;
        final int yBytesPerRow;
        final int vuBytesPerRow;

        if (planes.length >= 2) {
          // Multi-plane NV21: planes[0] = Y, planes[1] = VU interleaved
          yPlane = planes[0].bytes;
          vuPlane = planes[1].bytes;
          yBytesPerRow = planes[0].bytesPerRow;
          vuBytesPerRow = planes[1].bytesPerRow;
        } else {
          // Single-plane NV21: Y + VU packed in one buffer
          final plane = planes.first;
          final rowStride = plane.bytesPerRow;
          final ySize = rowStride * image.height;
          final chromaHeight = (image.height + 1) ~/ 2;
          final vuSize = rowStride * chromaHeight;
          if (plane.bytes.length < ySize + vuSize) return null;
          final bytes = plane.bytes;
          yPlane = Uint8List.sublistView(bytes, 0, ySize);
          vuPlane = Uint8List.sublistView(bytes, ySize, ySize + vuSize);
          yBytesPerRow = rowStride;
          vuBytesPerRow = rowStride;
        }

        final nv21Image = FaceMeshNv21Image(
          yPlane: yPlane,
          vuPlane: vuPlane,
          width: image.width,
          height: image.height,
          yBytesPerRow: yBytesPerRow,
          vuBytesPerRow: vuBytesPerRow,
        );
        return _meshProcessor!.processNv21(
          nv21Image,
          rotationDegrees: rotComp,
        );
      } else {
        final pixels = image.planes[0].bytes;
        final meshImage = FaceMeshImage(
          pixels: pixels,
          width: image.width,
          height: image.height,
          bytesPerRow: image.planes[0].bytesPerRow,
          pixelFormat: FaceMeshPixelFormat.bgra,
        );
        return _meshProcessor!.process(
          meshImage,
          rotationDegrees: rotComp,
        );
      }
    } catch (e) {
      debugPrint('Face mesh error: $e');
      return null;
    }
  }

  /// 캡처 완료 후 caller (HomeScreen) 에 raw 데이터만 돌려준다. demographic
  /// 확인·분석·저장은 DemographicConfirmScreen 이 담당.
  Future<void> _runAnalysis({List<FaceMeshLandmark>? lateralLandmarks}) async {
    final frontal = _frontalLandmarks;
    if (frontal == null) return;
    debugPrint('[Camera] capture complete frontalW=$_frontalImageWidth '
        'H=$_frontalImageHeight lateral=${lateralLandmarks != null}');

    final stillBytes = _captureStillBytes;
    _captureStillBytes = null;

    final result = CaptureResult(
      frontalLandmarks: frontal,
      lateralLandmarks: lateralLandmarks,
      imageWidth: _frontalImageWidth ?? 1,
      imageHeight: _frontalImageHeight ?? 1,
      stillBytes: stillBytes,
      source: AnalysisSource.camera,
      metadataFuture: _metadataFuture,
    );

    if (!mounted) return;
    setState(() => _isCapturing = false);
    Navigator.of(context).pop(result);
  }

  /// Asset path for the mesh-guide image that accompanies a phase title.
  /// Returns null when the title doesn't match a known phase.
  String? _phaseMeshAsset(String title) {
    if (title.contains('정면')) return 'assets/images/mesh-front.png';
    if (title.contains('측면')) return 'assets/images/mesh-side.png';
    return null;
  }

  /// Flash a full-screen phase-title overlay (e.g. "정면 사진" / "측면 사진")
  /// that flips in. [autoDismiss] true 면 1.8초 후 fade out, false 면 사용자
  /// 탭이나 [_dismissPhaseTitle] 호출 시까지 유지 (modal instructional).
  void _showPhaseTitle(String title, {bool autoDismiss = true}) {
    final token = ++_phaseTitleToken;
    setState(() {
      _phaseTitle = title;
      _phaseTitleDismissible = autoDismiss;
    });
    if (autoDismiss) {
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (!mounted || _phaseTitleToken != token) return;
        setState(() => _phaseTitle = null);
      });
    }
  }

  void _dismissPhaseTitle() {
    if (!mounted) return;
    setState(() {
      _phaseTitle = null;
      _phaseTitleDismissible = true;
    });
  }

  /// Skip the lateral capture and analyze frontal-only.
  Future<void> _skipLateral() async {
    if (_frontalLandmarks == null) return;
    await _runAnalysis(lateralLandmarks: null);
  }

  Future<void> _startCamera() async {
    final camera = _cameras[_cameraIndex];

    _cameraController?.dispose();
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();

    if (!mounted) return;

    _cameraController!.startImageStream(_onCameraFrame);

    setState(() {
      _isInitialized = true;
      _error = null;
    });
  }

  Future<void> _startCapture() async {
    if (_meshResult == null) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    debugPrint('[Camera] _startCapture phase=$_phase');

    // Only the frontal capture takes a still picture for the thumbnail —
    // the lateral capture reuses the frontal still. On Android takePicture()
    // requires stopping the image stream, so we only pay that cost once.
    if (_phase == _CapturePhase.frontal) {
      _captureStillBytes = null;
      _metadataFuture = null;
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        final XFile shot = await controller.takePicture();
        _captureStillBytes = await shot.readAsBytes();
      } catch (e) {
        debugPrint('[Camera] takePicture failed: $e');
      } finally {
        try {
          if (!controller.value.isStreamingImages) {
            await controller.startImageStream(_onCameraFrame);
          }
        } catch (e) {
          debugPrint('[Camera] restart stream failed: $e');
        }
      }

      // frontal still 확보 시점에 DeepFace 분석 background kickoff. 측면 캡처
      // + picker UI 시간 동안 병렬 진행.
      final bytes = _captureStillBytes;
      if (bytes != null) {
        _metadataFuture = _analyzeMetadata(bytes);
      }
    }

    if (!mounted) return;
    setState(() {
      _isCapturing = true;
      _capturedFrames.clear();
    });
    debugPrint('[Camera] capture started, frames=0/5');

    // Safety: if frames don't arrive within 6 seconds (tracking failure,
    // severe yaw, etc.), cancel the capture so the UI isn't stuck.
    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_isCapturing && _capturedFrames.length < 5) {
        debugPrint('[Camera] capture timeout — collected ${_capturedFrames.length}/5');
        setState(() {
          _isCapturing = false;
          _capturedFrames.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('캡처에 실패했어요. 얼굴이 잘 보이도록 고개 각도를 조정하고 다시 시도해 주세요.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }
}

/// 측면 캡처 중 한 줄 힌트 + 회전각 도수.
/// - 좌: yawClass 별 한 줄 안내 (색은 zone color)
/// - 우: 0°~90° 도수 (piecewise 매핑 — 0.70→45°, 0.88→60°, 0.95→75°)
class _YawHint extends StatelessWidget {
  final double yaw;
  final YawClass yawClass;

  const _YawHint({required this.yaw, required this.yawClass});

  static const _frontalEnd = 0.70;
  static const _threeQuarterEnd = 0.88;
  static const _profileEnd = 0.95;

  static int yawToDegrees(double y) {
    final a = y.abs().clamp(0.0, 1.5);
    if (a < _frontalEnd) return (a / _frontalEnd * 45).round();
    if (a < _threeQuarterEnd) {
      return (45 +
              (a - _frontalEnd) / (_threeQuarterEnd - _frontalEnd) * 15)
          .round();
    }
    if (a < _profileEnd) {
      return (60 +
              (a - _threeQuarterEnd) / (_profileEnd - _threeQuarterEnd) * 15)
          .round();
    }
    return (75 + (a - _profileEnd) / 0.05 * 15).clamp(0, 99).round();
  }

  Color get _zoneColor {
    switch (yawClass) {
      case YawClass.frontal:
        return const Color(0xFF9E9E9E);
      case YawClass.threeQuarter:
        return const Color(0xFF4CAF50);
      case YawClass.profile:
        return const Color(0xFFFF9800);
      case YawClass.unusable:
        return const Color(0xFFF44336);
    }
  }

  String get _hint {
    switch (yawClass) {
      case YawClass.frontal:
        return '→ 얼굴을 더 옆으로 돌려주세요';
      case YawClass.threeQuarter:
        return '● 지금이에요! 버튼을 누르세요';
      case YawClass.profile:
        return '← 조금만 정면으로 되돌리세요';
      case YawClass.unusable:
        return '← 더 많이 정면으로 되돌리세요';
    }
  }

  @override
  Widget build(BuildContext context) {
    final degrees = yawToDegrees(yaw);
    return Row(
      children: [
        Expanded(
          child: Text(
            _hint,
            style: TextStyle(
              color: _zoneColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '회전각 $degrees°',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
