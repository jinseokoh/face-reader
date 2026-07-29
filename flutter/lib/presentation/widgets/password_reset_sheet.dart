import 'dart:async';

import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 비밀번호 찾기 — 등록된 이메일로 6자리 recovery OTP 를 보내 본인 확인 후
/// 새 비밀번호를 저장하는 3단계 modal sheet (otp_verification_sheet 와 동일
/// 레시피: 60초 재전송 cooldown, 6자리 자동 제출). 취소 버튼 없음 — 로그인
/// 시트가 먼저 닫힌 뒤 열리므로, 바깥 탭/아래로 드래그가 곧 취소다.
///
/// OTP 검증 성공 시 Supabase 가 세션을 만들어 로그인 상태가 된다 — 새
/// 비밀번호 저장까지 마치면 true 를 pop 하고, 부모(login sheet)는 그대로
/// 로그인 성공 처리하면 된다.
///
/// Supabase user-enumeration 방어 — 미가입 이메일로 요청해도 성공 응답이
/// 오고 메일만 안 간다. 안내 hint 로 막다른 길을 알린다.
Future<bool> showPasswordResetSheet(
  BuildContext context, {
  String? initialEmail,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _PasswordResetSheet(initialEmail: initialEmail),
    ),
  );
  return result ?? false;
}

class _PasswordResetSheet extends ConsumerStatefulWidget {
  final String? initialEmail;
  const _PasswordResetSheet({this.initialEmail});

  @override
  ConsumerState<_PasswordResetSheet> createState() =>
      _PasswordResetSheetState();
}

class _PasswordResetSheetState extends ConsumerState<_PasswordResetSheet> {
  static const _kOtpLength = 6; // Supabase 대시보드 OTP 길이와 동기.
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  _Step _step = _Step.email;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;
  Timer? _resendTimer;
  int _resendCooldownSec = 0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // drag handle — login sheet 와 동일 레시피. 이 시트의 취소는
              // 바깥 탭/아래로 드래그뿐이라 시각 cue 가 곧 탈출구 안내다.
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
              const Text(
                '비밀번호 찾기',
                textAlign: TextAlign.center,
                style: AppText.modalTitle,
              ),
              const SizedBox(height: 12),
              ...switch (_step) {
                _Step.email => _emailStep(),
                _Step.otp => _otpStep(),
                _Step.newPassword => _passwordStep(),
              },
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail ?? '';
  }

  List<Widget> _emailStep() => [
    Text(
      '가입한 이메일로 6자리 인증 코드를 보내드립니다.',
      textAlign: TextAlign.center,
      style: AppText.body,
    ),
    const SizedBox(height: 24),
    TextField(
      controller: _emailCtrl,
      autofocus: true,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.done,
      decoration: _fieldDecoration(hint: 'you@example.com'),
      onSubmitted: _isLoading ? null : (_) => _sendCode(),
    ),
    const SizedBox(height: 16),
    PrimaryButton(label: '인증 코드 받기', busy: _isLoading, onPressed: _sendCode),
    const SizedBox(height: 8),
    Text(
      '가입된 이메일이 아니면 코드가 발송되지 않습니다.',
      textAlign: TextAlign.center,
      style: AppText.hint,
    ),
  ];

  /// otp_verification_sheet 의 필드 레시피와 동일 — 48px 비주얼 가중치.
  InputDecoration _fieldDecoration({
    required String hint,
    double? hintLetterSpacing,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppTheme.textHint,
        letterSpacing: hintLetterSpacing,
      ),
      isCollapsed: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      errorText: _error,
    );
  }

  List<Widget> _otpStep() => [
    Text.rich(
      TextSpan(
        style: AppText.body,
        children: [
          TextSpan(
            text: _emailCtrl.text.trim(),
            style: AppText.body.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const TextSpan(text: ' 으로 코드를 보냈습니다.'),
        ],
      ),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    TextField(
      controller: _otpCtrl,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(_kOtpLength),
      ],
      autofillHints: const [AutofillHints.oneTimeCode],
      textInputAction: TextInputAction.done,
      textAlign: TextAlign.center,
      style: AppText.modalTitle.copyWith(letterSpacing: 4),
      decoration: _fieldDecoration(
        hint: '0' * _kOtpLength,
        hintLetterSpacing: 4,
      ),
      onChanged: (v) {
        if (v.length == _kOtpLength && !_isLoading) _verify();
      },
      onSubmitted: _isLoading ? null : (_) => _verify(),
    ),
    const SizedBox(height: 16),
    PrimaryButton(label: '인증하기', busy: _isLoading, onPressed: _verify),
    const SizedBox(height: 4),
    Center(
      child: TextButton(
        onPressed: _resendCooldownSec > 0 || _isLoading ? null : _sendCode,
        child: Text(
          _resendCooldownSec > 0 ? '재전송 가능까지 $_resendCooldownSec 초' : '이메일 재전송',
          style: AppText.caption.copyWith(
            color: _resendCooldownSec > 0
                ? AppColors.textHint
                : AppColors.textSecondary,
          ),
        ),
      ),
    ),
    Text(
      '메일이 안 오면 스팸함 확인이나 재전송 버튼을 눌러주세요.',
      textAlign: TextAlign.center,
      style: AppText.hint,
    ),
  ];

  List<Widget> _passwordStep() => [
    Text(
      '본인 확인이 끝났습니다. 새 비밀번호를 입력하세요.',
      textAlign: TextAlign.center,
      style: AppText.body,
    ),
    const SizedBox(height: 24),
    TextField(
      controller: _passwordCtrl,
      autofocus: true,
      obscureText: _obscurePassword,
      autofillHints: const [AutofillHints.newPassword],
      textInputAction: TextInputAction.done,
      decoration: _fieldDecoration(hint: '6자 이상 새 비밀번호').copyWith(
        // login sheet 비밀번호 필드와 동일한 보기/숨기기 토글.
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? '비밀번호 보기' : '비밀번호 숨기기',
          icon: FaIcon(
            _obscurePassword
                ? FontAwesomeIcons.eye
                : FontAwesomeIcons.eyeSlash,
            size: 18,
            color: AppTheme.textSecondary,
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      onSubmitted: _isLoading ? null : (_) => _savePassword(),
    ),
    const SizedBox(height: 16),
    PrimaryButton(label: '비밀번호 변경', busy: _isLoading, onPressed: _savePassword),
  ];

  Future<void> _savePassword() async {
    final password = _passwordCtrl.text;
    if (password.length < 6) {
      setState(() => _error = '6자 이상 비밀번호를 입력하세요');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final res = await ref.read(authProvider.notifier).updatePassword(password);
    if (!mounted) return;
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isLoading = false;
        _error = res.message ?? '변경에 실패했습니다';
      });
    }
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = '가입한 이메일 주소를 입력하세요');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final res = await ref
        .read(authProvider.notifier)
        .requestPasswordReset(email);
    if (!mounted) return;
    if (res.ok) {
      _startResendCooldown();
      setState(() {
        _step = _Step.otp;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _error = res.message ?? '전송에 실패했습니다';
      });
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldownSec = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_resendCooldownSec <= 1) {
        t.cancel();
        setState(() => _resendCooldownSec = 0);
      } else {
        setState(() => _resendCooldownSec -= 1);
      }
    });
  }

  Future<void> _verify() async {
    final token = _otpCtrl.text.trim();
    if (token.length != _kOtpLength) {
      setState(() => _error = '$_kOtpLength자리 코드를 입력하세요');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final res = await ref
        .read(authProvider.notifier)
        .verifyRecoveryOtp(_emailCtrl.text.trim(), token);
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        _step = _Step.newPassword;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _error = res.message ?? '인증에 실패했습니다';
      });
    }
  }
}

enum _Step { email, otp, newPassword }
