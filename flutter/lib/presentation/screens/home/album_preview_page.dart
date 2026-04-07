import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:face_reader/domain/models/face_analysis.dart';
import 'package:face_reader/presentation/providers/age_group_provider.dart';
import 'package:face_reader/presentation/providers/ethnicity_provider.dart';
import 'package:face_reader/presentation/providers/gender_provider.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/providers/tab_provider.dart';
import 'face_mesh_painter.dart';

class AlbumPreviewPage extends ConsumerWidget {
  final Uint8List imageBytes;
  final FaceMeshResult meshResult;
  final int imageWidth;
  final int imageHeight;

  const AlbumPreviewPage({
    super.key,
    required this.imageBytes,
    required this.meshResult,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              '앨범 사진',
              style: TextStyle(
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
              // Image + mesh overlay
              Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: imageWidth.toDouble(),
                    height: imageHeight.toDouble(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          imageBytes,
                          fit: BoxFit.fill,
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: FaceMeshPainter(
                              result: meshResult,
                              isFrontCamera: false,
                              overlayColor: Colors.greenAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Analyze button
              Positioned(
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).padding.bottom + 24,
                child: Center(
                  child: SizedBox(
                    width: 140,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () => _analyze(context, ref),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.85),
                        foregroundColor: const Color(0xFF333333),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.analytics, size: 20),
                      label: const Text(
                        '분석',
                        style: TextStyle(
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

  void _analyze(BuildContext context, WidgetRef ref) {
    final ethnicity = ref.read(ethnicityProvider);
    final gender = ref.read(genderProvider);
    final ageGroup = ref.read(ageGroupProvider);

    final report = analyzeFaceReading(
      landmarks: meshResult.landmarks,
      ethnicity: ethnicity,
      gender: gender,
      ageGroup: ageGroup,
    );

    ref.read(historyProvider.notifier).add(report);
    ref.read(selectedTabProvider.notifier).selectTab(1);
    Navigator.of(context).pop();
  }
}
