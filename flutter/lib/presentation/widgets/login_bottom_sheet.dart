import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/services/auth_service.dart' show SignUpOutcome;
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/widgets/otp_verification_sheet.dart';
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(ctx).bottom,
      ),
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
                    : (v) => setState(() => _isSignUp = v),
              ),
              const SizedBox(height: 24),
              // ── 헤더 (모드별 문구) ───────────────────────────────────
              Text(
                isSignUp ? '새 계정 만들기' : '로그인',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isSignUp
                    ? '가입 후 모든 기능을 사용할 수 있습니다.'
                    : '로그인이 필요합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              // ── 카카오 (primary) — 모드 무관하게 가장 빠른 경로 ──────
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _kakaoLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE500),
                    foregroundColor: const Color(0xFF3C1E1E),
                    disabledBackgroundColor:
                        const Color(0xFFFEE500).withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isSignUp ? '카카오로 가입' : '카카오로 로그인',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // ── divider with text ────────────────────────────────────
              Row(
                children: [
                  Expanded(
                      child: Container(
                          height: 1, color: AppTheme.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '또는 이메일로',
                      style: TextStyle(
                          color: AppTheme.textHint, fontSize: 12),
                    ),
                  ),
                  Expanded(
                      child: Container(
                          height: 1, color: AppTheme.border)),
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
                          tooltip: _obscurePassword
                              ? '비밀번호 보기'
                              : '비밀번호 숨기기',
                          icon: FaIcon(
                            _obscurePassword
                                ? FontAwesomeIcons.eye
                                : FontAwesomeIcons.eyeSlash,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: (_isLoading || !_canSubmit) ? null : _emailSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.textPrimary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.surface,
                    disabledForegroundColor: AppColors.textHint,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isSignUp ? '가입하기' : '로그인',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              // ── 하단 hint (mode 별) — 같은 톤(textHint·12px)으로 통일.
              // 가입 모드의 reward 가치는 emoji 로만 시각 차별.
              Text(
                isSignUp
                    ? '🎁 첫 가입 시 3코인 지급'
                    : '처음이신가요? 위에서 \'가입\' 을 선택하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textHint, fontSize: 12),
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
    debugPrint('[Login.emailSubmit] start mode=${_isSignUp ? "signup" : "signin"} '
        'email=$email pwLen=${password.length}');
    if (email.isEmpty || password.length < 6) {
      debugPrint('[Login.emailSubmit] validation fail '
          '(email empty=${email.isEmpty} pwLen=${password.length})');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일과 6자 이상 비밀번호를 입력하세요')),
      );
      return;
    }
    setState(() => _isLoading = true);
    final notifier = ref.read(authProvider.notifier);

    if (_isSignUp) {
      final outcome = await notifier.signUpWithEmail(email, password);
      debugPrint('[Login.emailSubmit] signUp outcome=$outcome');
      if (!mounted) return;
      switch (outcome) {
        case SignUpOutcome.newAccount:
          // OTP sheet 띄움.
          final otpResult =
              await showOtpVerificationSheet(context, ref, email: email);
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
          // Supabase user-enumeration 방어 — OTP 안 옴. 로그인 모드로 자동
          // 전환 + 안내.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('이미 가입된 이메일입니다. 로그인 모드로 전환했습니다.')),
          );
          setState(() {
            _isSignUp = false;
            _isLoading = false;
          });
        case SignUpOutcome.error:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('가입 실패 — 잠시 후 다시 시도해주세요')),
          );
          setState(() => _isLoading = false);
      }
      return;
    }

    // ── 로그인 모드 ──────────────────────────────────────────────
    final ok = await notifier.loginWithEmail(email, password);
    debugPrint('[Login.emailSubmit] signIn ok=$ok');
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('로그인 실패 — 이메일/비밀번호를 확인해주세요')),
      );
    }
  }

  Future<void> _kakaoLogin() async {
    setState(() => _isLoading = true);
    final launched = await ref.read(authProvider.notifier).loginWithKakao();
    if (mounted) {
      Navigator.of(context).pop(launched);
    }
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
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
          Expanded(child: _segment(label: '로그인', selected: !isSignUp, onTap: () => onChanged?.call(false))),
          Expanded(child: _segment(label: '가입', selected: isSignUp, onTap: () => onChanged?.call(true))),
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
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
