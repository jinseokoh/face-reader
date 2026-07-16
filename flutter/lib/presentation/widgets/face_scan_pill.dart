import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// AppBar 관상 촬영 pill — 관상·궁합·케미 탭 공유 (§2.5 공용 승격).
/// 설정 [충전하기]·[케미 그룹 시작] pill 과 동일한 outlined stadium 레시피.
///
/// 내 관상 미등록 = [내 관상 등록] → 내 관상 촬영 진입.
/// 등록 후 = [상대방 관상 추가] → 상대방 촬영. 케미 탭은 등록 후 자체
/// [케미 그룹 시작] pill 이 이 자리를 가지므로 미등록일 때만 넣는다.
/// 탭 = 즉시 카메라, 앨범은 카메라 화면 안 숏컷.
class FaceScanPill extends ConsumerWidget {
  const FaceScanPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMyFace = ref.watch(historyProvider).any((r) => r.isMyFace);
    return Center(
      child: GestureDetector(
        onTap: () => hasMyFace
            ? startOtherFaceCapture(context, ref)
            : startMyFaceCapture(context, ref),
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
            hasMyFace ? '상대방 관상 추가' : '내 관상 등록',
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
