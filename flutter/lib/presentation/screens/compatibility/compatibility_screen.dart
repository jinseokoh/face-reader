import 'dart:io';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/presentation/providers/compatibility_provider.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/widgets/compatibility_info_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CompatibilityScreen extends ConsumerWidget {
  const CompatibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final compatMap = ref.watch(compatibilityProvider);

    final myFace = history
        .where((r) => r.source == AnalysisSource.camera && r.isMyFace)
        .toList();
    final albumReports =
        history.where((r) => r.source == AnalysisSource.album).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('궁합'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: _buildBody(context, ref, myFace, albumReports, compatMap),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'info',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, anim, secondAnim) {
        final maxH = MediaQuery.of(ctx).size.height * 0.8;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: CompatibilityInfoDialog(maxHeight: maxH),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<FaceReadingReport> myFace,
    List<FaceReadingReport> albumReports,
    Map<String, dynamic> compatMap,
  ) {
    // Case 1: 내 얼굴 미선택
    if (myFace.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.face, color: AppTheme.border, size: 64),
              const SizedBox(height: 16),
              Text(
                '관상 탭에서 내 얼굴을 먼저 선택해야만 궁합을 볼 수 있습니다.',
                style: TextStyle(color: AppTheme.textHint, fontSize: 15, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Case 2: 앨범 평가 없음
    if (albumReports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library, color: AppTheme.border, size: 64),
              const SizedBox(height: 16),
              Text(
                '앨범 열기로 사진의 관상 평가를 한 사람이 있는 경우에만, 그 사람과 나와의 궁합 평가를 볼 수 있습니다.',
                style: TextStyle(color: AppTheme.textHint, fontSize: 15, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Case 3: 리스트 표시
    final me = myFace.first;
    final myTs = me.timestamp.toIso8601String();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: albumReports.length,
      itemBuilder: (context, index) {
        final album = albumReports[index];
        final albumTs = album.timestamp.toIso8601String();
        final key = '${myTs}_$albumTs';
        final result = compatMap[key];
        final evaluated = result != null;

        return _CompatibilityItem(
          myReport: me,
          albumReport: album,
          evaluated: evaluated,
        );
      },
    );
  }
}

class _CompatibilityItem extends ConsumerWidget {
  final FaceReadingReport myReport;
  final FaceReadingReport albumReport;
  final bool evaluated;

  const _CompatibilityItem({
    required this.myReport,
    required this.albumReport,
    required this.evaluated,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumName = albumReport.alias ?? '앨범 인물';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _onTap(context, ref),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 내 얼굴 아이콘
                Icon(
                  myReport.gender == Gender.female
                      ? Icons.face_3
                      : Icons.face_6,
                  color: AppTheme.textSecondary,
                  size: 32,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.favorite,
                      color: evaluated ? Colors.red.shade400 : AppTheme.border,
                      size: 18),
                ),
                // 앨범 인물 썸네일
                _buildAlbumAvatar(),
                const SizedBox(width: 12),
                // 이름 + 태그
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(albumName,
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: evaluated
                              ? Colors.green.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          evaluated ? '평가 완료' : '미평가',
                          style: TextStyle(
                            color: evaluated
                                ? Colors.green.shade700
                                : AppTheme.textHint,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppTheme.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumAvatar() {
    if (albumReport.thumbnailPath != null) {
      final file = File(albumReport.thumbnailPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, width: 32, height: 32, fit: BoxFit.cover),
        );
      }
    }
    return Icon(Icons.photo_library, color: AppTheme.textSecondary, size: 32);
  }

  void _evaluateCompatibility(BuildContext context, WidgetRef ref) {
    // TODO: 궁합 평가 알고리즘 구현
  }

  void _onTap(BuildContext context, WidgetRef ref) {
    if (evaluated) {
      // TODO: 궁합 평가 결과 페이지로 이동
    } else {
      _showConfirmSheet(context, ref);
    }
  }

  void _showConfirmSheet(BuildContext context, WidgetRef ref) {
    final albumName = albumReport.alias ?? '앨범 인물';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$albumName과(와)의 궁합을 보겠습니까?',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textHint,
                        side: BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _evaluateCompatibility(context, ref);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.textPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('궁합 보기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
