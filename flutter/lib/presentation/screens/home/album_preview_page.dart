import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_reader/domain/models/face_analysis.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/presentation/providers/age_group_provider.dart';
import 'package:face_reader/presentation/providers/ethnicity_provider.dart';
import 'package:face_reader/presentation/providers/gender_provider.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/providers/tab_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
              '얼굴 랜드마크 감지',
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
              // Instruction banner
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.black.withValues(alpha: 0.6),
                  child: const Text(
                    '정면을 바라보는 사진을 사용해야만 왜곡을 줄일 수 있습니다.',
                    style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                    textAlign: TextAlign.left,
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
                    width: 200,
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
                      icon: const Icon(Icons.smart_toy, size: 20),
                      label: const Text(
                        '관상학 데이터 분석',
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

  Future<void> _analyze(BuildContext context, WidgetRef ref) async {
    final ethnicity = ref.read(ethnicityProvider);
    final gender = ref.read(genderProvider);
    final ageGroup = ref.read(ageGroupProvider);

    final report = analyzeFaceReading(
      landmarks: meshResult.landmarks,
      ethnicity: ethnicity,
      gender: gender,
      ageGroup: ageGroup,
      source: AnalysisSource.album,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );

    // Generate UUID upfront — same id used for thumbnail filename and Supabase
    final id = const Uuid().v4();
    report.supabaseId = id;

    // Compress to 128px WebP thumbnail and save
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        imageBytes,
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

    ref.read(historyProvider.notifier).add(report);
    ref.read(historyTabProvider.notifier).selectTab(1);
    ref.read(selectedTabProvider.notifier).selectTab(1);
    if (context.mounted) Navigator.of(context).pop();
    // Save to Supabase in background using the pre-assigned UUID
    SupabaseService().saveMetrics(report).catchError((e) {
      debugPrint('[Supabase] save error: $e');
      return '';
    });
  }
}
