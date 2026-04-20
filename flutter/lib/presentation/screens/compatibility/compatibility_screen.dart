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
    final compatCandidates = history.where((r) => !r.isMyFace).toList();

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

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<FaceReadingReport> myFace,
    List<FaceReadingReport> compatCandidates,
  ) {
    final history = ref.watch(historyProvider);
    final cameraCount =
        history.where((r) => r.source == AnalysisSource.camera).length;
    final albumCount =
        history.where((r) => r.source == AnalysisSource.album).length;
    final hasMyFace = myFace.isNotEmpty;

    // Only compute compat items once myFace is set — otherwise list is moot.
    List<FaceReadingReport> compatItems = const [];
    if (hasMyFace) {
      final compatAlbums = ref.watch(compatAlbumsProvider);
      compatItems = [
        for (final r in history)
          if (!r.isMyFace &&
              (r.supabaseId?.isNotEmpty ?? false) &&
              compatAlbums.contains(r.supabaseId))
            r,
      ];
    }

    if (!hasMyFace || compatItems.isEmpty) {
      return _PrerequisiteStepper(
        cameraCount: cameraCount,
        albumCount: albumCount,
        hasMyFace: hasMyFace,
        hasCompatItems: compatItems.isNotEmpty,
      );
    }

    final me = myFace.first;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: compatItems.length,
      itemBuilder: (context, index) {
        final partner = compatItems[index];
        return _CompatibilityItem(myReport: me, partnerReport: partner);
      },
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
    final partnerName =
        partnerReport.alias ??
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
                    child: Icon(
                      Icons.favorite,
                      color: Colors.red.shade300,
                      size: 18,
                    ),
                  ),
                  _buildPartnerAvatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      partnerName,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

  void _viewCompatibility(BuildContext context) {
    final result = evaluateCompatibility(myReport, partnerReport);
    // UUID — always set for new reports (UUID-first architecture).
    // Fallback to timestamp digits for legacy Hive entries without supabaseId.
    final partnerUuid =
        partnerReport.supabaseId ??
        partnerReport.timestamp.millisecondsSinceEpoch.toString();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompatibilityReportPage(
          result: result,
          albumName:
              partnerReport.alias ??
              '${partnerReport.ageGroup.labelKo} ${partnerReport.gender.labelKo} · ${partnerReport.archetype.primaryLabel}',
          albumUuid: partnerUuid,
          thumbnailPath: partnerReport.thumbnailPath,
          myThumbnailPath: myReport.thumbnailPath,
        ),
      ),
    );
  }
}

class _PrerequisiteStepper extends StatelessWidget {
  final int cameraCount;
  final int albumCount;
  final bool hasMyFace;
  final bool hasCompatItems;

  const _PrerequisiteStepper({
    required this.cameraCount,
    required this.albumCount,
    required this.hasMyFace,
    required this.hasCompatItems,
  });

  @override
  Widget build(BuildContext context) {
    final step1Done = cameraCount >= 1;
    final step2Done = albumCount >= 1;
    final step3Done = hasMyFace;
    final step4Done = hasCompatItems;

    int currentStep = 1;
    if (step1Done) currentStep = 2;
    if (step1Done && step2Done) currentStep = 3;
    if (step1Done && step2Done && step3Done) currentStep = 4;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '궁합을 보려면',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '아래 네 단계를 순서대로 진행해 주세요.',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _StepRow(
            number: 1,
            title: '카메라로 관상 분석',
            hint: '홈 탭에서, 카메라 열기를 선택해 나의 관상을 분석해 봅니다.',
            doneLabel: '$cameraCount개 완료',
            done: step1Done,
            isCurrent: currentStep == 1,
            isLast: false,
          ),
          _StepRow(
            number: 2,
            title: '앨범 사진으로 관상 분석',
            hint: '홈 탭에서, 앨범 열기를 선택해 상대방의 관상을 분석해 봅니다.',
            doneLabel: '$albumCount개 완료',
            done: step2Done,
            isCurrent: currentStep == 2,
            isLast: false,
          ),
          _StepRow(
            number: 3,
            title: '내 관상 지정',
            hint: '관상 탭에서, 카메라 리스트 아이템을 길게 누르거나 스와이프하여 "내 관상"을 지정합니다.',
            doneLabel: '지정 완료',
            done: step3Done,
            isCurrent: currentStep == 3,
            isLast: false,
          ),
          _StepRow(
            number: 4,
            title: '궁합 보기 추가',
            hint: '관상 탭의 상대방 항목을 길게 누르거나 스와이프하여 "궁합 보기"를 선택합니다.',
            doneLabel: '목록에 추가됨',
            done: step4Done,
            isCurrent: currentStep == 4,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  static const _doneColor = Color(0xFF4CAF50);

  final int number;
  final String title;
  final String hint;
  final String doneLabel;
  final bool done;
  final bool isCurrent;
  final bool isLast;

  const _StepRow({
    required this.number,
    required this.title,
    required this.hint,
    required this.doneLabel,
    required this.done,
    required this.isCurrent,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final indicatorColor = done
        ? _doneColor
        : (isCurrent ? AppTheme.textPrimary : AppTheme.border);
    final titleColor = done || isCurrent
        ? AppTheme.textPrimary
        : AppTheme.textHint;
    final hintColor = isCurrent && !done
        ? AppTheme.textSecondary
        : AppTheme.textHint;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: done ? _doneColor : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: indicatorColor, width: 2),
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : Text(
                        '$number',
                        style: TextStyle(
                          color: indicatorColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done
                        ? _doneColor.withValues(alpha: 0.35)
                        : AppTheme.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isCurrent && !done
                      ? AppTheme.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                        ),
                        if (done)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _doneColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              doneLabel,
                              style: const TextStyle(
                                color: _doneColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 13,
                        color: hintColor,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
