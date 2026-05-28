import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 회원탈퇴 confirmation flow:
///   1) 안내 dialog (bullet list + 동의 checkbox + 탈퇴하기)
///   2) Loading
///   3) 성공 dialog ("완전히 삭제되었습니다" + 확인) → 자동 logout 된 상태
class AccountDeletionDialog {
  AccountDeletionDialog._();

  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ConfirmDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    final loadingCompleter = _showBlockingLoader(context);
    final result = await ref.read(authProvider.notifier).deleteAccount();
    loadingCompleter.complete();
    if (!context.mounted) return;

    if (result.ok) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          title: const Text('탈퇴가 완료되었습니다', style: AppText.modalTitle),
          content: const Text(
            '모든 데이터가 영구 삭제되었습니다.\n그동안 관상은 과학이다를 이용해 주셔서 감사합니다.',
            style: AppText.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? '탈퇴 처리 실패')),
      );
    }
  }

  static _LoaderHandle _showBlockingLoader(BuildContext context) {
    final completer = _LoaderHandle();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        completer._popCallback = () => Navigator.of(ctx).pop();
        return const Center(child: CircularProgressIndicator());
      },
    );
    return completer;
  }
}

class _LoaderHandle {
  VoidCallback? _popCallback;
  void complete() => _popCallback?.call();
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog();

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _agreed = false;

  static const _items = <String>[
    '남은 코인 전부 소실',
    '코인 사용기록 전부 삭제',
    '저장된 관상 기록 전부 삭제',
    '저장된 궁합 기록 전부 삭제',
    '얼굴 썸네일 전부 삭제',
    '재가입 시 보너스 코인 지급 없음',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      title: const Text('회원 탈퇴 안내', style: AppText.modalTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '회원 탈퇴 시 아래 항목이 영구 삭제되며 복구할 수 없습니다.',
            style: AppText.body,
          ),
          const SizedBox(height: 12),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: AppText.body),
                  Expanded(child: Text(item, style: AppText.body)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () => setState(() => _agreed = !_agreed),
            child: Row(
              children: [
                Checkbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  visualDensity: VisualDensity.compact,
                ),
                const Expanded(
                  child: Text(
                    '위 내용을 모두 확인했으며, 탈퇴에 동의합니다.',
                    style: AppText.body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            '취소',
            style: TextStyle(color: AppColors.textHint),
          ),
        ),
        TextButton(
          onPressed:
              _agreed ? () => Navigator.pop(context, true) : null,
          child: const Text(
            '탈퇴하기',
            style: TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    );
  }
}
