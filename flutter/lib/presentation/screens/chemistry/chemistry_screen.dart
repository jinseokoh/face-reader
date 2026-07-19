import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../providers/battle_provider.dart';
import '../../providers/history_provider.dart';
import '../../widgets/age_range_pill.dart';
import '../../widgets/emotion_empty_state.dart';
import '../../widgets/face_scan_pill.dart';
import '../../widgets/login_bottom_sheet.dart';
import '../team/battle_create_page.dart';
import '../team/battle_detail_screen.dart';
import '../team/team_reveal_screen.dart';

/// 케미 탭 = Chemistry Battle 방 목록 브라우저.
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
    final myFace = ref
        .read(historyProvider)
        .where((r) => r.isMyFace)
        .firstOrNull;
    final decade = myFace == null ? null : 10 + myFace.ageGroup.index * 10;
    if (decade != null && decade < 20) {
      if (mounted) _showAgeGateDialog(context);
      return;
    }
    final battle = await showBattleCreatePage(context);
    if (battle == null || !mounted) return;
    ref.invalidate(myBattlesProvider);
    ref.invalidate(publicBattlesProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BattleDetailScreen(battleId: battle.id),
      ),
    );
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => battle.isRecruiting
            ? BattleDetailScreen(battleId: battle.id)
            : TeamRevealScreen(battleId: battle.id),
      ),
    );
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
            '정원이 다 차면 케미 결과표가 자동으로 발표됩니다.\n'
            '결과에서 베스트 케미와 케미 맵이 공개됩니다.\n\n'
            '모집 중인 방은 모두 목록에 보입니다.\n'
            '비밀번호가 있는 방은 비밀번호를 알아야 참가할 수 있습니다.',
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
                  tabs: [
                    Tab(text: '공개 배틀'),
                    Tab(text: '내 배틀'),
                  ],
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
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.textPrimary),
          ),
          child: Text(
            '배틀 만들기',
            style: AppText.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicTab extends ConsumerStatefulWidget {
  const _PublicTab();

  @override
  ConsumerState<_PublicTab> createState() => _PublicTabState();
}

class _PublicTabState extends ConsumerState<_PublicTab> {
  _SortOrder _order = _SortOrder.newest;

  @override
  Widget build(BuildContext context) {
    final battles = ref.watch(publicBattlesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(publicBattlesProvider),
      child: battles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.huge),
              child: Text(
                '목록을 불러오지 못했습니다\n당겨서 새로고침',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                EmotionEmptyState(
                  asset: 'assets/images/emotion-frown.png',
                  message: '모집 중인 공개 배틀이 없습니다',
                ),
              ],
            );
          }
          final sorted = [...list]
            ..sort(
              (a, b) => _order == _SortOrder.newest
                  ? b.createdAt.compareTo(a.createdAt)
                  : a.createdAt.compareTo(b.createdAt),
            );
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: sorted.length + 1,
            itemBuilder: (ctx, i) => i == 0
                ? _ListSelector<_SortOrder>(
                    value: _order,
                    values: _SortOrder.values,
                    labelOf: (o) => o.label,
                    onChanged: (o) => setState(() => _order = o),
                  )
                : _PublicCard(battle: sorted[i - 1]),
          );
        },
      ),
    );
  }
}

class _PublicCard extends StatefulWidget {
  final PublicBattle battle;
  const _PublicCard({required this.battle});

  @override
  State<_PublicCard> createState() => _PublicCardState();
}

class _PublicCardState extends State<_PublicCard> {
  PublicBattle get battle => widget.battle;

  /// 참가 여부 분기는 상세 페이지가 화면 안에서 처리 — 탭은 진입만.
  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BattleDetailScreen(battleId: battle.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: _BattleCardBody(
          title: battle.title,
          ageLabel: battle.ageRangeLabel,
          roomKind: battle.roomKind,
          playerCount: battle.playerCount,
          maxPlayers: battle.maxPlayers,
          validity: '모집중',
          thumbOpen: battle.thumbOpen,
          isPrivate: battle.isPrivate,
        ),
      ),
    );
  }
}

/// 공개 배틀·내 배틀 공용 카드 본문 — 제목+연령 pill / 유형·정원 / 유효 시한.
/// 두 목록의 item 은 이 위젯 하나로 같은 결을 강제한다.
class _BattleCardBody extends StatelessWidget {
  final String title;
  final String ageLabel;
  final BattleRoomKind roomKind;
  final int? playerCount;
  final int maxPlayers;
  final String validity;
  final bool thumbOpen;
  final bool isPrivate;

  /// 내 배틀 전용 — 내가 방장인 방에 '방장' pill (연령 pill 과 동일 레시피).
  final bool isOwner;
  const _BattleCardBody({
    required this.title,
    required this.ageLabel,
    required this.roomKind,
    required this.playerCount,
    required this.maxPlayers,
    required this.validity,
    required this.thumbOpen,
    required this.isPrivate,
    this.isOwner = false,
  });

  @override
  Widget build(BuildContext context) {
    final kind = roomKind == BattleRoomKind.match ? '이성 케미' : '전체 케미';
    final count = playerCount == null
        ? '$maxPlayers 명'
        : '$playerCount / $maxPlayers 명';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: AppText.subTitle)),
            const SizedBox(width: AppSpacing.sm),
            if (isOwner) ...[
              const AgeRangePill(label: '방장'),
              const SizedBox(width: AppSpacing.xs),
            ],
            AgeRangePill(label: ageLabel),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('$kind $count', style: AppText.caption),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                validity,
                style: AppText.caption.copyWith(color: AppColors.textHint),
              ),
            ),
            // 우측 하단 상태 아이콘 — 얼굴 공개 / 비밀방 / 방 유형.
            FaIcon(
              thumbOpen ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash,
              size: 14,
              color: AppColors.textHint,
            ),
            const SizedBox(width: AppSpacing.sm),
            FaIcon(
              isPrivate ? FontAwesomeIcons.lock : FontAwesomeIcons.lockOpen,
              size: 14,
              color: AppColors.textHint,
            ),
            const SizedBox(width: AppSpacing.sm),
            FaIcon(
              roomKind == BattleRoomKind.match
                  ? FontAwesomeIcons.children
                  : FontAwesomeIcons.users,
              size: 14,
              color: AppColors.textHint,
            ),
          ],
        ),
      ],
    );
  }
}

class _MineTab extends ConsumerStatefulWidget {
  final void Function(Battle) onOpen;
  const _MineTab({required this.onOpen});

  @override
  ConsumerState<_MineTab> createState() => _MineTabState();
}

class _MineTabState extends ConsumerState<_MineTab> {
  _MineFilter _filter = _MineFilter.all;

  @override
  Widget build(BuildContext context) {
    final battles = ref.watch(myBattlesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myBattlesProvider),
      child: battles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.huge),
              child: Text(
                '목록을 불러오지 못했습니다\n당겨서 새로고침',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                EmotionEmptyState(
                  asset: 'assets/images/emotion-laugh.png',
                  message: '참가 중인 배틀이 없습니다',
                ),
              ],
            );
          }
          final filtered = [
            for (final b in list)
              if (switch (_filter) {
                _MineFilter.all => true,
                _MineFilter.recruiting => b.status == BattleStatus.recruiting,
                _MineFilter.closed => b.status != BattleStatus.recruiting,
              })
                b,
          ];
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: filtered.length + 1,
            itemBuilder: (ctx, i) => i == 0
                ? _ListSelector<_MineFilter>(
                    value: _filter,
                    values: _MineFilter.values,
                    labelOf: (f) => f.label,
                    onChanged: (f) => setState(() => _filter = f),
                  )
                : _MineCard(battle: filtered[i - 1], onOpen: widget.onOpen),
          );
        },
      ),
    );
  }
}

class _MineCard extends ConsumerWidget {
  final Battle battle;
  final void Function(Battle) onOpen;
  const _MineCard({required this.battle, required this.onOpen});

  /// 유효 시한 줄 — 모집 중 = 상태 그대로, 완료 = 30일 purge 시한 (사실 카피).
  String get _validityLabel => switch (battle.status) {
    BattleStatus.recruiting => '모집중',
    BattleStatus.revealing => '결과 공개 중',
    BattleStatus.completed =>
      battle.closedAt == null ? '완료' : _resultValidLabel(battle.closedAt!),
    BattleStatus.expired => '인원 미달로 종료',
  };

  static String _resultValidLabel(DateTime closedAt) {
    final d = closedAt.toLocal().add(const Duration(days: 30));
    return '${d.month}월 ${d.day}일까지 결과 유효';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        child: _BattleCardBody(
          title: battle.title,
          ageLabel: battle.ageRangeLabel,
          roomKind: battle.roomKind,
          playerCount: battle.playerCount,
          maxPlayers: battle.maxPlayers,
          validity: _validityLabel,
          thumbOpen: battle.thumbOpen,
          isPrivate: !battle.isPublic,
          isOwner:
              battle.ownerId != null &&
              battle.ownerId == BattleService.instance.myUid,
        ),
      ),
    );
  }
}

/// 리스트 상단 우측 selector — 관상·궁합 탭의 정렬 selector 와 동일 레시피
/// (caption 라벨 + chevronDown popup).
class _ListSelector<T> extends StatelessWidget {
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  const _ListSelector({
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        PopupMenuButton<T>(
          tooltip: '필터',
          initialValue: value,
          padding: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          onSelected: onChanged,
          itemBuilder: (ctx) => [
            for (final v in values)
              PopupMenuItem<T>(
                value: v,
                child: Text(labelOf(v), style: AppText.body),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  labelOf(value),
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                ),
                const SizedBox(width: AppSpacing.sm),
                const FaIcon(
                  FontAwesomeIcons.chevronDown,
                  size: 12,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _SortOrder {
  newest('최신순'),
  oldest('오래된순');

  final String label;
  const _SortOrder(this.label);
}

enum _MineFilter {
  all('전체'),
  recruiting('모집중'),
  closed('모집완료');

  final String label;
  const _MineFilter(this.label);
}
