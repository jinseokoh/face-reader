import 'package:face_reader/core/theme.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
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
  bool _showEmail = false;
  bool _isSignUp = false;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _kakaoLogin() async {
    setState(() => _isLoading = true);
    final launched = await ref.read(authProvider.notifier).loginWithKakao();
    if (mounted) {
      Navigator.of(context).pop(launched);
    }
  }

  Future<void> _emailSubmit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일과 6자 이상 비밀번호를 입력하세요')),
      );
      return;
    }
    setState(() => _isLoading = true);
    final notifier = ref.read(authProvider.notifier);
    final success = _isSignUp
        ? await notifier.signUpWithEmail(email, password)
        : await notifier.loginWithEmail(email, password);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
      if (_isSignUp) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('가입 확인 메일을 확인해주세요')),
        );
      }
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isSignUp ? '가입 실패' : '로그인 실패')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '로그인이 필요합니다',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '앨범에 저장된 사진속 관상을 분석하거나, 관상 해석을 저장하는 기능을 이용하려면 로그인이 필요합니다.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  textAlign: TextAlign.left,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
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
                ),
                child: _isLoading && !_showEmail
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '카카오로 로그인',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => setState(() => _showEmail = !_showEmail),
              child: Text(
                _showEmail ? '닫기' : '이메일로 로그인',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
            if (_showEmail) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
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
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: '비밀번호 (6자 이상)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _emailSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.textPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading && _showEmail
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isSignUp ? '가입하기' : '로그인',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => setState(() => _isSignUp = !_isSignUp),
                child: Text(
                  _isSignUp ? '이미 계정이 있습니다' : '계정이 없으신가요? 가입하기',
                  style: TextStyle(color: AppTheme.textHint, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '첫 로그인 시 3코인 지급!',
              style: TextStyle(color: AppTheme.accent, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
