import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../providers/battle_provider.dart';
import '../../providers/history_provider.dart';
import '../../widgets/emotion_empty_state.dart';
import '../../widgets/face_scan_pill.dart';
import '../../widgets/login_bottom_sheet.dart';
import '../team/battle_create_page.dart';
import '../team/battle_join_screen.dart';
import '../team/team_lobby_screen.dart';
import '../team/team_reveal_screen.dart';

/// 케미 탭 = Chemistry Battle 로비 브라우저.
/// 내부 2탭: 공개 배틀(목록에서 발견·참가) / 내 배틀(진행·완료).
class ChemistryScreen extends ConsumerStatefulWidget {
  const ChemistryScreen({super.key});

  @override
  ConsumerState<ChemistryScreen> createState() => _ChemistryScreenState();
}

class _ChemistryScreenState extends ConsumerState<ChemistryScreen> {
  Future<void> _create() async {
    // 로그인 게이트 — 비로그인 owner_id null 이면 RLS 거부. login_bottom_sheet 패턴.
    if (!BattleService.instance.isLoggedIn) {
      final ok = await showLoginBottomSheet(context, ref);
      if (!ok || !mounted) return;
    }
    // 10대 차단 — UX §A.0. 연령 하한 20 이 스텝 중간이 아니라 문 앞에서 걸려야
    // 제목까지 고른 뒤 버려지는 낭비가 생기지 않는다.
    final myFace = ref.read(historyProvider).where((r) => r.isMyFace).firstOrNull;
    final decade = myFace == null ? null : 10 + myFace.ageGroup.index * 10;
    if (decade != null && decade < 20) {
      if (mounted) _showAgeGateDialog(context);
      return;
    }
    final battle = await showBattleCreatePage(context);
    if (battle == null || !mounted) return;
    ref.invalidate(myBattlesProvider);
    ref.invalidate(publicBattlesProvider);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TeamLobbyScreen(battleId: battle.id),
    ));
  }

  void _showAgeGateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('방 만들기 사용불가', style: AppText.modalTitle),
        content: const Text(
          '케미 배틀 방 만들기는 20세 이상부터 사용할 수 있습니다. '
          '내 관상 분석의 나이대가 10대로 확인되어 지금은 만들 수 없습니다.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인', style: AppText.subTitle),
          ),
        ],
      ),
    );
  }

  void _openMine(Battle battle) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => battle.isRecruiting
          ? TeamLobbyScreen(battleId: battle.id)
          : TeamRevealScreen(battleId: battle.id),
    ));
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('케미 배틀', style: AppText.modalTitle),
        content: const SingleChildScrollView(
          child: Text(
            '방을 만들면 참가자들이 각자 들어옵니다.\n'
            '정원이 다 차면 배틀이 자동으로 시작됩니다.\n'
            '결과에서 베스트 케미와 케미 맵이 공개됩니다.\n\n'
            '공개방은 목록에서 누구나 참가할 수 있고\n'
            '비밀방은 비밀번호를 아는 사람만 참가합니다.',
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

  @override
  Widget build(BuildContext context) {
    final hasMyFace = ref.watch(historyProvider).any((r) => r.isMyFace);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('케미'),
          actions: [
            if (!hasMyFace)
              const FaceScanPill()
            else
              _CreatePill(onTap: _create),
            IconButton(
              icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 20),
              tooltip: '케미 배틀에 대하여',
              onPressed: () => _showInfoDialog(context),
            ),
          ],
          // 내부 탭은 내 관상 등록 후에만 노출 — 궁합·관상 탭과 동일 규칙.
          bottom: hasMyFace
              ? const TabBar(
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textHint,
                  indicatorColor: AppColors.textPrimary,
                  tabs: [Tab(text: '공개 배틀'), Tab(text: '내 배틀')],
                )
              : null,
        ),
        body: !hasMyFace
            ? const EmotionEmptyState(
                asset: 'assets/images/emotion-shrug.png',
                message: '내 관상을 등록하면 케미 배틀에 참가할 수 있습니다',
              )
            : TabBarView(
                children: [
                  const _PublicTab(),
                  _MineTab(onOpen: _openMine),
                ],
              ),
      ),
    );
  }
}

/// AppBar 우측 pill — 기존 outlined stadium 레시피 (케미 그룹 시작 자리 승계).
class _CreatePill extends StatelessWidget {
  final VoidCallback onTap;
  const _CreatePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.textPrimary),
          ),
          child: Text(
            '배틀 만들기',
            style: AppText.caption.copyWith(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _PublicTab extends ConsumerWidget {
  const _PublicTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battles = ref.watch(publicBattlesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(publicBattlesProvider),
      child: battles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.huge),
            child: Text('목록을 불러오지 못했습니다\n당겨서 새로고침',
                style: AppText.caption, textAlign: TextAlign.center),
          ),
        ]),
        data: (list) => list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                EmotionEmptyState(
                  asset: 'assets/images/emotion-frown.png',
                  message: '모집 중인 공개 배틀이 없습니다',
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: list.length,
                itemBuilder: (ctx, i) => _PublicCard(battle: list[i]),
              ),
      ),
    );
  }
}

class _PublicCard extends StatelessWidget {
  final PublicBattle battle;
  const _PublicCard({required this.battle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BattleJoinScreen(battleId: battle.id),
      )),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(battle.title, style: AppText.subTitle),
            const SizedBox(height: AppSpacing.xs),
            Text('${battle.playerCount} / ${battle.maxPlayers} 명',
                style: AppText.caption),
            Text(battle.ageRangeLabel,
                style: AppText.caption.copyWith(color: AppColors.textHint)),
          ],
        ),
      ),
    );
  }
}

class _MineTab extends ConsumerWidget {
  final void Function(Battle) onOpen;
  const _MineTab({required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battles = ref.watch(myBattlesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myBattlesProvider),
      child: battles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.huge),
            child: Text('목록을 불러오지 못했습니다\n당겨서 새로고침',
                style: AppText.caption, textAlign: TextAlign.center),
          ),
        ]),
        data: (list) => list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                EmotionEmptyState(
                  asset: 'assets/images/emotion-laugh.png',
                  message: '참가 중인 배틀이 없습니다',
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: list.length,
                itemBuilder: (ctx, i) =>
                    _MineCard(battle: list[i], onOpen: onOpen),
              ),
      ),
    );
  }
}

class _MineCard extends ConsumerWidget {
  final Battle battle;
  final void Function(Battle) onOpen;
  const _MineCard({required this.battle, required this.onOpen});

  String get _statusLabel => switch (battle.status) {
        BattleStatus.recruiting => '모집 중',
        BattleStatus.revealing => '결과 공개 중',
        BattleStatus.completed => '완료',
        BattleStatus.expired => '종료',
      };

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
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
            child: Text('취소', style: AppText.body.copyWith(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('삭제', style: AppText.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await BattleService.instance.deleteBattle(battle.id);
    ref.invalidate(myBattlesProvider);
    ref.invalidate(publicBattlesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = battle.ownerId == BattleService.instance.myUid;
    return InkWell(
      onTap: battle.status == BattleStatus.expired
          ? null
          : () => onOpen(battle),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(battle.title, style: AppText.subTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_statusLabel, style: AppText.caption),
                ],
              ),
            ),
            if (isOwner && battle.isRecruiting)
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.trashCan,
                    size: 16, color: AppColors.textHint),
                onPressed: () => _delete(context, ref),
              ),
          ],
        ),
      ),
    );
  }
}
