import 'dart:async';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 이메일 가입 후 발송된 6자리 OTP 를 사용자가 입력해 본인 인증을 마치는
/// modal sheet.
///
/// Supabase user-enumeration 방어 — 이미 가입된 이메일로 signUp 해도 메일
/// 발송 안 되고 signUp 자체는 가짜 success 응답. 사용자가 OTP sheet 에서
/// 코드를 영영 못 받는 상황 발생 → "로그인으로 전환" 버튼을 명시 노출해
/// 막다른 길 차단.
///
/// 60초 cooldown 동안 재전송 disabled. cooldown 끝나면 "이메일 재전송" 활성.
Future<OtpSheetResult> showOtpVerificationSheet(
  BuildContext context,
  WidgetRef ref, {
  required String email,
}) async {
  final result = await showModalBottomSheet<OtpSheetResult>(
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
  return result ?? OtpSheetResult.cancelled;
}

/// OTP 시트의 결과. 부모(login_bottom_sheet)가 다음 행동을 정한다.
///
///   • verified — 인증 성공, 부모도 pop(true)
///   • cancelled — 사용자가 취소, 부모는 그대로 유지
///   • switchToLogin — "이미 가입한 계정이라면" 인지하고 로그인 모드로
///     전환 요청. 부모는 segmented control 을 로그인으로 setState.
enum OtpSheetResult { verified, cancelled, switchToLogin }

class _OtpSheet extends ConsumerStatefulWidget {
  final String email;
  const _OtpSheet({required this.email});

  @override
  ConsumerState<_OtpSheet> createState() => _OtpSheetState();
}

class _OtpSheetState extends ConsumerState<_OtpSheet> {
  static const _kOtpLength = 6; // Supabase 대시보드 OTP 길이와 동기.
  final _otpCtrl = TextEditingController();
  bool _isLoading = false;

  String? _error;
  Timer? _resendTimer;

  int _resendCooldownSec = 60;

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
                    const TextSpan(text: ' 으로 코드를 보냈습니다.'),
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
                  LengthLimitingTextInputFormatter(_kOtpLength),
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
                  hintText: '0' * _kOtpLength,
                  hintStyle: TextStyle(
                    color: AppTheme.textHint,
                    letterSpacing: 4,
                  ),
                  // 48px 높이로 맞춰 아래 "인증하기" 버튼과 동일 비주얼
                  // 가중치. default Material content padding (~16 vertical)
                  // 이 56px+ 만들어 button(48) 보다 커보이던 문제 해소.
                  isCollapsed: false,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _error,
                ),
                onChanged: (v) {
                  if (v.length == _kOtpLength && !_isLoading) _verify();
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
                        : () => Navigator.of(context)
                            .pop(OtpSheetResult.cancelled),
                    child: Text(
                      '취소',
                      style:
                          TextStyle(color: AppTheme.textHint, fontSize: 13),
                    ),
                  ),
                ],
              ),
              // Supabase user-enumeration 방어로 이미 가입된 이메일엔 OTP 가
              // 안 발송됨. 사용자가 막다른 길에 빠지지 않도록 명시 전환 경로.
              // "이미 가입했나요?" 는 login sheet 의 "처음이신가요?" hint 와
              // 동일 톤 (textHint·12px), "로그인으로 이동" 은 inline clickable.
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  style: TextStyle(
                      color: AppTheme.textHint, fontSize: 12, height: 1.5),
                  children: [
                    const TextSpan(text: '이미 가입했나요? '),
                    TextSpan(
                      text: '로그인으로 이동',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: _isLoading
                          ? null
                          : (TapGestureRecognizer()
                            ..onTap = () => Navigator.of(context)
                                .pop(OtpSheetResult.switchToLogin)),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '메일이 오지 않으면 스팸함을 확인하거나 재전송 버튼을 눌러주세요.\n'
                '이미 가입된 이메일이면 코드가 발송되지 않을 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textHint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
  }

  Future<void> _resend() async {
    debugPrint('[OtpSheet._resend] requested cooldown=$_resendCooldownSec '
        'loading=$_isLoading');
    if (_resendCooldownSec > 0 || _isLoading) {
      debugPrint('[OtpSheet._resend] skipped (cooldown or loading)');
      return;
    }
    setState(() => _isLoading = true);
    final res =
        await ref.read(authProvider.notifier).resendEmailOtp(widget.email);
    debugPrint('[OtpSheet._resend] ok=${res.ok} msg=${res.message}');
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일을 다시 발송했습니다')),
      );
      _startResendCooldown();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? '재전송 실패')),
      );
    }
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
    debugPrint('[OtpSheet._verify] start email=${widget.email} '
        'tokenLen=${token.length}');
    if (token.length != _kOtpLength) {
      debugPrint('[OtpSheet._verify] reject: token not $_kOtpLength digits');
      setState(() => _error = '$_kOtpLength자리 코드를 입력하세요');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final res = await ref
        .read(authProvider.notifier)
        .verifyEmailOtp(widget.email, token);
    debugPrint('[OtpSheet._verify] ok=${res.ok} msg=${res.message}');
    if (!mounted) return;
    if (res.ok) {
      Navigator.of(context).pop(OtpSheetResult.verified);
    } else {
      setState(() {
        _isLoading = false;
        _error = res.message ?? '인증 실패';
      });
    }
  }
}
