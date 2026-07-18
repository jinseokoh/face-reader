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
import '../../providers/history_provider.dart';
import '../../widgets/age_range_pill.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/login_bottom_sheet.dart';
import '../../widgets/my_face_capture_flow.dart';
import '../../widgets/primary_button.dart';
import 'team_reveal_screen.dart';

/// 케미 배틀 상세 페이지 — 참가 여부와 무관한 단일 진입점.
/// 미참가자에겐 참가 폼(PIN·사진 공개 동의·참가 CTA), 참가자에겐 슬롯
/// 그리드·QR·초대가 같은 화면 안에서 분기된다. 조인 성공도 화면 전환 없이
/// in-place 로 참가자 뷰가 된다 (멤버 판정 리다이렉트 없음).
/// Realtime(teams UPDATE + team_members INSERT/DELETE) 구독 + 10초 폴링
/// 안전망. 정원 충족(status=revealing)을 감지하면 참가자만 리빌로 넘어간다.
class BattleDetailScreen extends ConsumerStatefulWidget {
  final String battleId;
  const BattleDetailScreen({super.key, required this.battleId});

  @override
  ConsumerState<BattleDetailScreen> createState() =>
      _BattleDetailScreenState();
}

class _BattleDetailScreenState extends ConsumerState<BattleDetailScreen> {
  final _service = BattleService.instance;
  final _pinCtrl = TextEditingController();
  Battle? _battle;
  List<BattleRosterEntry> _roster = const [];
  Map<String, BattleSlotProfile> _profiles = const {};
  RealtimeChannel? _channel;
  Timer? _poll;
  bool _loading = true;
  bool _notFound = false;
  bool _busy = false;
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
    _pinCtrl.dispose();
    final ch = _channel;
    if (ch != null) _service.unwatch(ch);
    super.dispose();
  }

  bool get _isMember {
    final myUid = _service.myUid;
    return myUid != null && _roster.any((r) => r.userId == myUid);
  }

  bool get _isOwner =>
      _battle != null && _battle!.ownerId == _service.myUid;

  Future<void> _refresh() async {
    final seq = ++_refreshSeq;
    try {
      final battle = await _service.fetchBattle(widget.battleId);
      if (!mounted || seq != _refreshSeq) return;
      if (battle == null) {
        setState(() {
          _battle = null;
          _notFound = true;
          _loading = false;
        });
        return;
      }
      final roster = await _service.fetchRoster(widget.battleId);
      if (!mounted || seq != _refreshSeq) return;
      final myUid = _service.myUid;
      final joined =
          myUid != null && roster.any((r) => r.userId == myUid);
      // 시작된 방의 참가자는 리빌로 — 최초 로드면 전환 연출 없이 즉시 교체
      // (상세가 떴다가 밀려나는 이중 전환 방지), 대기 중 시작이면 연출 전환.
      if (battle.status != BattleStatus.recruiting && joined) {
        _goReveal(battle, animated: !_loading);
        return;
      }
      // 관상 유형(archetype)은 얼굴 공개 여부와 무관하게 슬롯에 노출한다.
      // 썸네일 URL 은 thumb_open=true 인 방에서만 사용 (_SlotCell 게이트).
      final profiles = joined
          ? await _service
              .fetchSlotProfiles([for (final r in roster) r.userId])
          : _profiles;
      if (!mounted || seq != _refreshSeq) return;
      setState(() {
        _battle = battle;
        _roster = roster;
        _profiles = profiles;
        _notFound = false;
        _loading = false;
      });
    } catch (_) {}
  }

  void _goReveal(Battle battle, {bool animated = true}) {
    if (_navigatedToReveal) return;
    _navigatedToReveal = true;
    Widget dest(BuildContext _) => TeamRevealScreen(
          battleId: widget.battleId,
          ceremony: !battle.hasResult,
        );
    Navigator.of(context).pushReplacement(animated
        ? MaterialPageRoute(builder: dest)
        : PageRouteBuilder(
            pageBuilder: (context, _, _) => dest(context),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ));
  }

  // ── 참가 (미참가자) ─────────────────────────────────────────────────────

  /// 이성방 — 성별 남은 자리 수 (roster gender 카운트 기준, 0 미만 표시 방지).
  int _remaining(String gender) {
    final per = _battle!.maxPlayers ~/ 2;
    final count = _roster.where((r) => r.gender == gender).length;
    return (per - count).clamp(0, per);
  }

  Future<void> _join() async {
    final battle = _battle!;
    // ① 로그인 게이트 — login_bottom_sheet 패턴.
    if (!_service.isLoggedIn) {
      final ok = await showLoginBottomSheet(context, ref);
      if (!ok || !mounted) return;
    }
    // ② my-face 게이트.
    final hasMyFace =
        ref.read(historyProvider).any((r) => r.isMyFace);
    if (!hasMyFace) {
      await startMyFaceCapture(context, ref);
      if (!mounted ||
          !ref.read(historyProvider).any((r) => r.isMyFace)) {
        return;
      }
    }
    setState(() => _busy = true);
    final myFace =
        ref.read(historyProvider).where((r) => r.isMyFace).firstOrNull;
    if (myFace == null || !await _service.ensureMyFaceOnServer(myFace)) {
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: '내 관상 서버 등록에 실패했습니다'),
        );
        setState(() => _busy = false);
      }
      return;
    }
    try {
      await _service.joinBattle(
        widget.battleId,
        password: battle.isPublic ? null : _pinCtrl.text.trim(),
      );
      ref.invalidate(myBattlesProvider);
      ref.invalidate(publicBattlesProvider);
      // _busy 는 유지 — 다음 refresh 가 참가자 뷰로 바꾸며 버튼 자체가
      // 사라진다 (화면 전환 없음, 정원 충족 시엔 리빌로).
      if (mounted) await _refresh();
    } catch (e) {
      final err = mapBattleError(e);
      if (err == BattleJoinError.alreadyJoined) {
        if (mounted) await _refresh();
        return;
      }
      if (mounted) {
        final label = err == BattleJoinError.genderFull
            ? genderFullLabel(myFace.gender.name)
            : err.labelKo;
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: label),
        );
        setState(() => _busy = false);
      }
    }
  }

  // ── 이탈·삭제 (참가자) ──────────────────────────────────────────────────

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
        ref.invalidate(publicBattlesProvider);
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
            child: Text('취소',
                style: AppText.body.copyWith(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('삭제',
                style: AppText.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteBattle(widget.battleId);
      if (mounted) {
        ref.invalidate(myBattlesProvider);
        ref.invalidate(publicBattlesProvider);
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

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final battle = _battle;
    final member = _isMember;
    return Scaffold(
      appBar: AppBar(
        // 방 제목은 헤더 카드가 보여준다 — AppBar 는 고정 타이틀 (로딩 중
        // 타이틀이 방제목으로 바뀌는 깜빡임 제거).
        title: const Text('케미 배틀 상세정보'),
        actions: [
          if (battle != null && member && battle.isRecruiting)
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
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _notFound || battle == null
                ? Center(
                    child: Text('존재하지 않는 방입니다', style: AppText.body))
                : !battle.isRecruiting
                    ? _closedBody(battle)
                    : member
                        ? _memberBody(battle)
                        : _joinBody(battle),
      ),
    );
  }

  /// 시작·종료된 방의 미참가자 뷰 — 참가자는 _refresh 가 리빌로 보낸다.
  Widget _closedBody(Battle battle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.huge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              battle.status == BattleStatus.expired
                  ? '인원이 모이지 않아 종료된 방입니다'
                  : '이미 시작된 방입니다',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            if (battle.hasResult) ...[
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: '결과 보기',
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) =>
                        TeamRevealScreen(battleId: widget.battleId),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 미참가자 body ──────────────────────────────────────────────────────

  Widget _joinBody(Battle battle) {
    final canJoin = battle.isPublic || _pinCtrl.text.trim().length == 4;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _headerCard(battle, showRemaining: true),
          if (!battle.isPublic) ...[
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppText.body.copyWith(color: AppColors.textPrimary),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: '비밀번호 4자리'),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          _photoConsentNotice(battle),
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(
            label: '동의하고 참가',
            busy: _busy,
            onPressed: canJoin && !_busy ? _join : null,
          ),
        ],
      ),
    );
  }

  /// 사진 공개 계약 문구 — 정보성 고지, 체크박스 없음. 조인 = 동의(UX §E.1).
  Widget _photoConsentNotice(Battle battle) {
    final text = battle.roomKind == BattleRoomKind.match
        ? '베스트 매칭이 되면 상대에게 내 사진이 공개되고, 서로 동의하면 1:1 채팅이 열립니다'
        : '베스트 케미로 뽑히면 상대에게 내 사진이 공개됩니다';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: AppText.caption),
    );
  }

  // ── 참가자 body ────────────────────────────────────────────────────────

  Widget _memberBody(Battle battle) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _headerCard(battle),
          const SizedBox(height: AppSpacing.xl),
          _slotGrid(battle),
          const SizedBox(height: AppSpacing.xl),
          _qrCard(),
          const SizedBox(height: AppSpacing.xl),
          _inviteRow(battle),
        ],
      ),
    );
  }

  /// 공개 배틀 카드(_PublicCard)와 동일한 결 — 제목 + 연령 pill / 정원.
  /// [showRemaining] = 미참가 이성방에서 성별 남은 자리 표시 (참가자 뷰는
  /// 슬롯 열 헤더가 같은 정보를 보여주므로 생략).
  Widget _headerCard(Battle battle, {bool showRemaining = false}) {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(battle.title, style: AppText.subTitle)),
              const SizedBox(width: AppSpacing.sm),
              AgeRangePill(label: battle.ageRangeLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('${_roster.length} / ${battle.maxPlayers} 명',
              style: AppText.caption),
          if (showRemaining &&
              battle.roomKind == BattleRoomKind.match) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('남자 ${_remaining('male')}자리 남음', style: AppText.caption),
            Text('여자 ${_remaining('female')}자리 남음', style: AppText.caption),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            '정원이 다 차면 케미 결과표가 자동으로 발표됩니다',
            style: AppText.caption.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _slotGrid(Battle battle) {
    if (battle.roomKind == BattleRoomKind.match) {
      final perGender = battle.maxPlayers ~/ 2;
      final males = _roster.where((r) => r.gender == 'male').toList();
      final females = _roster.where((r) => r.gender == 'female').toList();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _genderColumn(
              battle: battle,
              gender: 'male',
              label: '남자',
              entries: males,
              slotCount: perGender,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: _genderColumn(
              battle: battle,
              gender: 'female',
              label: '여자',
              entries: females,
              slotCount: perGender,
            ),
          ),
        ],
      );
    }
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
        final profile = entry == null ? null : _profiles[entry.userId];
        return _SlotCell(
          entry: entry,
          thumbUrl: profile?.thumbUrl,
          archetype: profile?.archetype,
          isMe: entry?.userId == _service.myUid,
          thumbOpen: battle.thumbOpen,
        );
      },
    );
  }

  /// 이성방 남/여 열 — 헤더(성별 아이콘 16px + "남자 N / M")+ 세로 슬롯 목록.
  /// 색 구분 없이 열 위치·헤더·빈 슬롯 아이콘 세 겹으로 성별을 표현한다.
  Widget _genderColumn({
    required Battle battle,
    required String gender,
    required String label,
    required List<BattleRosterEntry> entries,
    required int slotCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset(_genderIconAsset(gender), width: 16, height: 16),
            const SizedBox(width: AppSpacing.xs),
            Text('$label ${entries.length} / $slotCount',
                style: AppText.sectionTitle),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < slotCount; i++)
          Padding(
            padding: EdgeInsets.only(
                bottom: i == slotCount - 1 ? 0 : AppSpacing.lg),
            child: _SlotCell(
              entry: i < entries.length ? entries[i] : null,
              thumbUrl: i < entries.length
                  ? _profiles[entries[i].userId]?.thumbUrl
                  : null,
              archetype: i < entries.length
                  ? _profiles[entries[i].userId]?.archetype
                  : null,
              isMe: i < entries.length &&
                  entries[i].userId == _service.myUid,
              thumbOpen: battle.thumbOpen,
              slotGender: gender,
            ),
          ),
      ],
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
            Text(label,
                style: AppText.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// male/female 성별 기본 아이콘 asset 경로.
String _genderIconAsset(String gender) =>
    gender == 'male' ? 'assets/icons/male.png' : 'assets/icons/female.png';

class _SlotCell extends StatelessWidget {
  final BattleRosterEntry? entry;
  final String? thumbUrl;
  /// 관상 유형 라벨(신의형·연예인형…) — 슬롯의 관심 유도 포인트.
  final String? archetype;
  final bool isMe;
  final bool thumbOpen;
  /// 이성방 빈 슬롯의 열 성별 — alpha 0.35 성별 아이콘 표시용. 전체방은 null
  /// (성별 미정 FaIcon `user` 유지).
  final String? slotGender;
  const _SlotCell({
    required this.entry,
    required this.thumbUrl,
    required this.archetype,
    required this.isMe,
    required this.thumbOpen,
    this.slotGender,
  });

  /// 전체방은 성별이 열로 안 드러나므로 "남 신의형" 처럼 성별을 붙이고,
  /// 이성방은 열 헤더가 성별을 이미 말해주므로 유형만.
  String? get _archetypeLine {
    final a = archetype;
    if (entry == null || a == null) return null;
    if (slotGender != null) return a;
    return '${entry!.gender == 'male' ? '남' : '여'} $a';
  }

  @override
  Widget build(BuildContext context) {
    final filled = entry != null;
    final typeLine = _archetypeLine;
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
          child: ClipOval(child: _avatar()),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          !filled ? '대기 중' : (isMe ? '나' : entry!.nickname),
          style: AppText.hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (typeLine != null)
          Text(
            typeLine,
            style: AppText.hint.copyWith(color: AppColors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _avatar() {
    if (entry == null) {
      final gender = slotGender;
      if (gender == null) {
        return const Center(
            child: FaIcon(FontAwesomeIcons.user,
                size: 16, color: AppColors.border));
      }
      return Opacity(
        opacity: 0.35,
        child: Image.asset(_genderIconAsset(gender), fit: BoxFit.cover),
      );
    }
    // thumb_open=false — 얼굴 썸네일 대신 참가자 성별 기본 아이콘.
    if (!thumbOpen) {
      return Image.asset(_genderIconAsset(entry!.gender), fit: BoxFit.cover);
    }
    return thumbUrl == null
        ? const Center(
            child: FaIcon(FontAwesomeIcons.solidUser,
                size: 16, color: AppColors.textHint))
        : Image.network(thumbUrl!, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Center(
                child: FaIcon(FontAwesomeIcons.solidUser,
                    size: 16, color: AppColors.textHint)));
  }
}
