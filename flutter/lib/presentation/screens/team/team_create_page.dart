import 'dart:async';

import 'package:facely/core/theme.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 교감도 방 생성 풀페이지 — Toss 스타일 스텝 플로우 (2026-06-27 개정).
/// 카메라 캡처와 동일한 바텀 슬라이드 풀페이지. 한 화면에서 질문 1개 + 입력 1개씩
/// 누적: 인트로(회전 훅) → 인원 → 나 포함 → 참가자 이름 → 검토. 답한 스텝은
/// 컴팩트 요약으로 접히고 다음 스텝이 fade+slide 로 내려온다.
/// 반환: 생성된 TeamRoom (취소 시 null).
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

/// 스텝 플로우 단계. name 은 단일 활성 단계로, 필요한 이름이 다 모일 때까지
/// 같은 컨트롤러로 슬롯을 하나씩 reveal 한다.
enum _Step { intro, count, includeOwner, name, review }

/// "우리 〔팀〕에서 나랑 케미가 제일 잘 맞는 사람은?" — 키워드만
/// fade+slide 로 교체되는 훅 헤드라인. SongMyung display 토큰.
class _HookHeadline extends StatelessWidget {
  final String word;

  const _HookHeadline({required this.word});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('우리 ', style: AppText.display),
            _RotatingWord(word: word),
            Text('에서', style: AppText.display),
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

/// 멤버 이름 칩 — 명단 입력용 단일 톤 pill (§3.3). onRemove 없으면 X 없음(나).
/// [number] 는 명단 순번(1-indexed) — '1. 나' 처럼 이름과 동일 톤으로 앞에 붙는다.
class _MemberChip extends StatelessWidget {
  final int number;
  final String name;
  final VoidCallback? onRemove;

  const _MemberChip({
    required this.number,
    required this.name,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs + 1,
        onRemove != null ? AppSpacing.sm : AppSpacing.md,
        AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$number. $name',
            style: AppText.body.copyWith(color: AppColors.textPrimary),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: AppSpacing.xs),
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: FaIcon(
                  FontAwesomeIcons.xmark,
                  size: 12,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 회전 키워드 — 전환 400ms 동안만 크로스페이드 Stack 을 쓰고, 정지
/// 상태에선 래퍼 없는 평문 [Text] 로 렌더한다. 전환 위젯(opacity/transform
/// 레이어) 안의 텍스트는 글리프 픽셀 스냅이 달라져 옆 글자보다 흐릿하게
/// 보이는 문제가 있어, 화면에 머무는 시간(약 1.1초)에는 일반 텍스트와
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

/// once-only 등장 위젯 — Fade 0→1 + Slide translateY 위로 살짝, 360ms
/// easeOutCubic. 다음 스텝/슬롯이 내려오는 reveal 연출 전용. [revealKey] 가
/// 바뀌면(같은 위치의 새 슬롯) 다시 처음부터 재생한다.
class _RevealOnce extends StatefulWidget {
  final Widget child;

  const _RevealOnce({super.key, required this.child});

  @override
  State<_RevealOnce> createState() => _RevealOnceState();
}

class _RevealOnceState extends State<_RevealOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  )..forward();

  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// 모임 유형 선택 시트 — 회전 키워드 목록에서 고르거나 마지막 '직접 입력'
/// 으로 커스텀 이름을 적는다. 선택값(키워드 String) 반환, 취소 시 null.
/// 시트 chrome 은 legal_doc_sheet 와 동일(grab handle·흰 배경·radius 20).
Future<String?> _showKeywordSheet(
  BuildContext context, {
  required List<String> words,
  required String current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _KeywordSheet(words: words, current: current),
  );
}

class _KeywordSheet extends StatefulWidget {
  final List<String> words;
  final String current;

  const _KeywordSheet({required this.words, required this.current});

  @override
  State<_KeywordSheet> createState() => _KeywordSheetState();
}

class _KeywordSheetState extends State<_KeywordSheet> {
  bool _custom = false;
  late final TextEditingController _input = TextEditingController(
    text: widget.words.contains(widget.current) ? '' : widget.current,
  );
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // grab handle — partial sheet 공통 chrome.
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xs,
              ),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _custom ? _customBody() : _listBody(),
          ],
        ),
      ),
    );
  }

  Widget _listBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.sm,
            AppSpacing.xxl,
            AppSpacing.sm,
          ),
          child: Text('어떤 모임이에요?', style: AppText.modalTitle),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            children: [
              for (final w in widget.words)
                _row(
                  label: '우리 $w',
                  selected: w == widget.current,
                  onTap: () => Navigator.of(context).pop(w),
                ),
              _row(
                label: '직접 입력',
                trailing: FontAwesomeIcons.pen,
                onTap: () {
                  setState(() => _custom = true);
                  _focus.requestFocus();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _customBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            0,
            AppSpacing.xxl,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _custom = false),
                icon: const FaIcon(
                  FontAwesomeIcons.arrowLeft,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
              ),
              Text('직접 입력', style: AppText.modalTitle),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: TextField(
            controller: _input,
            focusNode: _focus,
            autofocus: true,
            maxLength: 14,
            textInputAction: TextInputAction.done,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '예) 우리 가족, 강남 스터디',
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
            onSubmitted: (_) => _confirmCustom(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.xxl,
            AppSpacing.xxl,
          ),
          child: PrimaryButton(label: '확인', onPressed: _confirmCustom),
        ),
      ],
    );
  }

  Widget _row({
    required String label,
    bool selected = false,
    FaIconData? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.body.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (selected)
              const FaIcon(
                FontAwesomeIcons.check,
                size: 16,
                color: AppColors.textPrimary,
              ),
            if (trailing != null)
              FaIcon(trailing, size: 13, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  void _confirmCustom() {
    final v = _input.text.trim();
    if (v.isEmpty) {
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(v);
  }
}

class _TeamCreatePage extends ConsumerStatefulWidget {
  final String ownerReportId;

  const _TeamCreatePage({required this.ownerReportId});

  @override
  ConsumerState<_TeamCreatePage> createState() => _TeamCreatePageState();
}

class _TeamCreatePageState extends ConsumerState<_TeamCreatePage>
    with WidgetsBindingObserver {
  // 교감도 모임 훅 — 회전 키워드. "우리 {키워드}에서 나랑 케미가 제일
  // 잘 맞는 사람은?" — 전부 "우리 ○에서" 결합이 자연스러운 단어.
  static const _hookWords = [
    '팀',
    '반',
    '모임',
    '조직',
    '회사',
    '부서',
    '좋소',
    '크루',
    '동아리',
    '패밀리',
  ];

  final ScrollController _scroll = ScrollController();
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  Timer? _hookTimer;
  int _hookIndex = 0;

  // ── 답변값 ─────────────────────────────────────────────────────────
  _Step _step = _Step.intro;

  /// 인트로에서 동결한 키워드. null 이면 아직 회전 중.
  String? _frozenWord;

  /// 직접 입력한 전체 제목. null 이면 프리셋("우리 {키워드}") 사용.
  String? _customTitle;

  /// 케미 그룹 총 인원 (나 포함). clamp(3, 12).
  int _count = 4;

  /// 참가자에 나도 포함하는가. null = 미선택.
  bool? _includeOwner;

  final List<String> _names = [];

  String? _nameError;
  bool _creating = false;

  /// 방 제목 — 직접 입력값이 있으면 그대로, 없으면 "우리 {키워드}".
  String get _title => _customTitle ?? '우리 ${_frozenWord ?? _hookWords[_hookIndex]}';

  /// 수집해야 할 참가자 이름 수 — 나 포함이면 총원-1, 아니면 총원.
  int get _neededNames => (_includeOwner ?? true) ? _count - 1 : _count;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startHookRotation();
  }

  /// 훅 키워드 회전 시작/재개 — 1.5초마다 키워드 교체. 인트로 진입마다 호출.
  void _startHookRotation() {
    _hookTimer?.cancel();
    _hookTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() => _hookIndex = (_hookIndex + 1) % _hookWords.length);
    });
  }

  /// 인트로(시작 페이지)로 복귀 — 동결 해제 + 키워드 회전 재개.
  void _goIntro() {
    setState(() {
      _frozenWord = null;
      _customTitle = null;
      _step = _Step.intro;
    });
    _startHookRotation();
  }

  /// 모임 유형 편집 — 접힌 '우리 ○' 헤더의 연필 탭. 시트에서 키워드를 고르거나
  /// 직접 입력하면 동결 키워드를 교체한다(방 제목에 반영).
  Future<void> _editKeyword() async {
    final picked = await _showKeywordSheet(
      context,
      words: _hookWords,
      current: _customTitle ?? _frozenWord ?? _hookWords[_hookIndex],
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (_hookWords.contains(picked)) {
        // 프리셋 키워드 — "우리 {키워드}".
        _frozenWord = picked;
        _customTitle = null;
      } else {
        // 직접 입력 — 전체 제목 그대로(프리픽스 강제 없음).
        _customTitle = picked;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hookTimer?.cancel();
    _scroll.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // 키보드 inset 변화 시 활성 입력을 키보드 위로 다시 스크롤.
  @override
  void didChangeMetrics() => _scrollToBottomSoon();

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
          leading: _step == _Step.intro
              ? null
              : IconButton(
                  onPressed: _back,
                  icon: const FaIcon(
                    FontAwesomeIcons.arrowLeft,
                    color: AppColors.textPrimary,
                    size: 20,
                  ),
                ),
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
        body: PopScope(
          canPop: _step == _Step.intro,
          onPopInvokedWithResult: (didPop, _) {
            // 시스템 백(안드로이드 하드웨어·iOS 드래그)을 스텝 후퇴로 일치시킨다 —
            // 멀티스텝 입력 도중 시트 전체가 닫혀 명단이 날아가지 않게.
            if (!didPop) _back();
          },
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildSteps(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxl,
                    AppSpacing.sm,
                    AppSpacing.xxl,
                    AppSpacing.xxl,
                  ),
                  child: PrimaryButton(
                    label: _ctaLabel,
                    busy: _creating,
                    onPressed: _ctaAction,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 스텝 본문 ───────────────────────────────────────────────────────

  List<Widget> _buildSteps() {
    final ord = _step.index;
    return [
      const SizedBox(height: AppSpacing.lg),
      _introSlot(),
      if (ord >= _Step.count.index) ...[
        const SizedBox(height: AppSpacing.lg),
        _countSlot(),
      ],
      if (ord >= _Step.includeOwner.index) ...[
        const SizedBox(height: AppSpacing.lg),
        _includeOwnerSlot(),
      ],
      if (ord >= _Step.name.index) ...[
        const SizedBox(height: AppSpacing.lg),
        _nameAndReviewSlot(),
      ],
      const SizedBox(height: AppSpacing.huge),
    ];
  }

  /// 답한 스텝 ↔ 활성 스텝 전환 — fade(AnimatedSwitcher) + size(AnimatedSize).
  Widget _slot({required Widget child}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        child: child,
      ),
    );
  }

  // 인트로 — 활성: 회전 훅 + 맵 이미지. 접힘: '우리 ○' quiet 헤더 한 줄.
  Widget _introSlot() {
    final active = _step == _Step.intro;
    return _slot(
      child: active
          ? Column(
              key: const ValueKey('intro-hero'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HookHeadline(word: _frozenWord ?? _hookWords[_hookIndex]),
                const SizedBox(height: AppSpacing.md),
                Text('이름만 적으면 한 명씩 케미를 봐줄게요.', style: AppText.body),
                const SizedBox(height: AppSpacing.xl),
                Image.asset(
                  'assets/images/team-chemistry-map.png',
                  height: 180,
                  fit: BoxFit.contain,
                ),
              ],
            )
          : _quietHeader(
              key: const ValueKey('intro-quiet'),
              label: _title,
              onTap: _editKeyword,
            ),
    );
  }

  // 인원 — 활성: 촉각 스테퍼. 접힘: '인원 {n}명' summary row.
  Widget _countSlot() {
    final active = _step == _Step.count;
    return _slot(
      child: active
          ? Column(
              key: const ValueKey('count-active'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _question(
                  '몇 명의 케미를\n함께 볼까요?',
                  '나를 포함해 최소 3명, 최대 12명까지 볼 수 있어요.',
                ),
                const SizedBox(height: AppSpacing.xl),
                _stepper(),
              ],
            )
          : _summaryRow(
              key: const ValueKey('count-summary'),
              label: '인원',
              value: '$_count명',
              onTap: () => setState(() => _step = _Step.count),
            ),
    );
  }

  // 나 포함 — 활성: 전폭 선택 카드 2개. 접힘: '나 포함/제외' summary row.
  Widget _includeOwnerSlot() {
    final active = _step == _Step.includeOwner;
    return _slot(
      child: active
          ? Column(
              key: const ValueKey('owner-active'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _question('참가자에 나도 포함할까요?', '내 얼굴까지 함께 케미를 보려면 포함하세요.'),
                const SizedBox(height: AppSpacing.xl),
                _choiceCard(
                  selected: _includeOwner == true,
                  title: '네, 저도 포함할게요',
                  subtitle: '내 관상도 매트릭스에 들어가요',
                  onTap: () => _selectIncludeOwner(true),
                ),
                const SizedBox(height: AppSpacing.md),
                _choiceCard(
                  selected: _includeOwner == false,
                  title: '아니요, 이 사람들만 볼게요',
                  subtitle: '나는 빼고 참가자끼리만 봐요',
                  onTap: () => _selectIncludeOwner(false),
                ),
              ],
            )
          : _summaryRow(
              key: const ValueKey('owner-summary'),
              label: '나',
              value: (_includeOwner ?? true) ? '포함' : '제외',
              onTap: () => setState(() => _step = _Step.includeOwner),
            ),
    );
  }

  // 참가자 이름 수집 + 최종 검토 — 누적 칩 Wrap 이 라이브 명단 미리보기.
  Widget _nameAndReviewSlot() {
    final review = _step == _Step.review;
    final includeMe = _includeOwner ?? true;
    final displayN = includeMe ? _names.length + 2 : _names.length + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _question(
          review ? '이 멤버들로 케미를 볼까요?' : '$displayN번째 참가자는 누구?',
          review ? '이름을 지우거나 추가하려면 칩을 눌러요.' : '이름을 적은 후 다음을 누르세요.',
        ),
        const SizedBox(height: AppSpacing.lg),
        // 라이브 명단 — '나' 칩 선두(포함 시) + 참가자 칩. 번호는 1-indexed
        // (포함 시 나=1·참가자 2.., 미포함 시 참가자 1..).
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (includeMe) const _MemberChip(number: 1, name: '나'),
              for (final entry in _names.asMap().entries)
                _popInChip(
                  key: ValueKey(entry.value),
                  child: review
                      ? GestureDetector(
                          onTap: () => _editName(entry.value),
                          child: _MemberChip(
                            number: (includeMe ? 2 : 1) + entry.key,
                            name: entry.value,
                            onRemove: () => _removeName(entry.value),
                          ),
                        )
                      : _MemberChip(
                          number: (includeMe ? 2 : 1) + entry.key,
                          name: entry.value,
                          onRemove: () => _removeName(entry.value),
                        ),
                ),
            ],
          ),
        ),
        if (!review) ...[
          const SizedBox(height: AppSpacing.lg),
          // key 는 슬롯 수와 무관한 상수 — 이름 확정마다 입력창 element 를
          // 유지해 포커스/키보드가 끊기지 않게 한다(매번 재생성 시 포커스 유실).
          // 첫 진입 때 한 번만 reveal 슬라이드, 이후엔 element 보존.
          _RevealOnce(
            key: const ValueKey('name-slot'),
            child: _nameField(),
          ),
          if (_nameError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _nameError!,
              style: AppText.hint.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // 카운터 분모를 총원으로 통일 — 질문 "$displayN번째" 와 동일 기준.
          Text('$_count명 중 $displayN번째 참가자', style: AppText.hint),
        ],
      ],
    );
  }

  // ── 공용 조각 ───────────────────────────────────────────────────────

  Widget _question(String q, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(q, style: AppText.display),
        const SizedBox(height: AppSpacing.sm),
        Text(sub, style: AppText.caption),
      ],
    );
  }

  Widget _quietHeader({
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Text(label, style: AppText.subTitle),
            const SizedBox(width: AppSpacing.sm),
            const FaIcon(
              FontAwesomeIcons.pen,
              size: 12,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Text(label, style: AppText.caption),
            const SizedBox(width: AppSpacing.md),
            Text(value, style: AppText.subTitle),
            const Spacer(),
            const FaIcon(
              FontAwesomeIcons.pen,
              size: 12,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepper() {
    final canDec = _count > TeamRoom.kMinMembers;
    final canInc = _count < TeamRoom.kMaxMembers;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepperButton(
          icon: FontAwesomeIcons.minus,
          enabled: canDec,
          onTap: () => _bumpCount(-1),
        ),
        const SizedBox(width: AppSpacing.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.5, end: 1).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                '$_count',
                key: ValueKey('count-$_count'),
                style: AppText.display,
              ),
            ),
            Text(' 명', style: AppText.subTitle),
          ],
        ),
        const SizedBox(width: AppSpacing.xl),
        _stepperButton(
          icon: FontAwesomeIcons.plus,
          enabled: canInc,
          onTap: () => _bumpCount(1),
        ),
      ],
    );
  }

  Widget _stepperButton({
    required FaIconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: FaIcon(
              icon,
              size: 18,
              color: enabled ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _choiceCard({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg,
          horizontal: AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.subTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle, style: AppText.caption),
                ],
              ),
            ),
            if (selected)
              const FaIcon(
                FontAwesomeIcons.check,
                size: 16,
                color: AppColors.textPrimary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _nameField() {
    final lastSlot = _names.length + 1 >= _neededNames;
    return TextField(
      controller: _nameController,
      focusNode: _nameFocus,
      autofocus: true,
      textInputAction: lastSlot ? TextInputAction.done : TextInputAction.next,
      maxLength: 10,
      style: AppText.body.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: '이름을 입력하세요',
        hintStyle: AppText.body.copyWith(color: AppColors.textHint),
        counterText: '',
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        suffixIcon: IconButton(
          icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
          color: AppColors.textPrimary,
          onPressed: () => _confirmName(),
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
      onSubmitted: (v) => _confirmName(v),
    );
  }

  Widget _popInChip({required Key key, required Widget child}) {
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.9 + 0.1 * t, child: c),
      ),
      child: child,
    );
  }

  // ── 하단 CTA 파생 ──────────────────────────────────────────────────

  String get _ctaLabel {
    switch (_step) {
      case _Step.intro:
        return '시작하기';
      case _Step.review:
        return '케미 그룹 입장하기';
      default:
        return '다음';
    }
  }

  VoidCallback? get _ctaAction {
    switch (_step) {
      case _Step.intro:
        return _start;
      case _Step.count:
        return _confirmCount;
      case _Step.includeOwner:
        return null; // 카드 탭 auto-advance.
      case _Step.name:
        return _confirmName;
      case _Step.review:
        return _enterRoom;
    }
  }

  // ── 액션 / 전환 ────────────────────────────────────────────────────

  void _start() {
    _hookTimer?.cancel();
    setState(() {
      _frozenWord = _hookWords[_hookIndex];
      _step = _Step.count;
    });
    _scrollToBottomSoon();
  }

  void _bumpCount(int delta) {
    final next = (_count + delta).clamp(
      TeamRoom.kMinMembers,
      TeamRoom.kMaxMembers,
    );
    if (next == _count) return;
    HapticFeedback.selectionClick();
    setState(() => _count = next);
  }

  void _confirmCount() {
    // 인원 축소로 이름이 넘치면 꼬리부터 trim (앞쪽 보존).
    if (_includeOwner != null && _names.length > _neededNames) {
      _names.removeRange(_neededNames, _names.length);
    }
    setState(() => _step = _Step.includeOwner);
    _scrollToBottomSoon();
  }

  void _selectIncludeOwner(bool value) {
    HapticFeedback.selectionClick();
    setState(() => _includeOwner = value); // 140ms 하이라이트.
    Future.delayed(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      // 토글로 필요한 이름 수가 줄면 초과분 drop.
      if (_names.length > _neededNames) {
        _names.removeRange(_neededNames, _names.length);
      }
      setState(() {
        _step = _names.length >= _neededNames ? _Step.review : _Step.name;
      });
      _scrollToBottomSoon(focusName: true);
    });
  }

  void _confirmName([String? raw]) {
    final name = (raw ?? _nameController.text).trim();
    if (name.isEmpty) {
      _nameFocus.requestFocus();
      return;
    }
    if (name == '나' || _names.contains(name)) {
      _nameController.clear();
      setState(() => _nameError = '이미 있는 이름이에요');
      _nameFocus.requestFocus();
      return;
    }
    _nameController.clear();
    setState(() {
      _names.add(name);
      _nameError = null;
      if (_names.length >= _neededNames) _step = _Step.review;
    });
    _scrollToBottomSoon(focusName: true);
  }

  void _removeName(String name) {
    setState(() {
      _names.remove(name);
      _nameError = null;
      if (_names.length < _neededNames) _step = _Step.name;
    });
  }

  void _editName(String name) {
    setState(() {
      _names.remove(name);
      _nameController.text = name;
      _nameError = null;
      _step = _Step.name;
    });
    _scrollToBottomSoon(focusName: true);
  }

  void _back() {
    switch (_step) {
      case _Step.intro:
        return;
      case _Step.count:
        _goIntro();
      case _Step.includeOwner:
        setState(() => _step = _Step.count);
      case _Step.name:
        if (_names.isNotEmpty) {
          // 직전 슬롯 재편집 — 마지막 이름을 필드로 되돌린다.
          setState(() {
            _nameController.text = _names.removeLast();
            _nameError = null;
          });
        } else {
          setState(() => _step = _Step.includeOwner);
        }
      case _Step.review:
        if (_names.isNotEmpty) {
          setState(() {
            _nameController.text = _names.removeLast();
            _nameError = null;
            _step = _Step.name;
          });
        } else {
          setState(() => _step = _Step.includeOwner);
        }
    }
    _scrollToBottomSoon(focusName: true);
  }

  Future<void> _enterRoom() async {
    if (_creating) return;
    // 입력 중이던 이름이 남아 있으면 흡수.
    if (_nameController.text.trim().isNotEmpty) _confirmName();
    setState(() => _creating = true);
    final room = await ref
        .read(teamsProvider.notifier)
        .create(
          title: _title,
          ownerReportId: widget.ownerReportId,
          pendingNames: List<String>.from(_names),
          includeOwner: _includeOwner ?? true,
        );
    if (!mounted) return;
    Navigator.of(context).pop(room);
  }

  void _scrollToBottomSoon({bool focusName = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 새 슬롯이 빌드된 다음 프레임에 포커스를 다시 잡아 키보드가 끊기지 않게.
      if (focusName && _step == _Step.name) _nameFocus.requestFocus();
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }
}
