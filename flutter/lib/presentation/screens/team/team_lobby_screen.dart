import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../../domain/services/share/share_publisher.dart';
import '../../providers/battle_provider.dart';
import '../../widgets/compact_snack_bar.dart';
import 'team_reveal_screen.dart';

/// Chemistry Battle 로비 — 슬롯이 차오르는 대기 화면.
/// Realtime(teams UPDATE + team_members INSERT/DELETE) 구독 + 10초 폴링
/// 안전망. 정원 충족(status=revealing)을 감지하면 리빌로 넘어간다.
class TeamLobbyScreen extends ConsumerStatefulWidget {
  final String battleId;
  const TeamLobbyScreen({super.key, required this.battleId});

  @override
  ConsumerState<TeamLobbyScreen> createState() => _TeamLobbyScreenState();
}

class _TeamLobbyScreenState extends ConsumerState<TeamLobbyScreen> {
  final _service = BattleService.instance;
  Battle? _battle;
  List<BattleRosterEntry> _roster = const [];
  Map<String, String?> _thumbs = const {};
  RealtimeChannel? _channel;
  Timer? _poll;
  bool _loading = true;
  int _refreshSeq = 0;
  bool _navigatedToReveal = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _channel = _service.watchBattle(widget.battleId, _refresh);
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    final ch = _channel;
    if (ch != null) _service.unwatch(ch);
    super.dispose();
  }

  Future<void> _refresh() async {
    final seq = ++_refreshSeq;
    try {
      final battle = await _service.fetchBattle(widget.battleId);
      if (!mounted || seq != _refreshSeq) return;
      if (battle == null) {
        Navigator.of(context).maybePop();
        return;
      }
      if (battle.status != BattleStatus.recruiting) {
        _onBattleStarted(battle);
        return;
      }
      final roster = await _service.fetchRoster(widget.battleId);
      final thumbs = await _service
          .fetchMyFaceThumbnailUrls([for (final r in roster) r.userId]);
      if (!mounted || seq != _refreshSeq) return;
      setState(() {
        _battle = battle;
        _roster = roster;
        _thumbs = thumbs;
        _loading = false;
      });
    } catch (_) {}
  }

  void _onBattleStarted(Battle battle) {
    if (_navigatedToReveal) return;
    _navigatedToReveal = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => TeamRevealScreen(
        battleId: widget.battleId,
        ceremony: !battle.hasResult,
      ),
    ));
  }

  bool get _isOwner =>
      _battle != null && _battle!.ownerId == _service.myUid;

  /// iOS 공유 시트(popover) anchor — async gap 전에 미리 계산.
  Rect? get _shareOrigin {
    final box = context.findRenderObject() as RenderBox?;
    return box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  Future<void> _leave() async {
    try {
      await _service.leaveBattle(widget.battleId);
      if (mounted) {
        ref.invalidate(myBattlesProvider);
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

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('방 삭제', style: AppText.modalTitle),
        content: const Text('참가자 명단이 함께 삭제됩니다.', style: AppText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소', style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteBattle(widget.battleId);
      if (mounted) {
        ref.invalidate(myBattlesProvider);
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

  @override
  Widget build(BuildContext context) {
    final battle = _battle;
    return Scaffold(
      appBar: AppBar(
        title: Text(battle?.title ?? '케미 배틀'),
        actions: [
          if (battle != null)
            PopupMenuButton<String>(
              icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 18),
              onSelected: (v) => v == 'leave' ? _leave() : _delete(),
              itemBuilder: (_) => [
                if (!_isOwner)
                  const PopupMenuItem(value: 'leave', child: Text('나가기')),
                if (_isOwner)
                  const PopupMenuItem(value: 'delete', child: Text('방 삭제')),
              ],
            ),
        ],
      ),
      body: _loading || battle == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _headerCard(battle),
                  if (battle.pledge != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _pledgeBanner(battle),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  _slotGrid(battle),
                  const SizedBox(height: AppSpacing.xl),
                  _qrCard(),
                  const SizedBox(height: AppSpacing.xl),
                  _inviteRow(battle),
                ],
              ),
            ),
    );
  }

  Widget _headerCard(Battle battle) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_roster.length} / ${battle.maxPlayers} 명',
              style: AppText.display),
          const SizedBox(height: AppSpacing.xs),
          Text('정원이 다 차면 자동으로 시작됩니다', style: AppText.caption),
          const SizedBox(height: AppSpacing.sm),
          Text(battle.ageRangeLabel, style: AppText.hint),
        ],
      ),
    );
  }

  Widget _pledgeBanner(Battle battle) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.goldSoft.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이 방의 공약', style: AppText.subTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(battle.pledge!, style: AppText.body),
          const SizedBox(height: AppSpacing.xs),
          Text('베스트 케미로 뽑힌 두 사람이 실행합니다', style: AppText.hint),
        ],
      ),
    );
  }

  Widget _slotGrid(Battle battle) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.72,
      ),
      itemCount: battle.maxPlayers,
      itemBuilder: (_, i) {
        final entry = i < _roster.length ? _roster[i] : null;
        return _SlotCell(
          entry: entry,
          thumbUrl: entry == null ? null : _thumbs[entry.userId],
          isMe: entry?.userId == _service.myUid,
        );
      },
    );
  }

  Widget _qrCard() {
    final url = SharePublisher.instance.teamInviteUrl(widget.battleId);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          QrImageView(data: url, size: 160),
          const SizedBox(height: AppSpacing.sm),
          Text('같은 자리에서는 이 코드를 스캔해 참가합니다',
              style: AppText.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _inviteRow(Battle battle) {
    return Row(
      children: [
        Expanded(
          child: _inviteTile(
            icon: FontAwesomeIcons.solidComment,
            label: '카톡 초대',
            onTap: () => SharePublisher.instance.publishTeamInvite(
              teamTitle: battle.title,
              roomId: widget.battleId,
              sharePositionOrigin: _shareOrigin,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _inviteTile(
            icon: FontAwesomeIcons.arrowUpFromBracket,
            label: '링크 공유',
            onTap: () => SharePublisher.instance.shareTeamInviteLink(
              teamTitle: battle.title,
              roomId: widget.battleId,
              sharePositionOrigin: _shareOrigin,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _inviteTile(
            icon: FontAwesomeIcons.copy,
            label: '복사',
            onTap: () async {
              await Clipboard.setData(ClipboardData(
                  text: SharePublisher.instance
                      .teamInviteUrl(widget.battleId)));
              if (mounted) {
                showTopSnackBar(
                  Overlay.of(context),
                  CompactSnackBar.success(message: '링크를 복사했습니다'),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _inviteTile({
    required FaIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.textPrimary),
        ),
        child: Column(
          children: [
            FaIcon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: AppText.caption.copyWith(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _SlotCell extends StatelessWidget {
  final BattleRosterEntry? entry;
  final String? thumbUrl;
  final bool isMe;
  const _SlotCell({required this.entry, required this.thumbUrl, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final filled = entry != null;
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: filled
                  ? (entry!.isOwner ? AppColors.gold : AppColors.border)
                  : AppColors.border,
            ),
          ),
          child: ClipOval(
            child: !filled
                ? const Center(
                    child: FaIcon(FontAwesomeIcons.user,
                        size: 16, color: AppColors.border))
                : thumbUrl == null
                    ? const Center(
                        child: FaIcon(FontAwesomeIcons.solidUser,
                            size: 16, color: AppColors.textHint))
                    : Image.network(thumbUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                            child: FaIcon(FontAwesomeIcons.solidUser,
                                size: 16, color: AppColors.textHint))),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          !filled ? '대기 중' : (isMe ? '나' : entry!.nickname),
          style: AppText.hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
