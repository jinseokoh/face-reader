import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/face_metadata_client.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/domain/models/face_analysis.dart';
import 'package:facely/domain/models/face_metadata.dart';
import 'package:facely/domain/services/face_metrics_lateral.dart';
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

  // Transient phase-title overlay ("정면 사진" / "측면 사진") — flips in and
  // fades out as a context cue when the capture phase changes.
  String? _phaseTitle;
  int _phaseTitleToken = 0;
  // false 면 tap-to-dismiss modal — frontal→lateral 전환 시 사용자가
  // "측면 시작" 누를 때까지 instructional overlay 가 유지된다.
  bool _phaseTitleDismissible = true;
  // Actual camera frame dimensions (may differ from previewSize on iOS)
  Size? _frameSize;

  List<FaceMeshLandmark>? _prevLandmarks;

  Color _overlayColor = Colors.redAccent;
  int _rotationCompensation = 0;
  // overlay 가 green 으로 안정되면 자동 카운트다운 (3→2→1→캡처). green 이
  // 깨지면 즉시 reset. 사용자가 button 을 누를 필요 없음.
  Timer? _countdownTimer;

  int? _countdownRemaining;
  // phase title 이 modal 로 떠 있는 동안에는 lateral camera 가 background 에서
  // 흐르고 있어도 yaw-driven auto-countdown 이 발동하면 안 된다.
  bool get _phaseTitleBlocking =>
      _phaseTitle != null && !_phaseTitleDismissible;

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
    // 진입 시 정면 안내 modal — 사용자가 "확인" 누를 때까지 mesh overlay 와
    // auto-countdown 모두 차단. lateral 안내와 동일한 mechanism.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showPhaseTitle('얼굴 정면', autoDismiss: false);
    });
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
                  // modal 안내 떠 있는 동안에는 mesh overlay 도 숨김 — 사용자에게
                  // popup 내용에만 집중시킴.
                  if (_meshResult != null && !_phaseTitleBlocking)
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
        // 정면·측면 둘 다 auto-countdown 으로만 캡처 — button 없음.
        // Instruction banner (on top of camera) — switches text in lateral phase.
        // modal 안내 떠 있는 동안에는 함께 숨김 (popup 단독 노출).
        if (!_phaseTitleBlocking) Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.black.withValues(alpha: 0.6),
            child: Text(
              _phase == _CapturePhase.frontal
                  ? '안면 계측 점선이 녹색으로 변해야 합니다.'
                  : '한쪽 귀가 안 보일 때까지 얼굴을 돌려주세요.',
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, height: 1.4),
              textAlign: TextAlign.left,
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
                  : Stack(
                      key: ValueKey(_phaseTitle),
                      children: [
                        // modal dim 배경 — popup 분위기. tap-to-dismiss 아닌
                        // 명시적 button 으로만 닫히도록 IgnorePointer 는 부모
                        // AnimatedSwitcher 가 dismissible 여부로 제어.
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
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
                                    color: Color(0xFF1F1F1F),
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                if (!_phaseTitleDismissible) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    _phaseInstruction(_phaseTitle!),
                                    style: const TextStyle(
                                      color: Color(0xFF555555),
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: _dismissPhaseTitle,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1F1F1F),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Text(
                                        _phaseConfirmLabel(_phaseTitle!),
                                        style: const TextStyle(
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
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdownRemaining != null) {
      setState(() => _countdownRemaining = null);
    }
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

  void _dismissPhaseTitle() {
    if (!mounted) return;
    setState(() {
      _phaseTitle = null;
      _phaseTitleDismissible = true;
    });
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


  /// modal 의 dismiss button label — phase 에 맞춰 작명.
  String _phaseConfirmLabel(String title) {
    if (title.contains('정면')) return '확인';
    return '측면 시작';
  }

  /// modal popup 본문에 표시되는 phase 별 안내 문구.
  String _phaseInstruction(String title) {
    if (title.contains('정면')) {
      return '안면 계측 점선이 녹색으로 변할 때까지 조정 후 3초 이상 유지하면 자동 촬영됩니다.';
    }
    return '한쪽 귀가 살짝 안 보일 때까지\n고개를 천천히 옆으로 돌려주세요.';
  }

  /// Asset path for the guide image that accompanies a phase title.
  /// Returns null when the title doesn't match a known phase.
  String? _phaseMeshAsset(String title) {
    if (title.contains('정면')) return 'assets/images/frontal.png';
    if (title.contains('측면')) return 'assets/images/lateral.png';
    return null;
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
}

