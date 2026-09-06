import 'package:face_engine/data/constants/impression_evidence.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/geometry_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../domain/services/pair_score.dart';
import '../../providers/history_provider.dart';
import '../../widgets/detail_avatar.dart';
import '../../widgets/source_badge.dart';

/// 같은 사람의 사진 여러 장 비교 (APPLE.md §56) — measure 에디션 전용.
///
/// 카드 목록에서 2~4장을 고르면 사진마다 첫인상 4축과 얼굴 대칭이 나란히
/// 놓인다. "사진에 따라 내가 전달하는 첫인상이 어떻게 달라지는지" 를 보는
/// 화면이라 어느 카드가 같은 사람인지는 사용자가 고른다.
class PhotoCompareScreen extends ConsumerWidget {
  const PhotoCompareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PhotoCompareBody(reports: ref.watch(historyProvider));
  }
}

class PhotoCompareBody extends StatefulWidget {
  final List<FaceReadingReport> reports;
  const PhotoCompareBody({super.key, required this.reports});

  static const int maxPick = 4;

  @override
  State<PhotoCompareBody> createState() => _PhotoCompareBodyState();
}

class _PhotoCompareBodyState extends State<PhotoCompareBody> {
  /// 고른 순서대로 — 표의 열 순서.
  final List<FaceReadingReport> _picked = [];

  void _toggle(FaceReadingReport r) {
    setState(() {
      if (_picked.contains(r)) {
        _picked.remove(r);
      } else if (_picked.length < PhotoCompareBody.maxPick) {
        _picked.add(r);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('사진별 첫인상'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl + bottom),
        children: [
          Text(
            '같은 사람의 사진을 2~${PhotoCompareBody.maxPick}장 고르면 사진에 따라 '
            '첫인상이 어떻게 달라지는지 나란히 봅니다. 어느 카드가 같은 사람인지는 '
            '직접 고릅니다.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (widget.reports.isEmpty)
            Text('비교할 카드가 없습니다.', style: AppText.body)
          else
            for (final r in widget.reports) _PickRow(
              report: r,
              order: _picked.indexOf(r),
              onTap: () => _toggle(r),
            ),
          if (_picked.length >= 2) ...[
            const SizedBox(height: AppSpacing.xl),
            Text('사진별 첫인상', style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.md),
            _CompareTable(reports: _picked),
          ],
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  final FaceReadingReport report;

  /// 고른 순서(0부터). −1 = 안 고름.
  final int order;
  final VoidCallback onTap;

  const _PickRow({
    required this.report,
    required this.order,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = report.timestamp;
    final picked = order >= 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: picked ? AppColors.cream : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
              color: picked ? AppColors.textPrimary : AppColors.shell),
        ),
        child: Row(
          children: [
            DetailAvatar(
              thumbnailKey: report.thumbnailKey,
              borderColor: sourceBorderColor(report.source),
              fallback: Center(
                child: SvgPicture.asset(
                  report.gender == Gender.male
                      ? 'assets/svgs/male.svg'
                      : 'assets/svgs/female.svg',
                  height: DetailAvatar.size * 0.5,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.isMyFace ? '나' : (report.alias ?? '이름 없음'),
                    style: AppText.subTitle,
                  ),
                  Text('${t.year}.${t.month}.${t.day}', style: AppText.caption),
                ],
              ),
            ),
            if (picked) Text(_photoLabel(order), style: AppText.subTitle),
          ],
        ),
      ),
    );
  }
}

String _photoLabel(int i) => '사진 ${String.fromCharCode(65 + i)}';

/// 행 = 첫인상 4축 + 얼굴 대칭, 열 = 고른 사진. 값은 상위 N%.
class _CompareTable extends StatelessWidget {
  final List<FaceReadingReport> reports;
  const _CompareTable({required this.reports});

  @override
  Widget build(BuildContext context) {
    final profiles = [for (final r in reports) impressionOf(r)];
    final symmetry = [
      for (final r in reports)
        computeGeometryProfile(
          zByMetric: zMapOf(r),
          gender: r.gender,
          symmetry: r.symmetry,
        )['symmetry'],
    ];
    Widget cell(String text, {TextStyle style = AppText.caption}) => SizedBox(
          width: 64,
          child: Text(text, style: style, textAlign: TextAlign.right),
        );
    Widget row(String label, List<double?> values) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppText.body)),
              for (final v in values)
                cell(v == null ? '—' : _top(v), style: AppText.body),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.shell),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: SizedBox()),
              for (var i = 0; i < reports.length; i++) cell(_photoLabel(i)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final axis in ImpressionAxis.values)
            row(axis.labelKo, [for (final p in profiles) p[axis]]),
          const Divider(height: AppSpacing.xl),
          row('얼굴 대칭', symmetry),
        ],
      ),
    );
  }
}

String _top(double percentile) =>
    '상위 ${(100 - percentile).round().clamp(1, 99)}%';
