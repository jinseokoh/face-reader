import 'dart:io' show Platform;

import 'package:facely/core/theme.dart';
import 'package:facely/data/services/auth_service.dart' show SignUpOutcome;
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/widgets/otp_verification_sheet.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Shows a login bottom sheet. Returns true if login succeeded (Kakao browser
/// launched or email sign-in/up succeeded).
Future<bool> showLoginBottomSheet(BuildContext context, WidgetRef ref) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // viewInsetsOf 는 viewInsets 만 listen — MediaQuery.of 보다 selective.
    // 키보드 애니메이션 중 매 frame rebuild 가 발생해도 다른 메트릭 변화
    // 에는 반응 안 함. 모달의 const _LoginSheet 는 동일 instance 라
    // 자식 element 트리는 보존, Padding 만 padding 재적용.
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: const _LoginSheet(),
    ),
  );
  return result ?? false;
}

class _LoginSheet extends ConsumerStatefulWidget {
  const _LoginSheet();

  @override
  ConsumerState<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends ConsumerState<_LoginSheet> {
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;

  // Apple 로그인 버튼은 iOS(아이폰)에서만 노출 — 그 외 플랫폼엔 Sign in with
  // Apple 네이티브 시트가 없거나 대상이 아니다.
  static final bool _isAppleDevice = Platform.isIOS;
  String? _errorMessage; // inline 표시 — snackbar 가 sheet 뒤로 가는 문제 회피.

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool get _canSubmit {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    return email.isNotEmpty && password.length >= 6;
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _isSignUp;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        // form 이 길어지면 모달 sheet 의 height 제한을 넘기는 경우 발생 →
        // 자체 scroll 로 흡수. keyboard 가 올라와도 viewInsets + 이 scroll 로
        // 안전.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // drag handle — sheet 상단 시각 cue + 탭 위로 breathing room.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // ── 모드 segmented control — 로그인 vs 가입 ──────────────
              // SSOT 이자 가장 prominent 한 mode signal. 다른 모든 라벨
              // (제목·카카오 버튼·submit 버튼·하단 hint)도 이 값에 따라 동시
              // 변경 → 사용자가 어느 모드인지 1초 만에 파악.
              _ModeSegmented(
                isSignUp: isSignUp,
                onChanged: _isLoading
                    ? null
                    : (v) => setState(() {
                        _isSignUp = v;
                        _errorMessage = null;
                      }),
              ),
              const SizedBox(height: 24),
              // ── 헤더 (모드별 문구) ───────────────────────────────────
              Text(
                isSignUp ? '새 계정 만들기' : '로그인',
                textAlign: TextAlign.center,
                style: AppText.modalTitle,
              ),
              const SizedBox(height: 8),
              Text(
                isSignUp ? '가입 후 모든 기능을 사용할 수 있습니다.' : '로그인이 필요합니다.',
                textAlign: TextAlign.center,
                style: AppText.body,
              ),
              const SizedBox(height: 24),
              // ── 카카오 (primary) — 모드 무관하게 가장 빠른 경로 ──────
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _kakaoLogin,
                  icon: const FaIcon(
                    FontAwesomeIcons.kakaoTalk,
                    size: 18,
                    color: Color(0xFF3C1E1E),
                  ),
                  label: Text(
                    isSignUp ? '카카오로 가입' : '카카오로 로그인',
                    style: AppText.subTitle.copyWith(
                      color: const Color(0xFF3C1E1E),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE500),
                    foregroundColor: const Color(0xFF3C1E1E),
                    disabledBackgroundColor: const Color(
                      0xFFFEE500,
                    ).withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              // ── Apple (애플 기기 전용) — 카카오와 동일 버튼 형태 유지 ────
              if (_isAppleDevice) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  // Apple 공식 white-outline 변형 — 검정 invert CTA 전면 폐기.
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _appleLogin,
                    icon: const FaIcon(
                      FontAwesomeIcons.apple,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                    label: Text(
                      isSignUp ? 'Apple로 가입' : 'Apple로 로그인',
                      style: AppText.subTitle.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.background,
                      foregroundColor: AppColors.textPrimary,
                      disabledBackgroundColor: AppColors.background,
                      disabledForegroundColor: AppColors.textHint,
                      side: const BorderSide(color: AppColors.textPrimary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              // ── divider with text ────────────────────────────────────
              Row(
                children: [
                  Expanded(child: Container(height: 1, color: AppTheme.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('또는 이메일로', style: AppText.hint),
                  ),
                  Expanded(child: Container(height: 1, color: AppTheme.border)),
                ],
              ),
              const SizedBox(height: 16),
              // ── 이메일 form ──────────────────────────────────────────
              // AutofillGroup 으로 두 필드 묶음 — iOS Keychain 조회를
              // batch 처리해 첫 tap 시 응답성 개선. 묶이지 않으면 각
              // TextField 가 개별 autofill query 를 trigger.
              AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: '이메일',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: _isLoading ? null : (_) => _emailSubmit(),
                      decoration: InputDecoration(
                        labelText: '비밀번호 (6자 이상)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '비밀번호 보기' : '비밀번호 숨기기',
                          icon: FaIcon(
                            _obscurePassword
                                ? FontAwesomeIcons.eye
                                : FontAwesomeIcons.eyeSlash,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: isSignUp ? '가입하기' : '로그인',
                busy: _isLoading,
                onPressed: _canSubmit ? _emailSubmit : null,
              ),
              // 인라인 에러 — modal sheet 위 영역에 표시되므로 snackbar 처럼
              // 가려질 일 없음. AppColors.danger 살짝 tint 한 box + icon.
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.circleExclamation,
                        size: 14,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppText.caption.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // ── 하단 hint (mode 별) — 같은 톤(textHint·12px)으로 통일.
              // 가입 모드의 reward 가치는 gift 아이콘으로만 시각 차별.
              // 로그인 모드에는 OTP sheet 와 동일 패턴 — "처음이신가요?" 평문 +
              // "가입 페이지로 이동" inline clickable.
              if (isSignUp)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.gift,
                      size: 12,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text('첫 가입 시 3코인 지급', style: AppText.hint),
                  ],
                )
              else
                Text.rich(
                  TextSpan(
                    style: AppText.hint,
                    children: [
                      const TextSpan(text: '처음이신가요? '),
                      TextSpan(
                        text: '가입으로 이동',
                        style: AppText.hint.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: _isLoading
                            ? null
                            : (TapGestureRecognizer()
                                ..onTap = () => setState(() {
                                  _isSignUp = true;
                                  _errorMessage = null;
                                })),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // submit 버튼 enabled 상태는 두 필드 내용에 따라 결정 — 매 입력마다 rebuild.
    _emailCtrl.addListener(_onFormChanged);
    _passwordCtrl.addListener(_onFormChanged);
  }

  Future<void> _emailSubmit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    debugPrint(
      '[Login.emailSubmit] start mode=${_isSignUp ? "signup" : "signin"} '
      'email=$email pwLen=${password.length}',
    );
    if (email.isEmpty || password.length < 6) {
      debugPrint(
        '[Login.emailSubmit] validation fail '
        '(email empty=${email.isEmpty} pwLen=${password.length})',
      );
      setState(() => _errorMessage = '이메일과 6자 이상 비밀번호를 입력하세요');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final notifier = ref.read(authProvider.notifier);

    if (_isSignUp) {
      final res = await notifier.signUpWithEmail(email, password);
      debugPrint(
        '[Login.emailSubmit] signUp outcome=${res.outcome} '
        'msg=${res.message}',
      );
      if (!mounted) return;
      switch (res.outcome) {
        case SignUpOutcome.newAccount:
          final otpResult = await showOtpVerificationSheet(
            context,
            ref,
            email: email,
          );
          debugPrint('[Login.emailSubmit] otpResult=$otpResult');
          if (!mounted) return;
          switch (otpResult) {
            case OtpSheetResult.verified:
              Navigator.of(context).pop(true);
            case OtpSheetResult.switchToLogin:
              setState(() {
                _isSignUp = false;
                _isLoading = false;
              });
            case OtpSheetResult.cancelled:
              setState(() => _isLoading = false);
          }
        case SignUpOutcome.alreadyRegistered:
          setState(() {
            _isSignUp = false;
            _isLoading = false;
            _errorMessage = '이미 가입된 이메일입니다. 로그인을 진행하세요.';
          });
        case SignUpOutcome.error:
          setState(() {
            _isLoading = false;
            _errorMessage = res.message ?? '가입 실패';
          });
      }
      return;
    }

    // ── 로그인 모드 ──────────────────────────────────────────────
    final res = await notifier.loginWithEmail(email, password);
    debugPrint('[Login.emailSubmit] signIn ok=${res.ok} msg=${res.message}');
    if (!mounted) return;
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = res.message ?? '로그인 실패';
      });
    }
  }

  Future<void> _kakaoLogin() async {
    setState(() => _isLoading = true);
    final launched = await ref.read(authProvider.notifier).loginWithKakao();
    if (mounted) {
      Navigator.of(context).pop(launched);
    }
  }

  /// Apple 네이티브 로그인 — Kakao(브라우저)와 달리 즉시 세션이 생성되므로
  /// 성공 시 바로 pop(true). 취소면 message=null 이라 에러 표시 없이 복귀.
  Future<void> _appleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final res = await ref.read(authProvider.notifier).loginWithApple();
    if (!mounted) return;
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = res.message;
      });
    }
  }

  void _onFormChanged() {
    if (mounted) {
      setState(() {
        // 사용자가 다시 입력하기 시작하면 이전 에러 사라짐.
        if (_errorMessage != null) _errorMessage = null;
      });
    }
  }
}

/// 로그인 / 가입 두 모드를 한 줄로 보여주는 segmented control. 선택된 쪽은
/// 검정 fill + 흰 글씨, 미선택은 transparent + 회색 글씨. tap 가능 영역이
/// 절반씩 — 사용자가 어느 모드인지 직관적으로 파악 + 한 번에 전환.
class _ModeSegmented extends StatelessWidget {
  final bool isSignUp;
  final ValueChanged<bool>? onChanged;

  const _ModeSegmented({required this.isSignUp, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              label: '로그인',
              selected: !isSignUp,
              onTap: () => onChanged?.call(false),
            ),
          ),
          Expanded(
            child: _segment(
              label: '가입',
              selected: isSignUp,
              onTap: () => onChanged?.call(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onChanged == null ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppTheme.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppText.subTitle.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
