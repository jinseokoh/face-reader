import 'dart:async';

import 'package:facely/core/theme.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/widgets/picker_row.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 교감도 방 생성 풀페이지 — PIVOT A6 채택안 B (2026-06-12 풀페이지 개정).
/// 카메라 캡처와 동일한 바텀 슬라이드 풀페이지 패턴. 상단에 "교감도 모임 훅"
/// 헤드라인(우리 팀/반/모임/조직/회사/부서/좋소/크루/동아리/패밀리 키워드 회전)을 크게 노출하고,
/// 생성은 여전히 모임명 한 줄 1스텝. 반환: 생성된 TeamRoom (취소 시 null).
Future<TeamRoom?> showTeamCreatePage(
  BuildContext context,
  WidgetRef ref, {
  required String ownerReportId,
}) {
  final size = MediaQuery.of(context).size;
  return showModalBottomSheet<TeamRoom>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints.tightFor(
      width: size.width,
      height: size.height,
    ),
    builder: (_) => _TeamCreatePage(ownerReportId: ownerReportId),
  );
}

/// "우리 〔팀〕에서 나랑 케미가 제일 잘 맞는 사람은?" — 키워드만
/// fade+slide 로 교체되는 훅 헤드라인. SongMyung display 토큰.
/// 인원 선택 후엔 꼬리말이 "에서" → " 〔n〕명 중에서" 로 바뀐다.
class _HookHeadline extends StatelessWidget {
  final String word;
  // true 면 회전 없이 [word] 로 고정 — 크로스페이드 없이 즉시 표시.
  final bool locked;
  // 인원 선택 시 non-null — 첫 줄 꼬리말이 " 〔n〕명 중에서" 로 변경.
  final int? memberCount;

  const _HookHeadline({
    required this.word,
    this.locked = false,
    this.memberCount,
  });

  String get _tail => memberCount == null ? '에서' : ' $memberCount명 중에서';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (locked)
          // 고정 단어 — 회전 레이어 없이 한 줄로 (인원 꼬리말 포함, 줄바꿈 허용).
          Text('우리 $word$_tail', style: AppText.display)
        else
          Row(
            children: [
              Text('우리 ', style: AppText.display),
              _RotatingWord(word: word),
              Text(_tail, style: AppText.display),
            ],
          ),
        const SizedBox(height: AppSpacing.xs),
        Text('나랑 케미가 제일', style: AppText.display),
        const SizedBox(height: AppSpacing.xs),
        Text('잘 맞는 사람은?', style: AppText.display),
      ],
    );
  }
}

/// 회전 키워드 — 전환 400ms 동안만 크로스페이드 Stack 을 쓰고, 정지
/// 상태에선 래퍼 없는 평문 [Text] 로 렌더한다. 전환 위젯(opacity/transform
/// 레이어) 안의 텍스트는 글리프 픽셀 스냅이 달라져 옆 글자보다 흐릿하게
/// 보이는 문제가 있어, 화면에 머무는 시간(약 2.1초)에는 일반 텍스트와
/// 동일한 렌더 경로를 보장한다.
class _RotatingWord extends StatefulWidget {
  final String word;

  const _RotatingWord({required this.word});

  @override
  State<_RotatingWord> createState() => _RotatingWordState();
}

class _RotatingWordState extends State<_RotatingWord>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late String _current = widget.word;
  String? _outgoing;

  @override
  Widget build(BuildContext context) {
    final outgoing = _outgoing;
    if (outgoing == null) {
      // 정지 상태 — 평문 렌더 (레이어 0, 옆 글자와 동일 경로).
      return Text(_current, style: AppText.display);
    }
    return Stack(
      alignment: Alignment.bottomLeft,
      children: [
        FadeTransition(
          opacity: ReverseAnimation(_controller),
          child: Text(outgoing, style: AppText.display),
        ),
        FadeTransition(
          opacity: _controller,
          child: Text(_current, style: AppText.display),
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant _RotatingWord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word == widget.word) return;
    _outgoing = _current;
    _current = widget.word;
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _outgoing = null);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _TeamCreatePage extends ConsumerStatefulWidget {
  final String ownerReportId;

  const _TeamCreatePage({required this.ownerReportId});

  @override
  ConsumerState<_TeamCreatePage> createState() => _TeamCreatePageState();
}

class _TeamCreatePageState extends ConsumerState<_TeamCreatePage> {
  // 교감도 모임 훅 — 회전 키워드. "우리 {키워드}에서 나랑 케미가 제일
  // 잘 맞는 사람은?" — 전부 "우리 ○에서" 결합이 자연스러운 단어.
  static const _hookWords = [
    '팀', '반', '모임', '조직', '회사', '부서', '좋소', '크루', '동아리', '패밀리',
  ];
  // 단체 유형 select — 훅 문장 전체가 옵션. 회전 키워드에서 파생해
  // 헤드라인과 select 가 항상 같은 어휘를 쓴다 + 직접입력.
  static final _typeOptions = [
    for (final w in _hookWords) '우리 $w',
    '직접입력',
  ];

  final TextEditingController _controller = TextEditingController();
  // 미선택(null) 이면 placeholder "단체 유형을 선택하세요." 노출.
  String? _selected;
  // 참여 인원 — 미선택(null) 이면 placeholder "참여인원을 선택하세요." 노출.
  int? _memberTarget;

  // 단계 reveal 슬롯 — 'type' → 'members' → 'done'. 각 전환은 2초 fade-out
  // 후 2초 fade-in 으로 순차 진행 (겹치지 않음).
  static const _slotAnim = Duration(seconds: 2);
  String _slot = 'type';
  bool _slotShown = true;
  Timer? _slotTimer;

  Timer? _hookTimer;
  int _hookIndex = 0;
  bool _creating = false;
  bool get _isCustom => _selected == '직접입력';

  /// 훅 문장 옵션을 선택하면 그 키워드로 헤드라인을 고정한다.
  /// 직접입력·미선택이면 null — 회전 유지.
  String? get _lockedWord {
    final sel = _selected;
    if (sel == null || sel == '직접입력') return null;
    final i = _typeOptions.indexOf(sel);
    return (i >= 0 && i < _hookWords.length) ? _hookWords[i] : null;
  }

  /// 직접입력에 입력된 단체명 (공백 제거, 비면 null).
  String? get _customWord {
    final t = _controller.text.trim();
    return t.isEmpty ? null : t;
  }

  /// 헤드라인에 박을 단어 — preset 키워드 / 직접입력 텍스트 / (미정) 회전.
  String get _headlineWord =>
      (_isCustom ? _customWord : _lockedWord) ?? _hookWords[_hookIndex];

  /// 단어가 고정됐는지 — preset 선택 또는 직접입력 텍스트가 있을 때.
  bool get _headlineLocked =>
      _isCustom ? _customWord != null : _lockedWord != null;

  @override
  Widget build(BuildContext context) {
    // 키보드 inset 은 Scaffold(resizeToAvoidBottomInset)가 처리 — 수동
    // viewInsets 가산 금지 (이중 차감으로 RenderFlex overflow).
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const FaIcon(
                FontAwesomeIcons.xmark,
                color: AppColors.textPrimary,
                size: 20,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      // 교감도 모임 훅 — 단체 유형 선택 시 키워드 고정,
                      // 인원 선택 시 꼬리말이 " 〔n〕명 중에서" 로 바뀐다.
                      _HookHeadline(
                        word: _headlineWord,
                        locked: _headlineLocked,
                        memberCount: _memberTarget,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Image.asset(
                        'assets/images/team-chemistry-map.png',
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      // 직접입력 단체명 — 선택 직후부터 계속 노출 (focus 유지).
                      if (_isCustom) ...[
                        _customNameField(),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      // 단계 reveal — 단체 유형 select 가 2초 fade-out 된 뒤
                      // 참여 인원 select 가 2초 fade-in (스르르 순차 전환).
                      AnimatedSlide(
                        duration: _slotAnim,
                        curve: Curves.easeInOut,
                        offset:
                            _slotShown ? Offset.zero : const Offset(0, 0.3),
                        child: AnimatedOpacity(
                          duration: _slotAnim,
                          curve: Curves.easeInOut,
                          opacity: _slotShown ? 1 : 0,
                          child: _slotBox(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 하단 고정 — 인원 선택 전엔 힌트, 선택 완료 시 CTA 가 올라온다.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  AppSpacing.sm,
                  AppSpacing.xxl,
                  AppSpacing.lg,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: _slideFade,
                  child: _bottomAction(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hookTimer?.cancel();
    _slotTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _hookTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted || _lockedWord != null) return;
      setState(() => _hookIndex = (_hookIndex + 1) % _hookWords.length);
    });
  }

  Future<void> _create() async {
    if (_creating) return;
    final selected = _selected;
    if (selected == null) {
      // 미선택이면 선택으로 유도.
      _pickType();
      return;
    }
    final title = _isCustom ? _controller.text.trim() : selected;
    if (title.isEmpty) {
      // 직접입력에서 비어 있으면 입력으로 유도 — 유일한 필수 입력.
      FocusScope.of(context).unfocus();
      return;
    }
    final memberTarget = _memberTarget;
    if (memberTarget == null) {
      // 인원 미선택이면 선택으로 유도.
      FocusScope.of(context).unfocus();
      _pickMembers();
      return;
    }
    setState(() => _creating = true);
    final room = await ref.read(teamsProvider.notifier).create(
          title: title,
          ownerReportId: widget.ownerReportId,
          memberTarget: memberTarget,
        );
    if (!mounted) return;
    Navigator.of(context).pop(room);
  }

  /// 단계 전환 공통 — 아래에서 슬라이드 + 페이드.
  Widget _slideFade(Widget child, Animation<double> anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      );

  /// 현재 슬롯이 보여줄 select 박스.
  Widget _slotBox() {
    switch (_slot) {
      case 'type':
        return PickerRow(
          value: '단체 유형을 선택하세요.',
          placeholder: true,
          onTap: _pickType,
        );
      case 'members':
        return PickerRow(
          value: '참여 인원을 선택하세요.',
          placeholder: true,
          onTap: _pickMembers,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  /// 슬롯 순차 전환 — 현재 박스를 2초 fade-out 한 뒤 [next] 로 교체,
  /// 빈 슬롯이 아니면 다시 2초 fade-in. (겹치지 않는 순차 애니메이션)
  void _advanceSlot(String next) {
    _slotTimer?.cancel();
    setState(() => _slotShown = false); // 현재 박스 fade-out 시작.
    _slotTimer = Timer(_slotAnim, () {
      if (!mounted) return;
      setState(() => _slot = next); // 교체 (아직 숨김 상태).
      if (next == 'done') return; // 빈 슬롯이면 그대로 숨김 유지.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _slotShown = true); // fade-in.
      });
    });
  }

  /// 하단 액션: 인원 선택 전엔 힌트, 슬롯이 done 에 도달하면 CTA.
  Widget _bottomAction() {
    if (_slot == 'done') {
      return PrimaryButton(
        key: const ValueKey('cta'),
        label: '방 만들기',
        busy: _creating,
        onPressed: _create,
      );
    }
    if (_slot == 'members') {
      return Text(
        '최소 3명부터 최대 12명까지 참여 가능합니다.',
        key: const ValueKey('hint'),
        style: AppText.hint,
        textAlign: TextAlign.center,
      );
    }
    return const SizedBox.shrink(key: ValueKey('empty'));
  }

  /// 직접입력 단체명 필드 — 입력 시 헤드라인 단어가 따라 바뀐다.
  Widget _customNameField() {
    return TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 20,
      style: AppText.body.copyWith(color: AppColors.textPrimary),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: '단체명',
        hintStyle: AppText.body.copyWith(color: AppColors.textHint),
        counterText: '',
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.textPrimary),
        ),
      ),
      onSubmitted: (_) => _create(),
    );
  }

  Future<void> _pickType() async {
    final v = await showWheelPicker<String>(
      context,
      title: '단체 유형 선택',
      values: _typeOptions,
      current: _selected ?? _typeOptions.first,
      labelOf: (s) => s,
    );
    if (v == null) return;
    setState(() => _selected = v);
    if (_slot == 'type') _advanceSlot('members'); // 유형 → 인원 select.
  }

  Future<void> _pickMembers() async {
    final v = await showWheelPicker<int>(
      context,
      title: '참여 인원 선택',
      values: [
        for (var n = TeamRoom.kMinMembers; n <= TeamRoom.kMaxMembers; n++) n,
      ],
      current: _memberTarget ?? TeamRoom.kMinMembers,
      labelOf: (n) => '$n명',
    );
    if (v == null) return;
    setState(() => _memberTarget = v); // 헤드라인 즉시 갱신.
    if (_slot == 'members') _advanceSlot('done'); // 인원 select → 사라짐 + CTA.
  }
}
