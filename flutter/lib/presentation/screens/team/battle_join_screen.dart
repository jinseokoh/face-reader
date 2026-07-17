import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../providers/battle_provider.dart';
import '../../providers/history_provider.dart';
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
  int _playerCount = 0;
  bool _agreed = false;
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
      _playerCount = roster?.length ?? 0;
      _loading = false;
    });
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
    try {
      await _service.joinBattle(
        widget.battleId,
        password: battle.isPublic ? null : _pinCtrl.text.trim(),
      );
      ref.invalidate(myBattlesProvider);
      if (mounted) _goInside(battle);
    } catch (e) {
      final err = mapBattleError(e);
      if (err == BattleJoinError.alreadyJoined) {
        if (mounted) _goInside(battle);
        return;
      }
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: err.labelKo),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : battle == null
              ? Center(
                  child: Text('존재하지 않는 방입니다', style: AppText.body))
              : !battle.isRecruiting
                  ? _closedBody(battle)
                  : _joinBody(battle),
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
    final needsConsent = battle.pledge != null;
    final canJoin = (!needsConsent || _agreed) &&
        (battle.isPublic || _pinCtrl.text.trim().length == 4);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(battle.title, style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('$_playerCount / ${battle.maxPlayers} 명', style: AppText.body),
        const SizedBox(height: AppSpacing.xs),
        Text(battle.ageRangeLabel, style: AppText.caption),
        if (battle.pledge != null) ...[
          const SizedBox(height: AppSpacing.xl),
          Container(
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
          ),
          const SizedBox(height: AppSpacing.md),
          CheckboxListTile(
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text('공약에 동의하고 참가합니다', style: AppText.caption),
          ),
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
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(
          label: '참가하기',
          busy: _busy,
          onPressed: canJoin && !_busy ? _join : null,
        ),
      ],
    );
  }
}
