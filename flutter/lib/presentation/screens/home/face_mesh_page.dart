import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_reader/domain/models/face_analysis.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/face_metrics_lateral.dart';
import 'package:face_reader/presentation/providers/age_group_provider.dart';
import 'package:face_reader/presentation/providers/ethnicity_provider.dart';
import 'package:face_reader/presentation/providers/gender_provider.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/providers/tab_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'face_mesh_painter.dart';

class FaceMeshPage extends ConsumerStatefulWidget {
  const FaceMeshPage({super.key});

  @override
  ConsumerState<FaceMeshPage> createState() => _FaceMeshPageState();
}

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

  // Actual camera frame dimensions (may differ from previewSize on iOS)
  Size? _frameSize;

  List<FaceMeshLandmark>? _prevLandmarks;
  Color _overlayColor = Colors.redAccent;
  int _rotationCompensation = 0;

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
            title: const Text(
              '얼굴 랜드마크 감지',
              style: TextStyle(
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
    _cameraController?.dispose();
    _meshProcessor?.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
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
            child: Text(
              switch (_phase) {
                _CapturePhase.frontal =>
                  '폰을 벽면에 대고 얼굴 중심이 녹색 좌표계로 변할때까지 움직이세요. 왜곡을 줄여야 정확해집니다.',
                _CapturePhase.frontalDone =>
                  '✓ 정면 촬영 완료! 측면(3/4) 사진을 더 찍으면 매부리코·턱 윤곽·입술 돌출 등 프로파일 메트릭이 추가됩니다.',
                _CapturePhase.lateral =>
                  '${_lateralBannerText()}\n[yaw=${_currentYaw.toStringAsFixed(2)} ${_currentYawClass.name}]',
              },
              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
              textAlign: TextAlign.left,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureControls() {
    final bottom = MediaQuery.of(context).padding.bottom + 24;

    // Stage 1.5 — frontal done, pause for explicit user decision.
    if (_phase == _CapturePhase.frontalDone) {
      return Positioned(
        left: 20,
        right: 20,
        bottom: bottom,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _proceedToLateral,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.95),
                  foregroundColor: const Color(0xFF333333),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.rotate_right, size: 20),
                label: const Text('측면 촬영 시작하기',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: _skipLateral,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('정면만으로 분석하기',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }

    if (_phase == _CapturePhase.frontal) {
      // Stage 1 — original single-button frontal capture.
      return Positioned(
        left: 20,
        right: 20,
        bottom: bottom,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 52,
            child: ElevatedButton.icon(
              onPressed:
                  _isCapturing || _meshResult == null ? null : _startCapture,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isCapturing
                    ? const Color(0xFFFF9800)
                    : Colors.white.withValues(alpha: 0.85),
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
                  : const Icon(Icons.smart_toy, size: 20),
              label: Text(
                _isCapturing ? '${_capturedFrames.length}/5' : '관상학 데이터 분석',
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

  String _lateralBannerText() {
    switch (_currentYawClass) {
      case YawClass.frontal:
        return '측면(3/4) 사진. 한쪽 귀가 거의 안 보일 때까지 50~60도 돌려주세요.';
      case YawClass.threeQuarter:
        return '좋아요! 그대로 「측면 캡처」를 눌러주세요.';
      case YawClass.profile:
        return '거의 옆얼굴이에요. 조금만 정면으로 돌아오세요.';
      case YawClass.unusable:
        return '얼굴이 거의 안 보여요. 조금만 정면 쪽으로 돌려주세요.';
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

      if (highConfidence && stable && largEnough) {
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

    // Phase 1: Frontal capture done — transition to a pause/confirmation
    // step so the user gets explicit feedback that the frontal shot succeeded
    // before being asked to rotate their head for the lateral shot.
    if (_phase == _CapturePhase.frontal) {
      if (!mounted) return;
      setState(() {
        _frontalLandmarks = averaged;
        _frontalImageWidth = lastResult?.imageWidth;
        _frontalImageHeight = lastResult?.imageHeight;
        _phase = _CapturePhase.frontalDone;
        _capturedFrames.clear();
      });
      return;
    }

    // Phase 2: Lateral capture done — run full analysis with both.
    await _runAnalysis(lateralLandmarks: averaged);
    _capturedFrames.clear();
  }

  /// Skip the lateral capture and analyze frontal-only.
  Future<void> _skipLateral() async {
    if (_frontalLandmarks == null) return;
    await _runAnalysis(lateralLandmarks: null);
  }

  /// Transition from frontalDone → lateral phase (user explicitly elects to
  /// continue with the second capture).
  void _proceedToLateral() {
    setState(() {
      _phase = _CapturePhase.lateral;
    });
  }

  /// Final analysis + persistence step. Uses [_frontalLandmarks] as the primary
  /// input and optionally adds [lateralLandmarks] when available.
  Future<void> _runAnalysis({List<FaceMeshLandmark>? lateralLandmarks}) async {
    final frontal = _frontalLandmarks;
    if (frontal == null) return;
    final ethnicity = ref.read(ethnicityProvider);
    final gender = ref.read(genderProvider);
    final ageGroup = ref.read(ageGroupProvider);
    debugPrint('[Camera] analysis frontalW=$_frontalImageWidth '
        'H=$_frontalImageHeight lateral=${lateralLandmarks != null}');
    final report = analyzeFaceReading(
      landmarks: frontal,
      ethnicity: ethnicity,
      gender: gender,
      ageGroup: ageGroup,
      source: AnalysisSource.camera,
      imageWidth: _frontalImageWidth ?? 1,
      imageHeight: _frontalImageHeight ?? 1,
      lateralLandmarks: lateralLandmarks,
    );

    // Generate UUID upfront — used by both Hive and Supabase and also as the
    // thumbnail filename so they stay in lockstep.
    final id = const Uuid().v4();
    report.supabaseId = id;

    // Compress the still image captured in _startCapture() to a 128px WebP
    // thumbnail, same pipeline used by the album flow.
    final stillBytes = _captureStillBytes;
    _captureStillBytes = null;
    if (stillBytes != null) {
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          stillBytes,
          minWidth: 128,
          minHeight: 128,
          quality: 80,
          format: CompressFormat.webp,
        );
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$id.webp');
        await file.writeAsBytes(compressed);
        report.thumbnailPath = file.path;
      } catch (e) {
        debugPrint('[Thumbnail] save error: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isCapturing = false);
    ref.read(historyProvider.notifier).add(report);
    // 카메라로 분석한 직후엔 관상 탭 → 카메라 sub-tab을 기본으로 보여준다.
    ref.read(historyTabProvider.notifier).selectTab(0);
    ref.read(selectedTabProvider.notifier).selectTab(1);
    Navigator.of(context).pop();
    // Save to Supabase in background using the pre-assigned UUID
    SupabaseService().saveMetrics(report).catchError((e) {
      debugPrint('[Supabase] save error: $e');
      return '';
    });
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
          _currentYaw = yaw;
          _currentYawClass = yawClass;
          // Processor already applied rotation via rotationDegrees,
          // so landmarks are in screen-upright space — no painter rotation needed.
          _rotationCompensation = 0;
        });
        _prevLandmarks = List.of(result.landmarks);
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

enum _CapturePhase { frontal, frontalDone, lateral }
