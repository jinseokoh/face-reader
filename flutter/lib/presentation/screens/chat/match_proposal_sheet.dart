import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/team_service.dart';
import '../../../domain/models/team.dart';
import '../../providers/team_provider.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/source_badge.dart';

/// 매칭 제안 시트 — 채팅 탭 appbar 뱃지에서 진입. 미결 베스트 매칭마다
/// 카드 하나: 상대 사진 + 그룹명 + 응답 기한, [채팅방 열기]/[이번에는
/// 넘어가기] (reveal 의 TeamMatchCard 와 동일 라벨·동일 respond_match RPC).
Future<void> showMatchProposalSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _MatchProposalSheet(),
  );
}

class _MatchProposalSheet extends ConsumerWidget {
  const _MatchProposalSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposals =
        ref.watch(matchProposalsProvider).value ?? const <MatchProposal>[];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: proposals.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.huge),
                child: Center(
                  child: Text('응답할 매칭 제안이 없습니다', style: AppText.caption),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: proposals.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (_, i) => _ProposalCard(proposal: proposals[i]),
              ),
      ),
    );
  }
}

class _ProposalCard extends ConsumerStatefulWidget {
  final MatchProposal proposal;
  const _ProposalCard({required this.proposal});

  @override
  ConsumerState<_ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends ConsumerState<_ProposalCard> {
  bool _responding = false;

  MatchProposal get p => widget.proposal;

  Future<void> _respond(bool accept) async {
    setState(() => _responding = true);
    try {
      await TeamService.instance.respondMatch(p.match.teamId, accept);
      // 성사 시 채팅 목록에 entry 가 생기고, 어느 쪽이든 제안 목록이 바뀐다.
      ref.invalidate(matchProposalsProvider);
      ref.invalidate(openChatsProvider);
      ref.invalidate(openChatTeamsProvider);
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: mapTeamError(e).labelKo),
        );
        ref.invalidate(matchProposalsProvider);
      }
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = TeamService.instance.myUid;
    final myConsent = uid == null ? null : p.match.consentOf(uid);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        // 베스트 매칭 강조 — TeamMatchCard 와 같은 gold border 문법.
        border: Border.all(color: AppColors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '베스트 매칭',
            style: AppText.caption.copyWith(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _photo(),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.teamTitle, style: AppText.sectionTitle),
                    const SizedBox(height: AppSpacing.xs),
                    Text(p.otherNickname, style: AppText.caption),
                    if (p.decideBy != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _deadlineLabel(p.decideBy!),
                        style: AppText.caption.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (myConsent == null) ...[
            Text(
              '이 사람과 채팅방을 열까요? 두 사람 모두 열기를 선택하면 '
              '채팅방이 열립니다. 응답 기한이 지나면 자동으로 넘어갑니다.',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: '채팅방 열기',
              busy: _responding,
              onPressed: () => _respond(true),
            ),
            Center(
              child: TextButton(
                onPressed: _responding ? null : () => _respond(false),
                child: Text(
                  '이번에는 넘어가기',
                  style: AppText.body.copyWith(color: AppColors.textHint),
                ),
              ),
            ),
          ] else
            Text('상대의 선택을 기다리고 있습니다', style: AppText.caption),
        ],
      ),
    );
  }

  /// 상대 얼굴 — border 색은 전 탭 공통 촬영 경로 규칙 (카메라 gold / 그 외).
  Widget _photo() {
    return Container(
      width: 88,
      height: 88,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      // border 는 foreground — child 이미지가 코너 테두리를 덮지 않게.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: sourceBorderColor(p.photoSource)),
      ),
      child: p.photoUrl == null
          ? _genderFallback()
          : Image.network(
              p.photoUrl!,
              width: 88,
              height: 88,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _genderFallback(),
            ),
    );
  }

  Widget _genderFallback() => Center(
    child: Image.asset(
      p.otherGender == 'male'
          ? 'assets/icons/male.png'
          : 'assets/icons/female.png',
      width: 44,
      height: 44,
    ),
  );

  static String _deadlineLabel(DateTime decideBy) {
    final left = decideBy.difference(DateTime.now().toUtc());
    if (left.inHours >= 1) return '응답 기한 ${left.inHours}시간 남음';
    return '응답 기한 1시간 미만';
  }
}
