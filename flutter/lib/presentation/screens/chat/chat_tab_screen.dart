import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../domain/models/battle.dart';
import '../../providers/battle_provider.dart';
import '../../providers/tab_provider.dart';
import '../../widgets/emotion_empty_state.dart';
import '../../widgets/source_badge.dart';

/// 채팅 탭 — 열린 매칭 채팅방 목록 (카카오톡 채팅 목록 parity 레이아웃).
/// 행: squircle 아바타 / 닉네임 + 마지막 메시지 / 시간 + 안읽음 dot.
/// 탭하면 기존 `/chat/:id` 라우트 재사용 (매칭·닉네임 resolve 포함),
/// 복귀 시 openChatsProvider invalidate 로 읽음 상태 반영.
class ChatTabScreen extends ConsumerWidget {
  const ChatTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(openChatsProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('채팅')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(openChatsProvider.future),
        color: AppColors.textPrimary,
        child: chats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _fillScroll(
            const EmotionEmptyState(
              asset: 'assets/images/emotion-sad.png',
              message: '채팅 목록을 불러오지 못했습니다.\n아래로 당겨 새로고침하세요.',
            ),
          ),
          data: (list) => list.isEmpty
              ? _fillScroll(
                  _EmptyChats(
                    onGoChemistry: () =>
                        ref.read(selectedTabProvider.notifier).selectTab(2),
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
    );
  }

  /// 빈/에러 상태도 당겨서 새로고침 가능하게 스크롤 영역으로 감싼다.
  Widget _fillScroll(Widget child) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );
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
          asset: 'assets/images/emotion-love.png',
          message: '케미 그룹에서 베스트 매칭이 되면\n여기에 1:1 채팅방이 생깁니다.',
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
            child: const Text('케미 그룹 보러 가기', style: AppText.subTitle),
          ),
        ),
      ],
    );
  }
}

/// 채팅방 한 줄 — 아바타 48, 닉네임(subTitle) + 마지막 메시지(caption) 1줄,
/// 우측 시간(hint) + 안읽음 gold dot.
class _ChatTile extends ConsumerWidget {
  final OpenChat chat;
  const _ChatTile({required this.chat});

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
}

/// 채팅방 화면 아바타와 동일 레시피 (surface + border squircle).
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
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
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
