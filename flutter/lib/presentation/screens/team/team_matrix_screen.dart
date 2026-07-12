import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:facely/config/router.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
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

  /// 표시 이름 SoT = 방 명단(roster) — 웹 쇼케이스 payload(_buildPayload)와
  /// 동일 규칙. report.alias 는 원격 합류자에서 항상 null(공유수신 차단)이라
  /// 이름 소스로 쓰면 인구통계 fallback 으로 새는 참사가 난다 (2026-07-12).
  late final Map<String, String> _nameById;

  @override
  void initState() {
    super.initState();
    final room = ref.read(teamsProvider.notifier).byId(widget.roomId)!;
    _title = room.title;
    // 방장 슬롯 '나' 는 결과표에선 프로필 nickname 으로 (웹과 동일 표기).
    final myNickname = ref.read(authProvider)?.nickname;
    _nameById = {
      for (final m in room.members)
        if (m.reportId != null)
          m.reportId!: m.name == '나' ? (myNickname ?? m.name) : m.name,
    };
    final members = ref.read(teamsProvider.notifier).scannedReports(room);
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
      // 내 관상 재등록으로 roster 의 방장 reportId 와 live id 가 어긋난
      // 경우 보충 — 결과표의 나는 항상 프로필명으로.
      final vid = v.supabaseId;
      if (vid != null && !_nameById.containsKey(vid)) {
        _nameById[vid] = myNickname ?? '나';
      }
    }
  }

  String _nameOf(FaceReadingReport r) {
    final id = r.supabaseId;
    final roster = id == null ? null : _nameById[id];
    return roster ?? r.alias ?? '${r.ageGroup.labelKo} ${r.gender.labelKo}';
  }

  @override
  Widget build(BuildContext context) {
    final bests = _matrix.bests;
    final surprises = _matrix.surprises;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 🏆 베스트 — 1위 점수 그룹(동점자 모두) + 한 줄 무료 (A2 도파민 모먼트).
              _SummaryCard(
                eyebrow: '🥳 베스트 케미',
                headline: _pairHeadlines(bests),
                caption: '얼굴 관상으로 분석한 두사람의 호흡이 '
                    '현재 조직내에서 최고 수준입니다.',
              ),
              if (surprises.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                // 😲 버금가는 케미 — 2위 점수 그룹(동점자 모두).
                _SummaryCard(
                  eyebrow: '😲 버금가는 케미',
                  headline: _pairHeadlines(surprises),
                  caption: '얼굴 관상으로 분석한 두사람의 호흡이 '
                      '현재 조직내에서 두번째 최고 수준입니다.',
                ),
              ],
              // 나와의 교감도 순위 — 잘 맞는 사람부터 어려운 사람 순.
              // 보는 사람(내 관상)이 멤버일 때만. 무료 노출은 밴드 이모지만
              // (점수·풀이는 페어 unlock 정책 그대로, A2).
              if (_viewer != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '나와의 궁합도 순위',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildViewerRanking(),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text(
                '상호 궁합도 맵',
                style: AppText.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildGrid(),
              const SizedBox(height: AppSpacing.lg),
              // 밴드 범례 — 매트릭스와 동일한 색깔 닷 + 라벨.
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final label in CompatLabel.values)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: label.bandColor,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          label.bandLabel,
                          style: AppText.caption
                              .copyWith(color: AppColors.textHint),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 나와의 교감도 순위 — viewer 와 나머지 멤버의 페어를 총점 내림차순으로.
  /// 행 = 순위 + 이름 + 밴드 이모지(무료), 탭 = 페어 시트(unlock 흐름).
  Widget _buildViewerRanking() {
    final v = _viewer!;
    final ranked = <TeamPair>[];
    for (final m in _matrix.members) {
      if (m.supabaseId == v.supabaseId) continue;
      final pair = _matrix.pairOf(v, m);
      if (pair != null) ranked.add(pair);
    }
    ranked.sort((a, b) => b.total.compareTo(a.total));

    FaceReadingReport otherOf(TeamPair p) =>
        p.a.supabaseId == v.supabaseId ? p.b : p.a;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          for (int i = 0; i < ranked.length; i++)
            InkWell(
              onTap: () => _showPairSheet(ranked[i]),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    _rankAvatar(otherOf(ranked[i])),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _nameOf(otherOf(ranked[i])),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // 점수 → 이모지 → 라벨 순. xx점 (이모지) 형극난조.
                    Text(
                      '${ranked[i].total.round()}점',
                      style: AppText.body.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(ranked[i].label.bandEmoji, style: AppText.body),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      ranked[i].label.bandLabel,
                      style: AppText.body.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 원형 thumbnail 아바타 — 사람 구분용. 1순위 로컬 파일 → 2순위
  /// CDN(thumbnailKey) → 사람 아이콘 (앱 공통 3단 — rehydrate 복원·원격
  /// 합류 멤버는 thumbnailPath=null 이라 CDN 이 실제 얼굴을 띄운다).
  Widget _rankAvatar(FaceReadingReport r, {double size = 28}) {
    final file = ThumbnailPaths.resolveFileSync(r.thumbnailPath);
    if (file != null && file.existsSync()) {
      return ClipOval(
        child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
      );
    }
    final cdn = ThumbnailPaths.cdnUrl(r.thumbnailKey);
    if (cdn != null) {
      return ClipOval(
        child: Image.network(
          cdn,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _iconAvatar(size),
        ),
      );
    }
    return _iconAvatar(size);
  }

  Widget _iconAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.border,
      ),
      child: Center(
        child: FaIcon(FontAwesomeIcons.user,
            size: size * 0.45, color: AppColors.textHint),
      ),
    );
  }

  /// 요약 카드 헤드라인 — 닷 + 밴드 라벨 + 아바타·이름 페어.
  /// 동점 페어 그룹을 세로로 쌓는다 — 같은 점수면 모두 한 카드에.
  Widget _pairHeadlines(List<TeamPair> pairs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < pairs.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _pairHeadline(pairs[i].a, pairs[i].b, pairs[i].label, pairs[i].total),
        ],
      ],
    );
  }

  Widget _pairHeadline(
      FaceReadingReport a, FaceReadingReport b, CompatLabel label, double total) {
    return Row(
      children: [
        // 점수 → 이모지 → 라벨 순. xx점 (이모지) 마합가성.
        Text(
          '${total.round()}점',
          style: AppText.body.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label.bandEmoji, style: AppText.body),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label.bandLabel,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: _personInline(a)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text('×', style: AppText.body),
        ),
        Flexible(child: _personInline(b)),
      ],
    );
  }

  /// 아바타 + 이름 (한 줄, 이름 굵게).
  Widget _personInline(FaceReadingReport r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rankAvatar(r, size: 24),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            _nameOf(r),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  /// 페어 시트용 세로 인물 — 큰 아바타 + 이름 + 나이·성별.
  Widget _personColumn(FaceReadingReport r) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rankAvatar(r, size: 64),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _nameOf(r),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.body.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${r.ageGroup.labelKo} ${r.gender.labelKo}',
          style: AppText.caption.copyWith(color: AppColors.textHint),
        ),
      ],
    );
  }

  Widget _buildGrid() {
    const nameWidth = 72.0;
    const cellSize = 44.0;
    final n = _ordered.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 행 — 열 아바타.
          Row(
            children: [
              const SizedBox(width: nameWidth, height: cellSize),
              for (int j = 0; j < n; j++)
                SizedBox(
                  width: cellSize,
                  height: cellSize,
                  child: Center(child: _rankAvatar(_ordered[j])),
                ),
            ],
          ),
          for (int i = 0; i < n; i++)
            Row(
              children: [
                // 행 헤더 — 아바타 + 이름.
                SizedBox(
                  width: nameWidth,
                  height: cellSize,
                  child: Row(
                    children: [
                      _rankAvatar(_ordered[i]),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _nameOf(_ordered[i]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
        // 무료 셀 = 밴드 색깔 닷만. 점수·라벨 비노출 (A2).
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pair.label.bandColor,
            ),
          ),
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
      builder: (ctx) {
        final coins = ref.read(authProvider)?.coins ?? 0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.md,
            AppSpacing.xxl,
            AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 닫기.
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(ctx, false),
                  icon: const FaIcon(FontAwesomeIcons.xmark,
                      size: 20, color: AppColors.textSecondary),
                ),
              ),
              // 밴드 닷 + 라벨 + 점수.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: pair.label.bandColor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${pair.label.bandLabel} (${pair.total.round()}점)',
                    style: AppText.body,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              // 두 인물 — 큰 아바타 + 이름 + 나이·성별.
              Row(
                children: [
                  Expanded(child: _personColumn(pair.a)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm),
                    child: Text('×',
                        style: AppText.body.copyWith(
                          color: AppColors.textHint,
                          fontSize: AppText.body.fontSize! * 2,
                        )),
                  ),
                  Expanded(child: _personColumn(pair.b)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              // 잠금 안내 박스.
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.lock,
                        size: 13, color: AppColors.textHint),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '상세 풀이는 1코인 지불 후 확인가능합니다.',
                        style: AppText.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: '1코인으로 풀이 보기',
                onPressed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '보유 코인 $coins개',
                style: AppText.caption.copyWith(color: AppColors.textHint),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
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
  final Widget headline;
  final String caption;

  const _SummaryCard({
    required this.eyebrow,
    required this.headline,
    required this.caption,
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
          headline,
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
