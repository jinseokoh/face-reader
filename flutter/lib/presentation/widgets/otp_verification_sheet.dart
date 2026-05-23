import 'dart:async';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 이메일 가입 후 발송된 6자리 OTP 를 사용자가 입력해 본인 인증을 마치는
/// modal sheet. 성공 시 true 반환 → 호출자(login_bottom_sheet)가 자기
/// sheet 도 pop(true) 처리.
///
/// 60초 cooldown 동안 재전송 disabled. cooldown 끝나면 "이메일 재전송" 활성.
/// dismiss 시 false 반환 — 가입은 Supabase 에 이미 됐으므로 사용자는
/// 나중에 같은 email/pw 로 로그인 + OTP 재전송으로 마저 진행 가능.
Future<bool> showOtpVerificationSheet(
  BuildContext context,
  WidgetRef ref, {
  required String email,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false, // 실수로 닫히지 않도록 — 명시적 "취소" 만.
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(ctx).bottom,
      ),
      child: _OtpSheet(email: email),
    ),
  );
  return result ?? false;
}

class _OtpSheet extends ConsumerStatefulWidget {
  final String email;
  const _OtpSheet({required this.email});

  @override
  ConsumerState<_OtpSheet> createState() => _OtpSheetState();
}

class _OtpSheetState extends ConsumerState<_OtpSheet> {
  final _otpCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Timer? _resendTimer;
  int _resendCooldownSec = 60;

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    setState(() => _resendCooldownSec = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldownSec--;
        if (_resendCooldownSec <= 0) {
          t.cancel();
          _resendCooldownSec = 0;
        }
      });
    });
  }

  Future<void> _verify() async {
    final token = _otpCtrl.text.trim();
    if (token.length != 6) {
      setState(() => _error = '6자리 코드를 입력하세요');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final success = await ref
        .read(authProvider.notifier)
        .verifyEmailOtp(widget.email, token);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isLoading = false;
        _error = '인증 실패 — 코드를 다시 확인해주세요';
      });
    }
  }

  Future<void> _resend() async {
    if (_resendCooldownSec > 0 || _isLoading) return;
    setState(() => _isLoading = true);
    final success =
        await ref.read(authProvider.notifier).resendEmailOtp(widget.email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일을 다시 발송했습니다')),
      );
      _startResendCooldown();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재전송 실패 — 잠시 후 다시 시도')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '이메일 인증',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      height: 1.5),
                  children: [
                    TextSpan(
                      text: widget.email,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(
                        text: ' 으로 코드를 보냈습니다.\n메일을 확인해 코드를 입력해주세요.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 이메일/비번 필드와 동일한 비주얼 가중치 — letter-spacing 만
              // 살짝 줘서 6자리 숫자가 자연스럽게 보이도록.
              TextField(
                controller: _otpCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                autofillHints: const [AutofillHints.oneTimeCode],
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                ),
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: TextStyle(
                    color: AppTheme.textHint,
                    letterSpacing: 4,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _error,
                ),
                onChanged: (v) {
                  if (v.length == 6 && !_isLoading) _verify();
                },
                onSubmitted: _isLoading ? null : (_) => _verify(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.textPrimary,
                    foregroundColor: Colors.white,
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
                      : const Text('인증하기',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 4),
              // 재전송 · 취소 한 Row — 보조 액션 둘이 같은 무게라 같은 줄.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _resendCooldownSec > 0 || _isLoading
                        ? null
                        : _resend,
                    child: Text(
                      _resendCooldownSec > 0
                          ? '재전송 가능까지 $_resendCooldownSec 초'
                          : '이메일 재전송',
                      style: TextStyle(
                        color: _resendCooldownSec > 0
                            ? AppTheme.textHint
                            : AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(
                      '취소',
                      style:
                          TextStyle(color: AppTheme.textHint, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '메일이 오지 않으면 스팸함을 확인하거나 재전송 버튼을 눌러주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textHint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
