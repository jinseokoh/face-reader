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
    // Compat candidates: any non-myFace report (camera selfie or album photo).
    // Album-only assumption removed.
    final compatCandidates =
        history.where((r) => !r.isMyFace).toList();

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
      body: _buildBody(context, ref, myFace, compatCandidates),
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
    List<FaceReadingReport> compatCandidates,
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

    // 페어링 후보가 history에 하나도 없으면 (내 얼굴만 있거나 history가 비어있음) 안내.
    if (compatCandidates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library, color: AppTheme.border, size: 64),
              const SizedBox(height: 16),
              Text(
                '카메라로 다른 사람의 얼굴을 분석하거나 앨범에서 사진을 분석한 뒤, '
                '관상 탭에서 그 항목을 길게 눌러 "궁합 보기"를 선택해야 궁합 평가를 볼 수 있습니다.',
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

    // Reports the user has explicitly opted into compat for.
    // Includes both album items AND non-myFace camera selfies.
    final compatItems = <FaceReadingReport>[];
    for (final r in history) {
      if (r.isMyFace) continue; // 자기 자신과는 페어링 불가
      final uuid = r.supabaseId ?? '';
      if (uuid.isEmpty || !compatAlbums.contains(uuid)) continue;
      compatItems.add(r);
    }

    if (compatItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border, color: AppTheme.border, size: 64),
              const SizedBox(height: 16),
              Text(
                '관상 탭에서 인물을 길게 눌러 "궁합 보기"를 선택하면 이곳에 나타납니다.',
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
      itemCount: compatItems.length,
      itemBuilder: (context, index) {
        final partner = compatItems[index];
        return _CompatibilityItem(
          myReport: me,
          partnerReport: partner,
        );
      },
    );
  }
}

class _CompatibilityItem extends ConsumerWidget {
  final FaceReadingReport myReport;
  final FaceReadingReport partnerReport;

  const _CompatibilityItem({
    required this.myReport,
    required this.partnerReport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerName = partnerReport.alias ??
        '${partnerReport.ageGroup.labelKo} ${partnerReport.gender.labelKo} · ${partnerReport.archetype.primaryLabel}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(partnerReport.timestamp.toIso8601String()),
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
                  _buildPartnerAvatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(partnerName,
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

  Widget _buildPartnerAvatar() {
    if (partnerReport.thumbnailPath != null) {
      final file = File(partnerReport.thumbnailPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, width: 32, height: 32, fit: BoxFit.cover),
        );
      }
    }
    // Fallback icon: gender face for camera selfies, photo_library for album.
    final fallbackIcon = partnerReport.source == AnalysisSource.camera
        ? (partnerReport.gender == Gender.female ? Icons.face_3 : Icons.face_6)
        : Icons.photo_library;
    return Icon(fallbackIcon, color: AppTheme.textSecondary, size: 32);
  }

  void _viewCompatibility(BuildContext context) {
    final result = evaluateCompatibility(myReport, partnerReport);
    // UUID — always set for new reports (UUID-first architecture).
    // Fallback to timestamp digits for legacy Hive entries without supabaseId.
    final partnerUuid = partnerReport.supabaseId ??
        partnerReport.timestamp.millisecondsSinceEpoch.toString();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompatibilityReportPage(
          result: result,
          albumName: partnerReport.alias ??
              '${partnerReport.ageGroup.labelKo} ${partnerReport.gender.labelKo} · ${partnerReport.archetype.primaryLabel}',
          albumUuid: partnerUuid,
          thumbnailPath: partnerReport.thumbnailPath,
        ),
      ),
    );
  }

  void _delete(BuildContext context, WidgetRef ref) {
    // Remove the partner uuid from the compat opt-in set.
    // The original physiognomy report itself stays intact in 관상 tab.
    final partnerUuid = partnerReport.supabaseId;
    if (partnerUuid == null) return;
    ref.read(compatAlbumsProvider.notifier).remove(partnerUuid);
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
