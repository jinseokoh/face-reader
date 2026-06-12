import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_engine/data/constants/compat_hashtags.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:facely/config/router.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/domain/services/team_matrix.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/screens/compatibility/compat_unlock_action.dart';

import 'team_band.dart';

/// 교감도 — N×N 밴드 매트릭스. PIVOT A4:
/// 🏆/😲 요약 카드 → 밴드 이모지 그리드(보는 사람 행 최상단) → 밴드 범례.
/// 무료 셀 = 밴드 이모지만 (점수 비노출, A2). 페어 탭 → 1🪙 unlock → 상세.
class TeamMatrixScreen extends ConsumerStatefulWidget {
  final String roomId;

  const TeamMatrixScreen({super.key, required this.roomId});

  @override
  ConsumerState<TeamMatrixScreen> createState() => _TeamMatrixScreenState();
}

class _TeamMatrixScreenState extends ConsumerState<TeamMatrixScreen> {
  late final String _title;
  late final TeamMatrix _matrix;
  late final List<FaceReadingReport> _ordered; // 보는 사람(나) 행 최상단.
  FaceReadingReport? _viewer;
  // 🏆 베스트 페어 무료 공개분 — 한 줄 풀이 + 해시태그 (A2).
  late final String _bestOneLiner;
  late final String _bestHashtag;

  @override
  void initState() {
    super.initState();
    final room = ref.read(teamsProvider.notifier).byId(widget.roomId)!;
    _title = room.title;
    final members = ref.read(teamsProvider.notifier).resolveMembers(room);
    // 엔진이 결정론적·대칭이라 매번 재계산 (capture-only 원칙).
    _matrix = computeTeamMatrix(members);

    // 보는 사람 = 멤버 중 내 관상. 없으면(남의 폰) 첫 멤버 순서 그대로.
    final history = ref.read(historyProvider);
    for (final r in history) {
      if (r.isMyFace &&
          _matrix.members.any((m) => m.supabaseId == r.supabaseId)) {
        _viewer = r;
        break;
      }
    }
    _ordered = [..._matrix.members];
    final v = _viewer;
    if (v != null) {
      _ordered.removeWhere((m) => m.supabaseId == v.supabaseId);
      _ordered.insert(
        0,
        _matrix.members
            .firstWhere((m) => m.supabaseId == v.supabaseId),
      );
    }

    // 베스트 페어의 무료 공개분 — narrative summary 첫 문장 + warm 해시태그 1개.
    final bundle = analyzeCompatibilityFromReports(
      my: _matrix.best.a,
      album: _matrix.best.b,
    );
    _bestOneLiner = _firstSentence(bundle.narrative.summary);
    final chips = chipsForCompat(bundle.report);
    _bestHashtag = chips.isNotEmpty ? chips.first.label : '#케미';
  }

  static String _firstSentence(String text) {
    final idx = text.indexOf('.');
    if (idx < 0) return text.trim();
    return text.substring(0, idx + 1).trim();
  }

  String _nameOf(FaceReadingReport r) {
    if (_viewer != null && r.supabaseId == _viewer!.supabaseId) return '나';
    return r.alias ?? '${r.ageGroup.labelKo} ${r.gender.labelKo}';
  }

  @override
  Widget build(BuildContext context) {
    final best = _matrix.best;
    final surprise = _matrix.surprise;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 🏆 베스트 페어 — 점수 + 한 줄 무료 (A2 도파민 모먼트).
              _SummaryCard(
                eyebrow: '🏆 베스트 케미',
                title:
                    '${_nameOf(best.a)} ×× ${_nameOf(best.b)}  ${best.total.round()}',
                caption: _bestOneLiner,
                hashtag: _bestHashtag,
              ),
              if (surprise != null) ...[
                const SizedBox(height: AppSpacing.md),
                // 😲 의외의 조합 — 2위 페어. 점수는 잠금 (밴드만).
                _SummaryCard(
                  eyebrow: '😲 의외의 조합',
                  title:
                      '${_nameOf(surprise.a)} ×× ${_nameOf(surprise.b)}  ${surprise.label.bandEmoji}',
                  caption: '풀이를 열면 정확한 점수를 볼 수 있어요',
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              _buildGrid(),
              const SizedBox(height: AppSpacing.lg),
              // 밴드 범례.
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final label in CompatLabel.values)
                    Text(
                      '${label.bandEmoji} ${label.bandLabel}',
                      style:
                          AppText.caption.copyWith(color: AppColors.textHint),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    const nameWidth = 72.0;
    const cellSize = 44.0;
    final n = _ordered.length;

    Widget nameCell(String text, {bool bold = false}) => SizedBox(
          width: nameWidth,
          height: cellSize,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 행 — 열 이름.
          Row(
            children: [
              nameCell(''),
              for (int j = 0; j < n; j++)
                SizedBox(
                  width: cellSize,
                  height: cellSize,
                  child: Center(
                    child: Text(
                      _nameOf(_ordered[j]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.hint,
                    ),
                  ),
                ),
            ],
          ),
          for (int i = 0; i < n; i++)
            Row(
              children: [
                nameCell(_nameOf(_ordered[i]), bold: i == 0 && _viewer != null),
                for (int j = 0; j < n; j++) _cell(i, j),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int i, int j) {
    const cellSize = 44.0;
    if (i == j) {
      return SizedBox(
        width: cellSize,
        height: cellSize,
        child: Center(
          child: Text('·',
              style: AppText.caption.copyWith(color: AppColors.textHint)),
        ),
      );
    }
    final pair = _matrix.pairOf(_ordered[i], _ordered[j]);
    if (pair == null) {
      return const SizedBox(width: cellSize, height: cellSize);
    }
    return InkWell(
      onTap: () => _showPairSheet(pair),
      child: Container(
        width: cellSize,
        height: cellSize,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.surface, width: 0.5),
        ),
        // 무료 셀 = 밴드 이모지만. 점수·라벨 비노출 (A2).
        child: Center(
          child: Text(pair.label.bandEmoji,
              style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
  }

  Future<void> _showPairSheet(TeamPair pair) async {
    final unlock = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_nameOf(pair.a)} ×× ${_nameOf(pair.b)}',
              style: AppText.modalTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${pair.label.bandEmoji} ${pair.label.bandLabel}',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '정확한 점수와 상세 풀이는 코인으로 열 수 있어요',
              style: AppText.caption.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text(
                '1코인으로 풀이 보기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
    if (unlock != true || !mounted) return;
    // 기존 1:1 unlock 흐름 그대로 — 로그인·잔액·중복 unlock 전부 처리.
    final ok = await runCompatUnlock(
      context,
      ref,
      my: pair.a,
      album: pair.b,
      confirm: false,
    );
    if (!ok || !mounted) return;
    context.pushCompat(my: pair.a, album: pair.b);
  }
}

/// 🏆/😲 요약 카드 — §3.2 카드 토큰.
class _SummaryCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String caption;
  final String? hashtag;

  const _SummaryCard({
    required this.eyebrow,
    required this.title,
    required this.caption,
    this.hashtag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: AppText.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subTitle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hashtag != null)
                Text(
                  hashtag!,
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}
