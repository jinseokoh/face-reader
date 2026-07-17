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

/// 방 생성 스텝 (rev2 — UX §A/§C): ①방 유형 → ②방 제목(카테고리→프리셋) →
/// ③인원(6/8/10/12) → ④연령대(방장 인접 구간 RangeSlider) → ⑤공개 설정
/// (공개/비밀 + 썸네일 공개). [배틀 만들기] = createBattle + joinBattle(셀프
/// 조인) 후 Battle 반환, 조인 실패 시 방 롤백.
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

enum _Step { roomKind, title, count, age, visibility }

// battle.dart 의 Battle.ageRangeLabel 표기 규칙과 동일 포맷(로컬 복제).
String _ageSliderLabel(int start, int end) =>
    start == end ? '$start대' : '$start~${end + 9}세';

class _BattleCreatePage extends ConsumerStatefulWidget {
  const _BattleCreatePage();

  @override
  ConsumerState<_BattleCreatePage> createState() => _BattleCreatePageState();
}

class _BattleCreatePageState extends ConsumerState<_BattleCreatePage> {
  _Step _step = _Step.roomKind;
  final _pinCtrl = TextEditingController();

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
    final decade = _ownerAgeDecade ?? 20;
    final windows = _windowsFor(decade);
    final chosen = windows.length == 1 ? windows.first : windows.last;
    _ageMin = chosen.$1;
    _ageMax = chosen.$2;
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  // ④ 연령대 — 방장 decade 가 포함된, 폭 정확히 10(=2-decade) 인 유효 구간들.
  // 20대/70대는 1개, 그 사이는 2개([D-10,D], [D,D+10]).
  List<(int, int)> _windowsFor(int decade) {
    final list = <(int, int)>[];
    if (decade - 10 >= 20) list.add((decade - 10, decade));
    if (decade + 10 <= 70) list.add((decade, decade + 10));
    return list;
  }

  (int, int) _snapAgeWindow(int start, int end, int decade) {
    final windows = _windowsFor(decade);
    if (windows.length == 1) return windows.first;
    final center = (start + end) / 2;
    final centerA = (windows[0].$1 + windows[0].$2) / 2;
    final centerB = (windows[1].$1 + windows[1].$2) / 2;
    return (center - centerA).abs() <= (center - centerB).abs()
        ? windows[0]
        : windows[1];
  }

  // ② 방 제목 — 방 유형에 허용되지 않는 카테고리/제목은 숨긴다(disabled 나열 아님).
  List<BattleTitleCategory> get _visibleCategories => kBattleTitleCatalog
      .where((c) => c.titles.any((t) => t.allowedKinds.contains(_roomKind)))
      .toList();

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
        _Step.visibility =>
          _isPublic || _pinCtrl.text.trim().length == 4,
      };

  Future<void> _create() async {
    setState(() => _busy = true);
    final service = BattleService.instance;
    Battle? battle;
    final myFace =
        ref.read(historyProvider).where((r) => r.isMyFace).firstOrNull;
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
      await service.joinBattle(battle.id,
          password: _isPublic ? null : _pinCtrl.text.trim());
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
    if (_step == _Step.visibility) {
      _create();
      return;
    }
    setState(() => _step = _Step.values[_step.index + 1]);
  }

  void _back() {
    if (_step == _Step.roomKind) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step = _Step.values[_step.index - 1]);
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom +
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
            Expanded(child: SingleChildScrollView(child: _stepBody())),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: _step == _Step.visibility ? '배틀 만들기' : '다음',
              busy: _busy,
              onPressed: _stepValid && !_busy ? _next : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() => switch (_step) {
        _Step.roomKind => _roomKindStep(),
        _Step.title => _titleStep(),
        _Step.count => _countStep(),
        _Step.age => _ageStep(),
        _Step.visibility => _visibilityStep(),
      };

  Widget _roomKindStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('어떤 방을 만들까요?', style: AppText.display),
        const SizedBox(height: AppSpacing.xxl),
        _choiceTile(
          selected: _roomKind == BattleRoomKind.match,
          title: '이성 케미 매칭방',
          caption: '남녀 자리가 반반으로 고정됩니다. 결과는 남녀 쌍만 계산합니다',
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
          caption: '성별 구분 없이 모든 쌍의 케미를 계산합니다',
          onTap: () => setState(() {
            _roomKind = BattleRoomKind.all;
            _categorySel = null;
            _selectedTitle = null;
          }),
        ),
      ],
    );
  }

  Widget _titleStep() {
    final category = _activeCategory;
    final categories = _visibleCategories;
    final titles =
        category.titles.where((t) => t.allowedKinds.contains(_roomKind));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('방 제목을 고르세요', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('방 목록과 초대장에 그대로 보입니다', style: AppText.caption),
        const SizedBox(height: AppSpacing.xxl),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in categories) ...[
                _chip(
                  label: c.name,
                  selected: c == category,
                  onTap: () => setState(() {
                    _categorySel = c;
                    _selectedTitle = null;
                  }),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final t in titles) ...[
          _titleTile(
            selected: _selectedTitle == t.title,
            title: t.title,
            onTap: () => setState(() => _selectedTitle = t.title),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _countStep() {
    final half = _maxPlayers ~/ 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('몇 명이 참가하나요?', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('정원이 다 차면 배틀이 자동으로 시작됩니다', style: AppText.caption),
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
            showValueIndicator: ShowValueIndicator.onDrag,
            valueIndicatorColor: AppColors.textPrimary,
            valueIndicatorTextStyle:
                AppText.caption.copyWith(color: Colors.white),
          ),
          child: RangeSlider(
            min: lo.toDouble(),
            max: hi.toDouble(),
            divisions: divisions < 1 ? 1 : divisions,
            labels: RangeLabels('$min대', '$max대'),
            values: RangeValues(min.toDouble(), max.toDouble()),
            onChanged: (values) => setState(() {
              _ageMin = values.start.round();
              _ageMax = values.end.round();
            }),
            onChangeEnd: (values) => setState(() {
              final snapped = _snapAgeWindow(
                  values.start.round(), values.end.round(), decade);
              _ageMin = snapped.$1;
              _ageMax = snapped.$2;
            }),
          ),
        ),
      ],
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
          caption: '공개 배틀 목록에서 누구나 참가할 수 있습니다',
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
        const SizedBox(height: AppSpacing.xxl),
        Text('참가자 얼굴 공개', style: AppText.sectionTitle),
        const SizedBox(height: AppSpacing.md),
        _choiceTile(
          selected: _thumbOpen,
          title: '얼굴 공개',
          caption: '로비와 결과에서 참가자의 얼굴 썸네일이 보입니다',
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
          '이 설정과 관계없이 베스트 매칭이 되면 두 사람에게는 서로의 사진이 공개됩니다',
          style: AppText.caption.copyWith(color: AppColors.textHint),
        ),
      ],
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
        child: Text(title, style: AppText.body.copyWith(color: AppColors.textPrimary)),
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
}
