import 'package:facely/core/theme.dart';
import 'package:facely/data/services/battle_service.dart';
import 'package:facely/domain/models/battle.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/screens/team/battle_title_catalog.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

/// 방 생성 스텝 (rev2 — UX §A/§C): ①방 유형 → ②방 제목(카테고리→프리셋,
/// 기타 = 자유 입력) → ③인원(6/8/10/12) → ④연령대(방장 인접 구간 RangeSlider)
/// → ⑤공개 설정(공개/비밀) → ⑥모집중 참가자 얼굴 공개. [배틀 만들기] = createBattle
/// + joinBattle(셀프 조인) 후 Battle 반환, 조인 실패 시 방 롤백.
Future<Battle?> showBattleCreatePage(BuildContext context) {
  return showModalBottomSheet<Battle>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _BattleCreatePage(),
  );
}

// battle.dart 의 Battle.ageRangeLabel 표기 규칙과 동일 포맷(로컬 복제).
String _ageSliderLabel(int start, int end) =>
    start == end ? '$start대' : '$start대~$end대';

class _BattleCreatePage extends ConsumerStatefulWidget {
  const _BattleCreatePage();

  @override
  ConsumerState<_BattleCreatePage> createState() => _BattleCreatePageState();
}

class _BattleCreatePageState extends ConsumerState<_BattleCreatePage>
    with SingleTickerProviderStateMixin {
  _Step _step = _Step.roomKind;
  final _pinCtrl = TextEditingController();
  final _customTitleCtrl = TextEditingController();

  /// ② 제목 리스트 등장 연출 — 카테고리를 고를 때마다 위→아래로 순차 등장.
  late final AnimationController _listAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  BattleRoomKind? _roomKind;
  BattleTitleCategory? _categorySel;
  String? _selectedTitle;
  int _maxPlayers = 8;
  int? _ageMin;
  int? _ageMax;
  bool _isPublic = false;
  bool _thumbOpen = false;
  bool _busy = false;
  int? _ownerAgeDecade; // 방장(나) 연령대 — ④ 슬라이더 bounds 산출용.

  BattleTitleCategory get _activeCategory {
    final visible = _visibleCategories;
    final sel = _categorySel;
    if (sel != null && visible.contains(sel)) return sel;
    return visible.first;
  }

  bool get _stepValid => switch (_step) {
    _Step.roomKind => _roomKind != null,
    _Step.title => _selectedTitle != null,
    _Step.count => true,
    _Step.age => true,
    _Step.visibility => _isPublic || _pinCtrl.text.trim().length == 4,
    _Step.thumb => true,
  };

  // ② 방 제목 — 방 유형에 허용되지 않는 카테고리/제목은 숨긴다(disabled 나열 아님).
  // 자유 입력(기타)은 방 유형과 무관하게 항상 보인다.
  List<BattleTitleCategory> get _visibleCategories => kBattleTitleCatalog
      .where(
        (c) =>
            c.isCustom ||
            c.titles.any((t) => t.allowedKinds.contains(_roomKind)),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return FractionallySizedBox(
      // 키보드가 올라오면 시트를 허용 최대 높이로 — 0.92 고정인 채 안쪽
      // padding 만 키우면 내용 공간이 키보드만큼 줄어 ② 자유 입력(기타)에서
      // 세로 overflow 가 난다 (test/battle_create_overflow_test.dart).
      heightFactor: keyboard > 0 ? 1.0 : 0.92,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom:
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).viewPadding.bottom +
              AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                IconButton(
                  onPressed: _busy ? null : _back,
                  icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 18),
                ),
                const Spacer(),
                Text(
                  '${_step.index + 1} / ${_Step.values.length}',
                  style: AppText.hint,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            // ② 제목 스텝은 자체 스크롤 (헤더·카테고리 chip 고정) — 나머지
            // 스텝은 통짜 스크롤.
            Expanded(
              child: _step == _Step.title
                  ? _titleStep()
                  : SingleChildScrollView(child: _stepBody()),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: _step == _Step.thumb ? '배틀 만들기' : '다음',
              busy: _busy,
              onPressed: _stepValid && !_busy ? _next : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _customTitleCtrl.dispose();
    _listAnim.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    for (final r in ref.read(historyProvider)) {
      if (r.isMyFace) {
        _ownerAgeDecade = 10 + r.ageGroup.index * 10;
        break;
      }
    }
    // 진입 게이트(chemistry_screen._create)가 10대를 이미 걸러내므로 여기서는
    // 항상 20 이상이 온다 — decade 미상(방어적 fallback)만 20 으로 둔다.
    // 기본값 = 방장 인접 전체 범위 [decade-10, decade+10] (20~70 클램프).
    final decade = _ownerAgeDecade ?? 20;
    _ageMin = (decade - 10) < 20 ? 20 : decade - 10;
    _ageMax = (decade + 10) > 70 ? 70 : decade + 10;
  }

  Widget _ageStep() {
    final decade = _ownerAgeDecade ?? 20;
    final lo = (decade - 10) < 20 ? 20 : decade - 10;
    final hi = (decade + 10) > 70 ? 70 : decade + 10;
    final divisions = (hi - lo) ~/ 10;
    final min = _ageMin!;
    final max = _ageMax!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('참가 연령대', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('방장의 나이대가 포함된 범위만 고를 수 있습니다', style: AppText.caption),
        const SizedBox(height: AppSpacing.xxl),
        Text(_ageSliderLabel(min, max), style: AppText.body),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.textPrimary,
            thumbColor: AppColors.textPrimary,
            inactiveTrackColor: AppColors.border,
            overlayColor: Colors.transparent,
            // 두 knob 이 같은 눈금에 겹치도록 허용 — 기본 8px 간격 제한이
            // "30대만" 같은 단일 나이대(min == max) 선택을 막는다.
            minThumbSeparation: 0,
            showValueIndicator: ShowValueIndicator.onDrag,
            valueIndicatorColor: AppColors.textPrimary,
            valueIndicatorTextStyle: AppText.caption.copyWith(
              color: Colors.white,
            ),
          ),
          child: RangeSlider(
            min: lo.toDouble(),
            max: hi.toDouble(),
            divisions: divisions < 1 ? 1 : divisions,
            labels: RangeLabels('$min대', '$max대'),
            values: RangeValues(min.toDouble(), max.toDouble()),
            // 방장 decade 는 항상 범위에 포함 — 넘어가려는 thumb 만 되돌린다.
            onChanged: (values) => setState(() {
              final start = values.start.round();
              final end = values.end.round();
              _ageMin = start > decade ? decade : start;
              _ageMax = end < decade ? decade : end;
            }),
          ),
        ),
      ],
    );
  }

  void _back() {
    if (_step == _Step.roomKind) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step = _Step.values[_step.index - 1]);
    if (_step == _Step.title) _listAnim.forward(from: 0);
  }

  /// ② 제목 리스트 등장 연출 — [index] 가 클수록 늦게 fade + 아래로
  /// 슬라이드하며 나타나 위→아래 순차 등장이 된다. [_listAnim] 재생마다 반복.
  Widget _cascadeItem({
    required int index,
    required int total,
    required Widget child,
  }) {
    final start = total <= 1 ? 0.0 : index * 0.55 / (total - 1);
    final anim = CurvedAnimation(
      parent: _listAnim,
      curve: Interval(
        start,
        (start + 0.45).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.25),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  /// 단일톤 chip — Material `ChoiceChip` 의 배경/폰트 크기 분리를 피하고
  /// 선택 상태를 border + 굵기 한 축으로만 표현한다(§0 chip/pill 단일톤 규칙).
  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: !enabled
                ? AppColors.textHint
                : (selected ? AppColors.textPrimary : AppColors.textSecondary),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _choiceTile({
    required bool selected,
    required String title,
    required String caption,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.subTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(caption, style: AppText.caption),
          ],
        ),
      ),
    );
  }

  Widget _countStep() {
    final half = _maxPlayers ~/ 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('몇 명이 참가하나요?', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('정원이 다 차면 케미 결과표가 자동으로 발표됩니다', style: AppText.caption),
        const SizedBox(height: AppSpacing.xxl),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final n in [6, 8, 10, 12])
              _chip(
                label: '$n명',
                selected: _maxPlayers == n,
                onTap: () => setState(() => _maxPlayers = n),
              ),
          ],
        ),
        if (_roomKind == BattleRoomKind.match) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('남자 $half명, 여자 $half명', style: AppText.body),
        ],
      ],
    );
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    final service = BattleService.instance;
    Battle? battle;
    final myFace = ref
        .read(historyProvider)
        .where((r) => r.isMyFace)
        .firstOrNull;
    if (myFace == null || !await service.ensureMyFaceOnServer(myFace)) {
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
      battle = await service.createBattle(
        title: _selectedTitle!,
        isPublic: _isPublic,
        password: _isPublic ? null : _pinCtrl.text.trim(),
        maxPlayers: _maxPlayers,
        ageMin: _ageMin,
        ageMax: _ageMax,
        roomKind: _roomKind!,
        thumbOpen: _thumbOpen,
      );
      await service.joinBattle(
        battle.id,
        password: _isPublic ? null : _pinCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(battle);
    } catch (e) {
      debugPrint('createBattle failed: $e');
      // createBattle 은 성공했는데 셀프 조인이 실패하면(예: 연령 게이트) 방장
      // 없는 고아 방이 남는다 — 에러를 보여주기 전에 방부터 지운다.
      if (battle != null) {
        try {
          await service.deleteBattle(battle.id);
        } catch (_) {}
      }
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: mapBattleError(e).labelKo),
        );
        setState(() => _busy = false);
      }
    }
  }

  void _next() {
    if (_step == _Step.thumb) {
      _create();
      return;
    }
    setState(() => _step = _Step.values[_step.index + 1]);
    if (_step == _Step.title) _listAnim.forward(from: 0);
  }

  Widget _roomKindStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('어떤 방을 만들까요?', style: AppText.display),
        const SizedBox(height: AppSpacing.xxl),
        _choiceTile(
          selected: _roomKind == BattleRoomKind.match,
          title: '이성 케미 매칭방',
          caption: '남녀 반반으로 고정되고 결과는 남녀 쌍만 계산합니다',
          onTap: () => setState(() {
            _roomKind = BattleRoomKind.match;
            _categorySel = null;
            _selectedTitle = null;
          }),
        ),
        if (_roomKind == BattleRoomKind.match) ...[
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              '베스트 매칭이 되면 두 사람에게 서로의 사진이 공개되고 채팅을 제안할 수 있습니다',
              style: AppText.caption.copyWith(color: AppColors.textHint),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _choiceTile(
          selected: _roomKind == BattleRoomKind.all,
          title: '전체 케미 배틀방',
          caption: '성별 구분 없이 모든 전체 쌍의 케미를 계산합니다',
          onTap: () => setState(() {
            _roomKind = BattleRoomKind.all;
            _categorySel = null;
            _selectedTitle = null;
          }),
        ),
      ],
    );
  }

  Widget _stepBody() => switch (_step) {
    _Step.roomKind => _roomKindStep(),
    _Step.title => _titleStep(),
    _Step.count => _countStep(),
    _Step.age => _ageStep(),
    _Step.visibility => _visibilityStep(),
    _Step.thumb => _thumbStep(),
  };

  Widget _thumbStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('모집중 참가자 얼굴 공개', style: AppText.display),
        const SizedBox(height: AppSpacing.xxl),
        _choiceTile(
          selected: _thumbOpen,
          title: '얼굴 공개',
          caption: '모집 중 참가자의 얼굴 썸네일이 보입니다',
          onTap: () => setState(() => _thumbOpen = true),
        ),
        const SizedBox(height: AppSpacing.md),
        _choiceTile(
          selected: !_thumbOpen,
          title: '얼굴 비공개',
          caption: '얼굴 대신 성별 기본 아이콘이 보입니다',
          onTap: () => setState(() => _thumbOpen = false),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '최종 결과표에는 얼굴이 모두에게 공개됩니다. 이 설정은 모집중에 공개할지 여부를 결정합니다',
          style: AppText.caption.copyWith(color: AppColors.textHint),
        ),
      ],
    );
  }

  Widget _titleStep() {
    final category = _activeCategory;
    final categories = _visibleCategories;
    final titles = category.isCustom
        ? const <BattleTitlePreset>[]
        : category.titles
              .where((t) => t.allowedKinds.contains(_roomKind))
              .toList();
    final header = [
      Text('방 제목을 고르세요', style: AppText.display),
      const SizedBox(height: AppSpacing.sm),
      Text('방 목록과 초대장에 보입니다', style: AppText.caption),
      const SizedBox(height: AppSpacing.xxl),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final c in categories) ...[
              _chip(
                label: c.name,
                selected: c == category,
                onTap: () {
                  setState(() {
                    _categorySel = c;
                    final custom = _customTitleCtrl.text.trim();
                    _selectedTitle = c.isCustom && custom.isNotEmpty
                        ? custom
                        : null;
                  });
                  _listAnim.forward(from: 0);
                },
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
    ];
    // 기타(자유 입력)는 스크롤할 프리셋 리스트가 없으므로 헤더까지 통째로
    // 스크롤 — 키보드가 세로 공간을 좁혀도 overflow 하지 않는다
    // (test/battle_create_overflow_test.dart).
    if (category.isCustom) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...header,
            _cascadeItem(
              index: 0,
              total: 1,
              child: TextField(
                controller: _customTitleCtrl,
                maxLength: 30,
                style: AppText.body.copyWith(color: AppColors.textPrimary),
                onChanged: (v) => setState(() {
                  final t = v.trim();
                  _selectedTitle = t.isEmpty ? null : t;
                }),
                decoration: const InputDecoration(hintText: '방 제목을 직접 입력하세요'),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...header,
        // 제목 리스트만 스크롤 — 위의 타이틀·카피·카테고리 chip 은 항상 고정.
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, t) in titles.indexed) ...[
                  _cascadeItem(
                    index: i,
                    total: titles.length,
                    child: _titleTile(
                      selected: _selectedTitle == t.title,
                      title: t.title,
                      onTap: () => setState(() => _selectedTitle = t.title),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// ② 제목 리스트 전용 축소형 — surface bg, 제목 한 줄만(caption 없음),
  /// 선택 표현은 border 만(라디오 아이콘 없음, §C.3).
  Widget _titleTile({
    required bool selected,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.border,
          ),
        ),
        child: Text(
          title,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _visibilityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('공개 설정', style: AppText.display),
        const SizedBox(height: AppSpacing.xxl),
        _choiceTile(
          selected: _isPublic,
          title: '공개방',
          caption: '비밀번호 없이 누구나 참가할 수 있습니다',
          onTap: () => setState(() => _isPublic = true),
        ),
        const SizedBox(height: AppSpacing.md),
        _choiceTile(
          selected: !_isPublic,
          title: '비밀방',
          caption: '비밀번호를 아는 사람만 참가할 수 있습니다',
          onTap: () => setState(() => _isPublic = false),
        ),
        if (!_isPublic) ...[
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
      ],
    );
  }
}

enum _Step { roomKind, title, count, age, visibility, thumb }
