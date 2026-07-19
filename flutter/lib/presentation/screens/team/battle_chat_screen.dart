import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../data/services/push_service.dart';
import '../../../domain/models/battle.dart';
import '../../widgets/compact_snack_bar.dart';

/// 매칭 성사 쌍 전용 1:1 인앱 채팅 — 최소 구성(rev2 §5): 메시지 리스트 +
/// 입력바, watchMatch(team_messages INSERT) 로 신규 메시지 refetch.
class BattleChatScreen extends StatefulWidget {
  final String teamId;
  final String otherUserId;
  final String otherNickname;

  const BattleChatScreen({
    super.key,
    required this.teamId,
    required this.otherUserId,
    required this.otherNickname,
  });

  @override
  State<BattleChatScreen> createState() => _BattleChatScreenState();
}

class _BattleChatScreenState extends State<BattleChatScreen> {
  final _service = BattleService.instance;
  final _controller = TextEditingController();
  List<BattleMessage> _messages = const [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // 이 방을 보는 동안은 이 방의 메시지 푸시 배너를 생략 (Realtime 이 그린다).
    PushService.instance.activeChatTeamId = widget.teamId;
    _load();
    _channel = _service.watchMatch(widget.teamId, _load);
  }

  @override
  void dispose() {
    if (PushService.instance.activeChatTeamId == widget.teamId) {
      PushService.instance.activeChatTeamId = null;
    }
    final ch = _channel;
    if (ch != null) _service.unwatch(ch);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final messages = await _service.fetchMessages(widget.teamId);
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _loading = false;
    });
  }

  /// 신고 사유 프리셋 — 스토어 UGC 정책의 신고 경로. 선택 즉시 접수.
  static const _reportReasons = ['스팸·광고', '욕설·비방', '음란·성적 발언', '기타 부적절한 행위'];

  /// [message] 를 주면 개별 메시지 신고 — 사유에 메시지 본문을 함께 접수해
  /// 운영이 맥락을 본다 (말풍선 길게 누르기 진입).
  Future<void> _report({BattleMessage? message}) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: Text(
          message == null ? '신고하기' : '메시지 신고',
          style: AppText.modalTitle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in _reportReasons)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(r),
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                child: Text(r, style: AppText.body),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '취소',
              style: AppText.body.copyWith(color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    // 메시지 신고는 본문을 사유에 동봉 — 서버 check(200자) 안으로 자른다.
    final packed = message == null
        ? reason
        : '[메시지] $reason · "${message.body}"'.characters.take(200).toString();
    try {
      await _service.reportChatUser(
        teamId: widget.teamId,
        reportedId: widget.otherUserId,
        reason: packed,
      );
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.success(message: '신고가 접수되었습니다'),
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: mapBattleError(e).labelKo),
        );
      }
    }
  }

  /// 차단 — 무통보·같은 방 조인 불가라는 결과를 확인 다이얼로그에 명시해
  /// 충동 차단을 줄인다. 성공 시 채팅을 닫는다. 해제는 설정 > 차단 목록.
  Future<void> _block() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('차단하기', style: AppText.modalTitle),
        content: const Text(
          '차단하면 상대에게 알리지 않고, 앞으로 같은 매칭방에 함께 참가할 수 없게 됩니다. 설정의 차단 목록에서 해제할 수 있습니다.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '취소',
              style: AppText.body.copyWith(color: AppColors.textHint),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '차단',
              style: AppText.body.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.blockUser(widget.otherUserId);
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.success(message: '차단했습니다'),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: mapBattleError(e).labelKo),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(widget.teamId, text);
      _controller.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: mapBattleError(e).labelKo),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _service.myUid;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherNickname),
        actions: [
          PopupMenuButton<String>(
            icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 18),
            onSelected: (v) => v == 'report' ? _report() : _block(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('신고하기')),
              PopupMenuItem(value: 'block', child: Text('차단하기')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? const Center(
                      child: Text('첫 메시지를 보내보세요', style: AppText.hint),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = _messages[_messages.length - 1 - i];
                        final isMine = msg.senderId == myUid;
                        return _MessageBubble(
                          message: msg,
                          isMine: isMine,
                          // 상대 메시지만 길게 눌러 신고 (스토어 UGC 정책).
                          onLongPress: isMine
                              ? null
                              : () => _report(message: msg),
                        );
                      },
                    ),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLength: 500,
              minLines: 1,
              maxLines: 4,
              style: AppText.body,
              decoration: const InputDecoration(
                hintText: '메시지 입력',
                border: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
          IconButton(
            icon: FaIcon(
              FontAwesomeIcons.paperPlane,
              size: 18,
              color: _sending ? AppColors.textHint : AppColors.textPrimary,
            ),
            onPressed: _sending ? null : _send,
          ),
        ],
      ),
    );
  }
}

/// 버블 = surface+border 카드 레시피 단일톤 — 좌우 정렬로만 발신자 구분.
/// [onLongPress] — 상대 메시지 신고 진입 (내 메시지는 null).
class _MessageBubble extends StatelessWidget {
  final BattleMessage message;
  final bool isMine;
  final VoidCallback? onLongPress;
  const _MessageBubble({
    required this.message,
    required this.isMine,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final time = message.createdAt.toLocal();
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(message.body, style: AppText.body),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text('$hh:$mm', style: AppText.caption),
          ],
        ),
      ),
    );
  }
}
