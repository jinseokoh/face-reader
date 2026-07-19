import 'package:flutter/material.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../widgets/compact_snack_bar.dart';

/// 설정 > 차단 목록 — 차단 상대 닉네임 + [해제]. 해제하면 다시 같은
/// 매칭방 참가가 가능해진다 (재차단은 매칭 채팅에서만 가능하므로 확인
/// 다이얼로그를 거친다).
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _service = BattleService.instance;
  List<BlockedUser> _blocked = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final blocked = await _service.fetchBlockedUsers();
    if (!mounted) return;
    setState(() {
      _blocked = blocked;
      _loading = false;
    });
  }

  Future<void> _unblock(BlockedUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('차단 해제', style: AppText.modalTitle),
        content: Text(
          '${user.nickname}님과 다시 같은 매칭방에 참가할 수 있게 됩니다.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '취소',
              style: AppText.body.copyWith(color: AppColors.textHint),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '해제',
              style: AppText.body.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.unblockUser(user.userId);
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.success(message: '차단을 해제했습니다'),
        );
        await _load();
      }
    } catch (_) {
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: '잠시 후 다시 시도해 주세요'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('차단 목록')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _blocked.isEmpty
            ? const Center(child: Text('차단한 사용자가 없습니다', style: AppText.hint))
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: _blocked.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (ctx, i) {
                  final user = _blocked[i];
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.nickname,
                            style: AppText.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        GestureDetector(
                          onTap: () => _unblock(user),
                          child: Text(
                            '해제',
                            style: AppText.caption.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
