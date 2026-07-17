import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../providers/battle_provider.dart';
import '../../providers/history_provider.dart';
import '../../widgets/age_range_pill.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/login_bottom_sheet.dart';
import '../../widgets/my_face_capture_flow.dart';
import '../../widgets/primary_button.dart';
import 'team_lobby_screen.dart';
import 'team_reveal_screen.dart';

/// 배틀 참가 — 로그인 → 내 관상 → (비밀방) PIN → (공약) 동의 → join_battle.
class BattleJoinScreen extends ConsumerStatefulWidget {
  final String battleId;
  const BattleJoinScreen({super.key, required this.battleId});

  @override
  ConsumerState<BattleJoinScreen> createState() => _BattleJoinScreenState();
}

class _BattleJoinScreenState extends ConsumerState<BattleJoinScreen> {
  final _service = BattleService.instance;
  final _pinCtrl = TextEditingController();
  Battle? _battle;
  List<BattleRosterEntry> _roster = const [];
  int _playerCount = 0;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final battle = await _service.fetchBattle(widget.battleId);
    final roster =
        battle == null ? null : await _service.fetchRoster(widget.battleId);
    if (!mounted) return;
    // 이미 참가한 방이면 바로 로비/결과로.
    final myUid = _service.myUid;
    if (battle != null &&
        roster != null &&
        myUid != null &&
        roster.any((r) => r.userId == myUid)) {
      _goInside(battle);
      return;
    }
    setState(() {
      _battle = battle;
      _roster = roster ?? const [];
      _playerCount = roster?.length ?? 0;
      _loading = false;
    });
  }

  /// 이성방 — 성별 남은 자리 수 (roster gender 카운트 기준, 0 미만 표시 방지).
  int _remaining(String gender) {
    final per = _battle!.maxPlayers ~/ 2;
    final count = _roster.where((r) => r.gender == gender).length;
    return (per - count).clamp(0, per);
  }

  void _goInside(Battle battle) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => battle.isRecruiting
          ? TeamLobbyScreen(battleId: widget.battleId)
          : TeamRevealScreen(battleId: widget.battleId),
    ));
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
      if (mounted) _goInside(battle);
    } catch (e) {
      final err = mapBattleError(e);
      if (err == BattleJoinError.alreadyJoined) {
        if (mounted) _goInside(battle);
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

  @override
  Widget build(BuildContext context) {
    final battle = _battle;
    return Scaffold(
      appBar: AppBar(title: const Text('케미 배틀')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : battle == null
                ? Center(
                    child: Text('존재하지 않는 방입니다', style: AppText.body))
                : !battle.isRecruiting
                    ? _closedBody(battle)
                    : _joinBody(battle),
      ),
    );
  }

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
                onPressed: () => _goInside(battle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _joinBody(Battle battle) {
    final canJoin = battle.isPublic || _pinCtrl.text.trim().length == 4;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(battle.title, style: AppText.display)),
            const SizedBox(width: AppSpacing.sm),
            AgeRangePill(label: battle.ageRangeLabel),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('$_playerCount / ${battle.maxPlayers} 명', style: AppText.body),
        if (battle.roomKind == BattleRoomKind.match) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('남자 ${_remaining('male')}자리 남음', style: AppText.caption),
          Text('여자 ${_remaining('female')}자리 남음', style: AppText.caption),
        ],
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
}
