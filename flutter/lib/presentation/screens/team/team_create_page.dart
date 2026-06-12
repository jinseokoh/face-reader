import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/widgets/primary_button.dart';

/// 교감도 방 생성 풀페이지 — PIVOT A6 채택안 B (2026-06-12 풀페이지 개정).
/// 카메라 캡처와 동일한 바텀 슬라이드 풀페이지 패턴. 상단에 "교감도 모임 훅"
/// 헤드라인(우리 팀/반/모임/동아리/가족 키워드 회전)을 크게 노출하고,
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

class _TeamCreatePage extends ConsumerStatefulWidget {
  final String ownerReportId;

  const _TeamCreatePage({required this.ownerReportId});

  @override
  ConsumerState<_TeamCreatePage> createState() => _TeamCreatePageState();
}

class _TeamCreatePageState extends ConsumerState<_TeamCreatePage> {
  // 교감도 모임 훅 — 회전 키워드. "우리 {키워드}에서 나랑 케미가 제일
  // 잘 맞는 사람은?" 조사 충돌이 없는 단어만 (전부 받침 없음/에서 결합 자연).
  static const _hookWords = ['팀', '반', '모임', '동아리', '가족'];
  static const _suggestions = ['회식', 'MT', '동아리', '가족', '스터디'];

  final TextEditingController _controller = TextEditingController();
  Timer? _hookTimer;
  int _hookIndex = 0;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _hookTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted) return;
      setState(() => _hookIndex = (_hookIndex + 1) % _hookWords.length);
    });
  }

  @override
  void dispose() {
    _hookTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
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
                      // 교감도 모임 훅 — 키워드 회전 헤드라인.
                      _HookHeadline(word: _hookWords[_hookIndex]),
                      const SizedBox(height: AppSpacing.xl),
                      Image.asset(
                        'assets/images/team-chemistry-map.png',
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        '모임 이름',
                        style: AppText.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _controller,
                        maxLength: 20,
                        style: AppText.body.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: '예: 마케팅팀 회식',
                          hintStyle: AppText.body.copyWith(
                            color: AppColors.textHint,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(
                                color: AppColors.textPrimary),
                          ),
                        ),
                        onSubmitted: (_) => _create(),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final s in _suggestions)
                            InkWell(
                              onTap: () =>
                                  setState(() => _controller.text = s),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm + 2,
                                  vertical: AppSpacing.xs,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                  border:
                                      Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  s,
                                  style: AppText.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 하단 고정 — 인원 힌트 + 생성 버튼 (키보드 위로 따라 올라옴).
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  AppSpacing.sm,
                  AppSpacing.xxl,
                  AppSpacing.lg + bottomInset,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '멤버 3~12명, 4~8명이 가장 재밌어요',
                      style: AppText.hint,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PrimaryButton(
                      label: '교감도 방 만들기',
                      busy: _creating,
                      onPressed: _create,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final title = _controller.text.trim();
    if (_creating) return;
    if (title.isEmpty) {
      // 비어 있으면 입력으로 유도 — 페이지의 유일한 필수 입력.
      FocusScope.of(context).unfocus();
      return;
    }
    setState(() => _creating = true);
    final room = await ref.read(teamsProvider.notifier).create(
          title: title,
          ownerReportId: widget.ownerReportId,
        );
    if (!mounted) return;
    Navigator.of(context).pop(room);
  }
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.6),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                word,
                key: ValueKey(word),
                style: AppText.display,
              ),
            ),
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
