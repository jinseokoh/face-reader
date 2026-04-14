import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'face_mesh_painter.dart';

class AlbumPreviewPage extends ConsumerWidget {
  final Uint8List imageBytes;
  final FaceMeshResult meshResult;
  final int imageWidth;
  final int imageHeight;
  final AlbumPreviewPhase phase;
  final VoidCallback onConfirm;

  const AlbumPreviewPage({
    super.key,
    required this.imageBytes,
    required this.meshResult,
    required this.imageWidth,
    required this.imageHeight,
    required this.phase,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFrontal = phase == AlbumPreviewPhase.frontal;
    final title = isFrontal ? '정면 사진' : '측면(3/4)사진';
    final description = isFrontal
        ? '지금은 정면의 윤곽을 파악하는 과정입니다.'
        : '지금은 측면의 윤곽을 파악하는 과정입니다.';
    final buttonLabel = isFrontal ? '정면 분석' : '측면 분석';

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
              title,
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
          body: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: imageWidth.toDouble(),
                    height: imageHeight.toDouble(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(imageBytes, fit: BoxFit.fill),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: FaceMeshPainter(
                              result: meshResult,
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
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
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.85),
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
          ),
        ),
      ),
    );
  }
}

enum AlbumPreviewPhase { frontal, lateral }
