import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../widgets/compact_snack_bar.dart';

/// 매칭 성사 쌍 전용 1:1 인앱 채팅 — 최소 구성(rev2 §5): 메시지 리스트 +
/// 입력바, watchMatch(battle_messages INSERT) 로 신규 메시지 refetch.
class BattleChatScreen extends StatefulWidget {
  final String teamId;
  final String otherNickname;

  const BattleChatScreen({
    super.key,
    required this.teamId,
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
    _load();
    _channel = _service.watchMatch(widget.teamId, _load);
  }

  @override
  void dispose() {
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
      appBar: AppBar(title: Text(widget.otherNickname)),
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
                            return _MessageBubble(
                              message: msg,
                              isMine: msg.senderId == myUid,
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
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
class _MessageBubble extends StatelessWidget {
  final BattleMessage message;
  final bool isMine;
  const _MessageBubble({required this.message, required this.isMine});

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
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(message.body, style: AppText.body),
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
