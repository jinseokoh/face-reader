import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [상대방 관상 추가] AppBar pill — 관상·궁합 탭 공유 (§2.5 공용 승격).
/// 설정 [충전하기]·궁합 등록 pill 과 동일한 outlined stadium 레시피.
/// 탭 = 즉시 카메라 (내 관상 등록과 동일 UX, 앨범은 카메라 화면 안 숏컷).
/// 내 관상 등록 후에만 노출 — 미등록 상태의 진입은 등록 nudge 가 전담.
class OtherFaceScanPill extends ConsumerWidget {
  const OtherFaceScanPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMyFace = ref.watch(historyProvider).any((r) => r.isMyFace);
    if (!hasMyFace) return const SizedBox.shrink();
    return Center(
      child: GestureDetector(
        onTap: () => startOtherFaceCapture(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.textPrimary),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '상대방 관상 추가',
            style: AppText.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
