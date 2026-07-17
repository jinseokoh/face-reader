import 'package:facely/core/theme.dart';
import 'package:facely/data/services/battle_service.dart';
import 'package:facely/domain/models/battle.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

/// 방 생성 스텝: 이름 → 인원(4~12) → 공개/비밀(+PIN) → 연령대 → 공약(선택)
/// → [배틀 만들기] = createBattle + joinBattle(셀프 조인) 후 Battle 반환.
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

enum _Step { name, count, access, age, pledge }

const _kPledgePresets = ['🎬 영화', '☕ 커피', '🍜 밥 한 끼', '🎤 노래방'];

// battle.dart 의 Battle.ageRangeLabel 표기 규칙과 동일 포맷(로컬 복제).
String _ageSliderLabel(int start, int end) =>
    start == end ? '$start대' : '$start~${end + 9}세';

class _BattleCreatePage extends ConsumerStatefulWidget {
  const _BattleCreatePage();

  @override
  ConsumerState<_BattleCreatePage> createState() => _BattleCreatePageState();
}

class _BattleCreatePageState extends ConsumerState<_BattleCreatePage> {
  _Step _step = _Step.name;
  final _titleCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pledgeCtrl = TextEditingController();
  int _maxPlayers = 8;
  bool _isPublic = false;
  int? _ageMin; // null 쌍 = 전연령 (기본값).
  int? _ageMax;
  String? _pledgePreset; // null = 공약 없음, '' = 직접입력 모드
  bool _busy = false;
  int? _ownerAgeDecade; // 방장(나) 연령대 — join_battle 연령 게이트 셀프-배제 방지용.

  @override
  void initState() {
    super.initState();
    for (final r in ref.read(historyProvider)) {
      if (r.isMyFace) {
        _ownerAgeDecade = 10 + r.ageGroup.index * 10;
        break;
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _pinCtrl.dispose();
    _pledgeCtrl.dispose();
    super.dispose();
  }

  String? get _pledgeValue {
    if (_pledgePreset == null) return null;
    final text =
        _pledgePreset!.isEmpty ? _pledgeCtrl.text.trim() : _pledgePreset!;
    return text.isEmpty ? null : text;
  }

  // 공개방 + 공약 → 성인 연령대 강제 (서버 CHECK 와 동일 규칙의 UI 게이트).
  bool get _pledgeAllowed => !_isPublic || (_ageMin != null && _ageMin! >= 20);

  // 방장은 createBattle 직후 셀프 조인하며 join_battle 도 연령 게이트를
  // 적용한다 — 방장 본인 연령대를 배제하는 범위를 고르면 고아 방이 생기므로
  // 그런 범위는 '다음' 버튼을 막는다. 전연령 또는 연령대 모를 땐 게이트 없음.
  bool get _ageRangeValid {
    if (_ageMin == null) return true;
    final decade = _ownerAgeDecade;
    if (decade == null) return true;
    return decade >= _ageMin! && decade <= _ageMax!;
  }

  bool get _stepValid => switch (_step) {
        _Step.name => _titleCtrl.text.trim().isNotEmpty,
        _Step.count => true,
        _Step.access => _isPublic || _pinCtrl.text.trim().length == 4,
        _Step.age => _ageRangeValid,
        _Step.pledge => _pledgeValue == null || _pledgeAllowed,
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
        title: _titleCtrl.text.trim(),
        isPublic: _isPublic,
        password: _isPublic ? null : _pinCtrl.text.trim(),
        maxPlayers: _maxPlayers,
        ageMin: _ageMin,
        ageMax: _ageMax,
        roomKind: BattleRoomKind.all,
        thumbOpen: false,
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
    if (_step == _Step.pledge) {
      _create();
      return;
    }
    setState(() => _step = _Step.values[_step.index + 1]);
  }

  void _back() {
    if (_step == _Step.name) {
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
              label: _step == _Step.pledge ? '배틀 만들기' : '다음',
              busy: _busy,
              onPressed: _stepValid && !_busy ? _next : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() => switch (_step) {
        _Step.name => _nameStep(),
        _Step.count => _countStep(),
        _Step.access => _accessStep(),
        _Step.age => _ageStep(),
        _Step.pledge => _pledgeStep(),
      };

  Widget _nameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('배틀 방 이름', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('방 목록과 초대장에 그대로 보입니다', style: AppText.caption),
        const SizedBox(height: AppSpacing.xxl),
        TextField(
          controller: _titleCtrl,
          autofocus: true,
          maxLength: 24,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: '예: 우리 팀 케미 배틀'),
        ),
      ],
    );
  }

  Widget _countStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('참가 인원', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('정원이 다 차면 배틀이 자동으로 시작됩니다', style: AppText.caption),
        const SizedBox(height: AppSpacing.xxl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _maxPlayers > 4
                  ? () => setState(() => _maxPlayers--)
                  : null,
              icon: const FaIcon(FontAwesomeIcons.minus, size: 18),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Text('$_maxPlayers명', style: AppText.display),
            ),
            IconButton(
              onPressed: _maxPlayers < 12
                  ? () => setState(() => _maxPlayers++)
                  : null,
              icon: const FaIcon(FontAwesomeIcons.plus, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  Widget _accessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('공개 방식', style: AppText.display),
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
      ],
    );
  }

  Widget _ageStep() {
    final displayMin = _ageMin ?? 10;
    final displayMax = _ageMax ?? 70;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('참가 연령대', style: AppText.display),
        const SizedBox(height: AppSpacing.xxl),
        _chip(
          label: '전연령',
          selected: _ageMin == null,
          onTap: () => setState(() {
            _ageMin = null;
            _ageMax = null;
          }),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(_ageSliderLabel(displayMin, displayMax), style: AppText.body),
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
            min: 10,
            max: 70,
            divisions: 6,
            labels: RangeLabels('$displayMin대', '$displayMax대'),
            values: RangeValues(displayMin.toDouble(), displayMax.toDouble()),
            onChanged: (values) => setState(() {
              _ageMin = values.start.round();
              _ageMax = values.end.round();
            }),
          ),
        ),
        if (!_ageRangeValid) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '방장인 나도 참가하므로 내 연령대가 포함되어야 합니다',
            style: AppText.caption.copyWith(color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  Widget _pledgeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('공약 (선택)', style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text('베스트 케미로 뽑힌 두 사람이 실행합니다', style: AppText.caption),
        if (!_pledgeAllowed) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '공개방 공약은 20세 이상 연령대 설정이 필요합니다',
            style: AppText.caption.copyWith(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _chip(
              label: '공약 없음',
              selected: _pledgePreset == null,
              onTap: () => setState(() => _pledgePreset = null),
            ),
            for (final preset in _kPledgePresets)
              _chip(
                label: preset,
                selected: _pledgePreset == preset,
                onTap: _pledgeAllowed
                    ? () => setState(() => _pledgePreset = preset)
                    : null,
              ),
            _chip(
              label: '직접입력',
              selected: _pledgePreset == '',
              onTap:
                  _pledgeAllowed ? () => setState(() => _pledgePreset = '') : null,
            ),
          ],
        ),
        if (_pledgePreset == '') ...[
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _pledgeCtrl,
            maxLength: 40,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: '공약 내용'),
          ),
        ],
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
