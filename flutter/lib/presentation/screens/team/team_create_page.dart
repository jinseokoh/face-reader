import 'dart:async';

import 'package:facely/core/theme.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/presentation/providers/team_provider.dart';
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
class _MemberChip extends StatelessWidget {
  final String name;
  final VoidCallback? onRemove;

  const _MemberChip({required this.name, this.onRemove});

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
            name,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: AppSpacing.xs),
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: FaIcon(FontAwesomeIcons.xmark,
                    size: 12, color: AppColors.textHint),
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

  static const int _maxNames = TeamRoom.kMaxMembers - 1; // 나 포함 12
  // 멤버 이름 칩 — 방장(나) 제외 대기 멤버. 하드캡 12 → 최대 11명.
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  final List<String> _names = [];

  /// 입장 최소 인원 — 나 포함 3명(교감도 성립 최소 단위).
  static const int _minMembers = 3;

  Timer? _hookTimer;
  int _hookIndex = 0;
  bool _creating = false;

  /// 인원 미달 검증 에러 — 나 포함 3명 미만으로 입장 시도 시 노출.
  String? _error;

  /// 방 제목 — 입장 시점 헤드라인 키워드 스냅샷 ("우리 팀" 등). 방 화면 기어로 변경.
  String get _title => '우리 ${_hookWords[_hookIndex]}';

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
                      // 교감도 모임 훅 — 회전 키워드 헤드라인 (장식).
                      _HookHeadline(word: _hookWords[_hookIndex]),
                      const SizedBox(height: AppSpacing.xl),
                      Image.asset(
                        'assets/images/team-chemistry-map.png',
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                      // 멤버 이름 칩 입력 — 처음부터 노출.
                      _inviteSection(),
                    ],
                  ),
                ),
              ),
              // 하단 고정 CTA.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  AppSpacing.sm,
                  AppSpacing.xxl,
                  AppSpacing.lg,
                ),
                child: PrimaryButton(
                  label: '케미 그룹 입장하기',
                  busy: _creating,
                  onPressed: _enterRoom,
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
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _hookTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() => _hookIndex = (_hookIndex + 1) % _hookWords.length);
    });
  }

  /// 이름 칩 추가 — 공백 제거·중복 차단·11명 상한.
  void _addName([String? raw]) {
    final name = (raw ?? _nameController.text).trim();
    _nameController.clear();
    if (name.isEmpty) return;
    if (_names.length >= _maxNames) return;
    if (name == '나' || _names.contains(name)) {
      // 중복·예약어는 무시하고 입력만 비운다.
      _nameFocus.requestFocus();
      return;
    }
    setState(() {
      _names.add(name);
      _error = null;
    });
    _nameFocus.requestFocus(); // 연속 입력.
  }

  /// 방 입장 — 명단(칩)으로 방을 만들고 방 화면으로.
  Future<void> _enterRoom() async {
    if (_creating) return;
    if (_title.isEmpty) {
      FocusScope.of(context).unfocus();
      return;
    }
    // 입력 중이던 이름이 남아 있으면 칩으로 흡수.
    if (_nameController.text.trim().isNotEmpty) _addName();
    // 나 포함 3명 미만이면 입장 차단 — 교감도는 최소 3명부터 성립.
    if (_names.length + 1 < _minMembers) {
      FocusScope.of(context).unfocus();
      setState(() => _error = '나 포함 3명부터 입장할 수 있어요.');
      return;
    }
    setState(() {
      _error = null;
      _creating = true;
    });
    final room = await ref.read(teamsProvider.notifier).create(
          title: _title,
          ownerReportId: widget.ownerReportId,
          pendingNames: List<String>.from(_names),
        );
    if (!mounted) return;
    Navigator.of(context).pop(room);
  }

  /// 멤버 이름 칩 입력 reveal — 이름을 입력하면 빈 아바타 슬롯이 하나씩 쌓인다.
  Widget _inviteSection() {
    final canAddMore = _names.length < _maxNames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text(
          '함께할 멤버 이름을 입력하세요',
          style: AppText.subTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '이름을 입력하면 자리가 하나씩 생겨요.',
          style: AppText.hint,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        // 멤버 슬롯 — 나 + 입력한 이름 칩 (X 로 개별 삭제).
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _MemberChip(name: '나'),
            for (final n in _names)
              _MemberChip(name: n, onRemove: () => _removeName(n)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (canAddMore)
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            textInputAction: TextInputAction.done,
            maxLength: 10,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '이름 입력 후 엔터',
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
                onPressed: () => _addName(),
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
            onSubmitted: _addName,
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          canAddMore
              ? '최대 12명까지 채울 수 있어요. (빈자리: ${_maxNames - _names.length})'
              : '최대 12명까지 채울 수 있어요',
          style: AppText.hint,
          textAlign: TextAlign.center,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: AppText.hint.copyWith(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  void _removeName(String name) => setState(() {
        _names.remove(name);
        _error = null;
      });

}
