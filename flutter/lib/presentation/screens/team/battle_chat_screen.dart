import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/hive/hive_setup.dart';
import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../data/services/push_service.dart';
import '../../../domain/models/battle.dart';
import '../../providers/battle_provider.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/source_badge.dart';

// 메신저 레이아웃 전용 화면 국지 상수 — 색은 전부 AppColors 토큰 사용.
const _kBubbleRadius = 18.0;
const _kInputRadius = 22.0;

/// 매칭 성사 쌍 전용 1:1 인앱 채팅 — 최소 구성(rev2 §5): 메시지 리스트 +
/// 입력바, watchMatch(team_messages INSERT) 로 신규 메시지 refetch.
/// 레이아웃은 카카오톡 채팅방 parity (아바타·이름·꼬리 말풍선·분 단위 시간),
/// 배색은 앱 팔레트 (내 말풍선 goldSoft · 상대 surface).
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
  String? _otherPhotoUrl;
  AnalysisSource? _otherPhotoSource;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // 이 방을 보는 동안은 이 방의 메시지 푸시 배너를 생략 (Realtime 이 그린다).
    PushService.instance.activeChatTeamId = widget.teamId;
    _load();
    _channel = _service.watchMatch(widget.teamId, _load);
    // 상대 아바타 — 매칭 카드와 같은 my-face 썸네일, 실패 시 아이콘 fallback.
    _service.fetchMyFaceThumbnailUrls([widget.otherUserId]).then((thumbs) {
      if (mounted) {
        setState(() {
          _otherPhotoUrl = thumbs[widget.otherUserId]?.url;
          _otherPhotoSource = thumbs[widget.otherUserId]?.source;
        });
      }
    });
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
    // 이 방을 보고 있는 동안 도착분까지 읽음 처리 — 안읽음 뱃지·밴드 기준.
    if (messages.isNotEmpty) {
      Hive.box<String>(HiveBoxes.prefs).put(
        chatLastSeenKey(widget.teamId),
        messages.last.createdAt.toIso8601String(),
      );
    }
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
          '차단하면 상대에게 알리지 않고, 앞으로 같은 매칭그룹에 함께 참가할 수 없게 됩니다. 설정의 차단 목록에서 해제할 수 있습니다.',
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

  /// 같은 분(minute) 묶음 판정 키 — 시간 라벨은 묶음의 마지막 메시지에만 붙는다.
  static String _minuteKey(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${l.month}-${l.day} ${l.hour}:${l.minute}';
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) {
                        final c = _messages.length - 1 - i;
                        final msg = _messages[c];
                        final prev = c > 0 ? _messages[c - 1] : null;
                        final next = c < _messages.length - 1
                            ? _messages[c + 1]
                            : null;
                        final isMine = msg.senderId == myUid;
                        return _MessageRow(
                          message: msg,
                          isMine: isMine,
                          // 발신자가 바뀌는 첫 메시지 — 아바타·이름·말풍선 꼬리.
                          firstOfRun:
                              prev == null || prev.senderId != msg.senderId,
                          // 같은 발신자·같은 분 묶음의 마지막에만 시간 표시.
                          showTime:
                              next == null ||
                              next.senderId != msg.senderId ||
                              _minuteKey(next.createdAt) !=
                                  _minuteKey(msg.createdAt),
                          nickname: widget.otherNickname,
                          photoUrl: _otherPhotoUrl,
                          photoSource: _otherPhotoSource,
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

  /// pill 형태 입력바 — 카카오톡 하단 입력창 parity, 배색은 surface 토큰.
  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(_kInputRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLength: 500,
                minLines: 1,
                maxLines: 4,
                style: AppText.body.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  hintText: '메시지 입력',
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
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
      ),
    );
  }
}

/// 카카오톡 parity 레이아웃 메시지 행 (배색은 앱 팔레트).
/// - 내 메시지: goldSoft 말풍선 우측 정렬, 시간은 말풍선 왼쪽 하단.
/// - 상대 메시지: 그룹 첫 줄에 squircle 아바타 + 닉네임, surface 말풍선,
///   시간은 말풍선 오른쪽 하단. 이어지는 줄은 아바타 폭만큼 들여쓰기.
/// - [firstOfRun] 말풍선에만 바깥 위 모서리 꼬리(nib).
/// [onLongPress] — 상대 메시지 신고 진입 (내 메시지는 null).
class _MessageRow extends StatelessWidget {
  final BattleMessage message;
  final bool isMine;
  final bool firstOfRun;
  final bool showTime;
  final String nickname;
  final String? photoUrl;
  final AnalysisSource? photoSource;
  final VoidCallback? onLongPress;
  const _MessageRow({
    required this.message,
    required this.isMine,
    required this.firstOfRun,
    required this.showTime,
    required this.nickname,
    required this.photoUrl,
    required this.photoSource,
    this.onLongPress,
  });

  static const double _avatarSize = 40;

  /// '오후 3:13' — 카카오톡과 같은 한국어 12시간제.
  static String _timeLabel(DateTime t) {
    final l = t.toLocal();
    final h12 = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.hour < 12 ? '오전' : '오후'} $h12:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final time = Text(_timeLabel(message.createdAt), style: AppText.hint);
    final bubble = _bubble(context);
    final runGap = EdgeInsets.only(
      top: firstOfRun ? AppSpacing.md : AppSpacing.xs,
    );

    if (isMine) {
      return Padding(
        padding: runGap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (showTime)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: time,
              ),
            Flexible(child: bubble),
          ],
        ),
      );
    }

    return Padding(
      padding: runGap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (firstOfRun) _avatar() else const SizedBox(width: _avatarSize),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (firstOfRun) ...[
                  Text(
                    nickname,
                    style: AppText.caption.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(child: bubble),
                    if (showTime)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: time,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    final content = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isMine ? AppColors.goldSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(_kBubbleRadius),
        ),
        child: Text(
          message.body,
          style: AppText.body.copyWith(
            color: AppColors.textPrimary,
            height: 1.4,
          ),
        ),
      ),
    );
    if (!firstOfRun) return content;
    // 그룹 첫 말풍선에만 붙는 꼬리 — 상대는 아바타 쪽(좌), 나는 우측 상단.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        Positioned(
          top: 6,
          left: isMine ? null : -5,
          right: isMine ? -5 : null,
          child: CustomPaint(
            size: const Size(6, 12),
            painter: _BubbleTailPainter(
              color: isMine ? AppColors.goldSoft : AppColors.surface,
              pointsLeft: !isMine,
            ),
          ),
        ),
      ],
    );
  }

  Widget _avatar() {
    const fallback = Center(
      child: FaIcon(FontAwesomeIcons.user, size: 16, color: AppColors.textHint),
    );
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        // border 색은 source 규칙 (카메라 gold / 앨범 lightGray).
        border: Border.all(color: sourceBorderColor(photoSource)),
      ),
      child: photoUrl == null
          ? fallback
          : Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

/// 말풍선 꼬리 삼각형 — 말풍선과 같은 색으로 바깥쪽을 향해 그린다.
class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool pointsLeft;
  const _BubbleTailPainter({required this.color, required this.pointsLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsLeft) {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height * 0.35);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height * 0.35);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pointsLeft != pointsLeft;
}
