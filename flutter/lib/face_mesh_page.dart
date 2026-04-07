import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'face_analysis.dart';
import 'face_mesh_painter.dart';
import 'face_reference_data.dart';
import 'report_page.dart';

class FaceMeshPage extends StatefulWidget {
  const FaceMeshPage({super.key});

  @override
  State<FaceMeshPage> createState() => _FaceMeshPageState();
}

class _FaceMeshPageState extends State<FaceMeshPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  FaceMeshProcessor? _meshProcessor;
  FaceMeshResult? _meshResult;
  bool _isProcessing = false;
  bool _isInitialized = false;
  String? _error;

  Ethnicity _ethnicity = Ethnicity.eastAsian;
  bool _isCapturing = false;
  final List<List<FaceMeshLandmark>> _capturedFrames = [];

  // Tracking quality
  List<FaceMeshLandmark>? _prevLandmarks;
  Color _overlayColor = Colors.redAccent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No cameras found');
        return;
      }

      // Prefer front camera
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

  void _onCameraFrame(CameraImage image) {
    if (_isProcessing || _meshProcessor == null) return;
    _isProcessing = true;

    _processFrame(image).then((result) {
      if (mounted && result != null) {
        final color = _computeOverlayColor(result);
        setState(() {
          _meshResult = result;
          _overlayColor = color;
        });
        _prevLandmarks = List.of(result.landmarks);
        // Collect frames for analysis
        if (_isCapturing && result.landmarks.isNotEmpty) {
          _capturedFrames.add(List.of(result.landmarks));
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
    final camera = _cameras[_cameraIndex];
    final rotationDegrees = camera.sensorOrientation;
    final isFront = camera.lensDirection == CameraLensDirection.front;

    try {
      if (Platform.isAndroid) {
        // NV21 format: single buffer with Y plane followed by interleaved VU
        final fullBuffer = image.planes[0].bytes;
        final ySize = image.width * image.height;
        final yPlane = fullBuffer.buffer.asUint8List(fullBuffer.offsetInBytes, ySize);
        final vuPlane = fullBuffer.buffer.asUint8List(fullBuffer.offsetInBytes + ySize, fullBuffer.length - ySize);
        final nv21Image = FaceMeshNv21Image(
          yPlane: yPlane,
          vuPlane: vuPlane,
          width: image.width,
          height: image.height,
        );
        return _meshProcessor!.processNv21(
          nv21Image,
          rotationDegrees: rotationDegrees,
          mirrorHorizontal: isFront,
        );
      } else {
        // iOS: BGRA format
        final pixels = image.planes[0].bytes;
        final meshImage = FaceMeshImage(
          pixels: pixels,
          width: image.width,
          height: image.height,
        );
        return _meshProcessor!.process(
          meshImage,
          rotationDegrees: rotationDegrees,
          mirrorHorizontal: isFront,
        );
      }
    } catch (e) {
      debugPrint('Face mesh error: $e');
      return null;
    }
  }

  Color _computeOverlayColor(FaceMeshResult result) {
    final landmarks = result.landmarks;
    if (landmarks.isEmpty) return Colors.redAccent;

    // 1. Confidence score
    final highConfidence = result.score >= 0.85;

    // 2. Stability: average landmark movement vs previous frame
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

    // 3. Face size: face width should be at least 25% of frame
    // Use face oval edges (landmarks 234 and 454)
    if (landmarks.length > 454) {
      final faceWidth = (landmarks[454].x - landmarks[234].x).abs();
      final largEnough = faceWidth > 0.25;

      if (highConfidence && stable && largEnough) {
        return Colors.greenAccent;
      }
    }

    return Colors.redAccent;
  }

  void _startCapture() {
    if (_meshResult == null) return;
    setState(() {
      _isCapturing = true;
      _capturedFrames.clear();
    });
  }

  void _finishCapture() {
    _isCapturing = false;
    if (_capturedFrames.isEmpty) return;

    final averaged = averageLandmarks(_capturedFrames);
    final report = analyzeface(landmarks: averaged, ethnicity: _ethnicity);
    _capturedFrames.clear();

    if (mounted) {
      setState(() => _isCapturing = false);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReportPage(report: report)),
      );
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;

    await _cameraController?.stopImageStream();
    _meshResult = null;

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera();
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
      floatingActionButton: !_isInitialized
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_cameras.length > 1)
                  FloatingActionButton.small(
                    heroTag: 'switch',
                    onPressed: _switchCamera,
                    child: const Icon(Icons.cameraswitch),
                  ),
                if (_cameras.length > 1) const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'analyze',
                  onPressed: _isCapturing || _meshResult == null ? null : _startCapture,
                  backgroundColor: _isCapturing ? Colors.orange : Colors.teal,
                  icon: _isCapturing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.analytics),
                  label: Text(_isCapturing
                      ? '분석 중... (${_capturedFrames.length}/5)'
                      : '분석'),
                ),
              ],
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

    if (!_isInitialized || _cameraController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final controller = _cameraController!;
    final isFront = _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview + mesh overlay in same coordinate space
        // previewSize is in sensor orientation (landscape), swap for portrait
        Builder(builder: (context) {
          final previewSize = controller.value.previewSize;
          if (previewSize == null) return const SizedBox();
          // Sensor reports landscape (e.g. 1920x1080), swap for portrait display
          final previewW = previewSize.height;
          final previewH = previewSize.width;

          return SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewW,
                height: previewH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(controller),
                    if (_meshResult != null)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: FaceMeshPainter(
                            result: _meshResult!,
                            isFrontCamera: isFront,
                            overlayColor: _overlayColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
        // Top bar: landmark count + ethnicity selector
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Row(
            children: [
              if (_meshResult != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_meshResult!.landmarks.length} landmarks',
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<Ethnicity>(
                  value: _ethnicity,
                  dropdownColor: const Color(0xFF1A1A2E),
                  style: const TextStyle(color: Colors.tealAccent, fontSize: 12),
                  underline: const SizedBox(),
                  isDense: true,
                  items: Ethnicity.values.map((e) {
                    return DropdownMenuItem(value: e, child: Text(e.labelKo));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _ethnicity = v);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
