import 'dart:io';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/compatibility_engine.dart';
import 'package:face_reader/presentation/providers/compat_albums_provider.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/screens/compatibility/compatibility_report_page.dart';
import 'package:face_reader/presentation/widgets/compact_snack_bar.dart';
import 'package:face_reader/presentation/widgets/compatibility_info_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

class CompatibilityScreen extends ConsumerWidget {
  const CompatibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

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
      body: _buildBody(context, ref, myFace, albumReports),
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
  ) {
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
                style: TextStyle(
                    color: AppTheme.textHint, fontSize: 15, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

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
                style: TextStyle(
                    color: AppTheme.textHint, fontSize: 15, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final me = myFace.first;
    final history = ref.watch(historyProvider);
    final compatAlbums = ref.watch(compatAlbumsProvider);

    // Only album reports that the user has explicitly opted into compat for.
    final albumItems = <FaceReadingReport>[];
    for (final r in history) {
      if (r.source != AnalysisSource.album) continue;
      final uuid = r.supabaseId ?? '';
      if (uuid.isEmpty || !compatAlbums.contains(uuid)) continue;
      albumItems.add(r);
    }

    if (albumItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border, color: AppTheme.border, size: 64),
              const SizedBox(height: 16),
              Text(
                '관상 > 앨범 탭에서 인물을 길게 눌러 "궁합 보기"를 선택하면 이곳에 나타납니다.',
                style: TextStyle(
                    color: AppTheme.textHint, fontSize: 15, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: albumItems.length,
      itemBuilder: (context, index) {
        final album = albumItems[index];
        return _CompatibilityItem(
          myReport: me,
          albumReport: album,
        );
      },
    );
  }
}

class _CompatibilityItem extends ConsumerWidget {
  final FaceReadingReport myReport;
  final FaceReadingReport albumReport;

  const _CompatibilityItem({
    required this.myReport,
    required this.albumReport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumName = albumReport.alias ??
        '${albumReport.ageGroup.labelKo} ${albumReport.gender.labelKo} · ${albumReport.archetype.primaryLabel}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(albumReport.timestamp.toIso8601String()),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            CustomSlidableAction(
              onPressed: (_) => _delete(context, ref),
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              borderRadius: BorderRadius.circular(14),
              padding: EdgeInsets.zero,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete),
                  SizedBox(height: 4),
                  Text('삭제', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        child: Material(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _viewCompatibility(context),
            onLongPress: () => _showBottomMenu(context, ref),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
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
                        color: Colors.red.shade300, size: 18),
                  ),
                  _buildAlbumAvatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(albumName,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.chevron_right, color: AppTheme.textHint),
                ],
              ),
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

  void _viewCompatibility(BuildContext context) {
    final result = evaluateCompatibility(myReport, albumReport);
    // Album UUID — always set for new reports (UUID-first architecture).
    // Fallback to timestamp digits for legacy Hive entries without supabaseId.
    final albumUuid = albumReport.supabaseId ??
        albumReport.timestamp.millisecondsSinceEpoch.toString();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompatibilityReportPage(
          result: result,
          albumName: albumReport.alias ??
              '${albumReport.ageGroup.labelKo} ${albumReport.gender.labelKo} · ${albumReport.archetype.primaryLabel}',
          albumUuid: albumUuid,
          thumbnailPath: albumReport.thumbnailPath,
        ),
      ),
    );
  }

  void _delete(BuildContext context, WidgetRef ref) {
    // Remove the album uuid from the compat opt-in set.
    // Album physiognomy itself stays intact in 관상 tab.
    final albumUuid = albumReport.supabaseId;
    if (albumUuid == null) return;
    ref.read(compatAlbumsProvider.notifier).remove(albumUuid);
    showTopSnackBar(
      Overlay.of(context),
      CompactSnackBar.success(message: '궁합 항목이 삭제되었습니다'),
    );
  }

  void _showBottomMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.delete, color: Colors.red.shade600),
              title: const Text('삭제'),
              onTap: () {
                Navigator.pop(ctx);
                _delete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }
}
