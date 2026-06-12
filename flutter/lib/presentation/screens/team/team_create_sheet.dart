import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/presentation/providers/team_provider.dart';

/// 교감도 생성 바텀시트 — PIVOT A6 채택안 B.
/// 모임명 한 줄 + 제안 칩 → [만들기] → 즉시 팀 생성. 모드 선택 없음.
/// 반환: 생성된 TeamRoom (취소 시 null).
Future<TeamRoom?> showTeamCreateSheet(
  BuildContext context,
  WidgetRef ref, {
  required String ownerReportId,
}) {
  return showModalBottomSheet<TeamRoom>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _TeamCreateSheet(ownerReportId: ownerReportId),
  );
}

class _TeamCreateSheet extends ConsumerStatefulWidget {
  final String ownerReportId;

  const _TeamCreateSheet({required this.ownerReportId});

  @override
  ConsumerState<_TeamCreateSheet> createState() => _TeamCreateSheetState();
}

class _TeamCreateSheetState extends ConsumerState<_TeamCreateSheet> {
  static const _suggestions = ['회식', 'MT', '동아리', '가족', '스터디'];

  final TextEditingController _controller = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('교감도 만들기', style: AppText.modalTitle),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 20,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: '모임 이름 (예: 마케팅팀 회식)',
              hintStyle: AppText.body.copyWith(color: AppColors.textHint),
              counterText: '',
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
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
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in _suggestions)
                InkWell(
                  onTap: () => setState(() => _controller.text = s),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm + 2,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.border),
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
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: '만들기',
            onPressed: _creating ? null : _create,
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _creating) return;
    setState(() => _creating = true);
    final room = await ref.read(teamsProvider.notifier).create(
          title: title,
          ownerReportId: widget.ownerReportId,
        );
    if (!mounted) return;
    Navigator.of(context).pop(room);
  }
}
