import 'dart:math' as math;

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../domain/models/team.dart';
import '../../providers/team_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/tab_provider.dart';
import '../../widgets/emotion_empty_state.dart';
import '../../widgets/face_scan_pill.dart';
import '../../widgets/source_badge.dart';
import 'match_proposal_sheet.dart';

/// 채팅 탭 — 열린 매칭 채팅방 목록 (카카오톡 채팅 목록 parity 레이아웃).
/// 행: 42 원형 아바타 / 닉네임 + 마지막 메시지 / 시간 + 안읽음 dot.
/// 탭하면 기존 `/chat/:id` 라우트 재사용 (매칭·닉네임 resolve 포함),
/// 복귀 시 openChatsProvider invalidate 로 읽음 상태 반영.
class ChatTabScreen extends ConsumerWidget {
  const ChatTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 관상·궁합·케미 탭과 동일 규칙 — 미등록이면 [내 관상 보기] pill +
    // 안내 empty state, 본 화면은 등록 후에만.
    final hasMyFace = ref.watch(historyProvider).any((r) => r.isMyFace);
    final chats = ref.watch(openChatsProvider);
    final proposalCount = ref.watch(matchProposalsProvider).value?.length ?? 0;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('채팅'),
        actions: [
          if (!hasMyFace) const FaceScanPill() else const _MatchProposalBadge(),
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 20),
            tooltip: '매칭 채팅에 대하여',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          !hasMyFace
              ? const EmotionEmptyState(
                  asset: 'assets/images/emotion-yawn.png',
                  message: '채팅에 참여하려면 내관상을 등록하세요',
                )
              : RefreshIndicator(
                  onRefresh: () {
                    ref.invalidate(matchProposalsProvider);
                    return ref.refresh(openChatsProvider.future);
                  },
                  color: AppColors.textPrimary,
                  child: chats.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => _fillScroll(
                      const EmotionEmptyState(
                        asset: 'assets/images/emotion-sad.png',
                        message: '채팅 목록을 불러오지 못했습니다.\n아래로 당겨 새로고침하세요.',
                      ),
                    ),
                    data: (list) => list.isEmpty
                        ? _fillScroll(
                            _EmptyChats(
                              onGoChemistry: () => ref
                                  .read(selectedTabProvider.notifier)
                                  .selectTab(2),
                            ),
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            itemCount: list.length,
                            itemBuilder: (ctx, i) => _ChatTile(chat: list[i]),
                          ),
                  ),
                ),
          // 미결 베스트 매칭 callout — award 아이콘 바로 아래를 가리키는
          // 빨간 말풍선. 제안이 남아있는 동안 계속 떠서 반드시 눈에 띈다.
          // 탭 = 제안 시트 (뱃지와 동일 진입).
          if (hasMyFace && proposalCount > 0)
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.sm,
              child: _BestPickCallout(
                onTap: () => showMatchProposalSheet(context),
              ),
            ),
        ],
      ),
    );
  }

  /// 빈/에러 상태도 당겨서 새로고침 가능하게 스크롤 영역으로 감싼다.
  Widget _fillScroll(Widget child) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
    );
  }

  /// 케미 탭 info 다이얼로그와 동일 레시피 — 매칭 채팅 규칙 안내.
  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('매칭 채팅', style: AppText.modalTitle),
        content: const SingleChildScrollView(
          child: Text(
            '케미 그룹에서 최고의 케미를 보인 베스트 매칭 한 쌍에게는 '
            '1:1 채팅 기회가 주어집니다.\n\n'
            '두 사람 모두 원하는 경우에만 채팅방이 열리고, 한쪽이라도 '
            '거부하면 열리지 않습니다. 응답은 결과 발표 후 48시간 동안 '
            '가능합니다.\n\n'
            '응답을 기다리는 매칭 제안은 우상단 하트 뱃지에서, 열린 '
            '채팅방은 이 화면의 목록에서 확인할 수 있습니다.',
            style: AppText.body,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: AppText.subTitle),
          ),
        ],
      ),
    );
  }
}

/// 채팅방 화면 아바타와 동일 레시피 (surface + border 원형).
/// border 색은 source 규칙 (sourceBorderColor — 카메라 gold / 앨범 lightGray).
class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final AnalysisSource? photoSource;
  const _Avatar({required this.photoUrl, required this.photoSource});

  @override
  Widget build(BuildContext context) {
    const fallback = Center(
      child: FaIcon(FontAwesomeIcons.user, size: 18, color: AppColors.textHint),
    );
    final url = photoUrl;
    // border 는 foregroundDecoration — decoration 에 두면 child(이미지)가
    // 곡선 구간에서 테두리 안쪽 절반을 덮어 코너가 끊겨 보인다.
    // 리스트 아바타 표준 — 42 원형 (관상·궁합·케미 슬롯과 동일 문법).
    return Container(
      width: AppAvatar.md,
      height: AppAvatar.md,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
      ),
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: sourceBorderColor(photoSource)),
      ),
      child: url == null
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// 채팅방 한 줄 — 아바타 42 원형, 닉네임(subTitle) + 마지막 메시지(caption) 1줄,
/// 우측 시간(hint) + 안읽음 gold dot.
class _ChatTile extends ConsumerWidget {
  final OpenChat chat;
  const _ChatTile({required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = chat.lastMessage;
    return InkWell(
      onTap: () async {
        await context.push('/chat/${chat.teamId}');
        ref.invalidate(openChatsProvider);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            _Avatar(photoUrl: chat.photoUrl, photoSource: chat.photoSource),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.otherNickname,
                    style: AppText.subTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    last?.body ?? '아직 메시지가 없습니다',
                    style: AppText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (last != null)
                  Text(_timeLabel(last.createdAt), style: AppText.hint),
                if (chat.hasUnread)
                  Container(
                    margin: const EdgeInsets.only(top: AppSpacing.xs),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 오늘 = '오후 3:13', 어제 = '어제', 그 외 = 'M월 d일'.
  static String _timeLabel(DateTime t) {
    final l = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(l.year, l.month, l.day);
    if (day == today) {
      final h12 = l.hour % 12 == 0 ? 12 : l.hour % 12;
      final mm = l.minute.toString().padLeft(2, '0');
      return '${l.hour < 12 ? '오전' : '오후'} $h12:$mm';
    }
    if (today.difference(day).inDays == 1) return '어제';
    return '${l.month}월 ${l.day}일';
  }
}

/// 빈 상태 — 채팅방 생성 조건 안내 + 케미 탭 전환 CTA.
class _EmptyChats extends StatelessWidget {
  final VoidCallback onGoChemistry;
  const _EmptyChats({required this.onGoChemistry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const EmotionEmptyState(
          asset: 'assets/images/emotion-namaste.png',
          message: '베스트 매칭 후 두 사람이 모두 동의하면\n여기에 1:1 채팅방이 생깁니다.',
        ),
        const SizedBox(height: AppSpacing.xl),
        InkWell(
          onTap: onGoChemistry,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.textPrimary),
            ),
            child: const Text('케미 그룹 보러가기', style: AppText.subTitle),
          ),
        ),
      ],
    );
  }
}

/// appbar 우상단 베스트 매칭 뱃지 — 미결 제안이 있을 때만 노출.
/// 탭하면 매칭 제안 시트 (사진 + 채팅방 열기/넘어가기).
class _MatchProposalBadge extends ConsumerWidget {
  const _MatchProposalBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(matchProposalsProvider).value?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return IconButton(
      onPressed: () => showMatchProposalSheet(context),
      icon: _icon(count),
    );
  }

  Widget _icon(int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const FaIcon(
          FontAwesomeIcons.award,
          size: 20,
          color: AppColors.textPrimary,
        ),
        Positioned(
          right: -8,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            decoration: const BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$count',
              style: AppText.hint.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// 미결 베스트 매칭 주목 callout — danger 말풍선 + award 아이콘을 향한 말꼬리.
/// 제안이 해소(응답·시한 만료)될 때까지 유지된다.
class _BestPickCallout extends StatelessWidget {
  final VoidCallback onTap;
  const _BestPickCallout({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 말꼬리 — appbar 의 award 아이콘(우측에서 두 번째 액션) 아래 정렬.
          Padding(
            padding: const EdgeInsets.only(right: 64),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(width: 10, height: 10, color: AppColors.danger),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -5),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                '베스트 케미로 선정되었습니다',
                style: AppText.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
