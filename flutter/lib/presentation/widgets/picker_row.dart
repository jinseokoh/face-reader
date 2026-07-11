import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:facely/core/theme.dart';

/// select bar SSOT — surface 컨테이너 + (label)/value + chevronDown.
/// info_confirm(인종·성별·나이대)과 교감도 생성 페이지(모임 유형)가 공유.
/// 탭 → [showWheelPicker] 로 Cupertino 휠 픽커 모달.
/// [label] null 이면 value 가 좌측 정렬 단독 표시 (placeholder select 형).
/// [placeholder] true 면 미선택 상태 — value 를 hint 색으로.
class PickerRow extends StatelessWidget {
  final String? label;
  final String value;
  final VoidCallback onTap;
  final bool placeholder;
  // 추론 진행 중 — value 자리에 spinner + "추정 중..." (info_confirm 전용).
  final bool inferring;

  const PickerRow({
    super.key,
    this.label,
    required this.value,
    required this.onTap,
    this.placeholder = false,
    this.inferring = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: placeholder
          ? AppText.body.copyWith(color: AppColors.textHint)
          : AppText.body.copyWith(fontWeight: FontWeight.w600),
    );
    final spinner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.textHint),
          ),
        ),
        const SizedBox(width: 8),
        Text('추정 중...',
            style: AppText.body.copyWith(
                color: AppColors.textHint, fontWeight: FontWeight.w500)),
      ],
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            if (label != null) ...[
              Text(label!,
                  style:
                      AppText.body.copyWith(color: AppColors.textSecondary)),
              const Spacer(),
              if (inferring) spinner else valueText,
            ] else
              Expanded(child: inferring ? spinner : valueText),
            const SizedBox(width: 6),
            const FaIcon(FontAwesomeIcons.chevronDown,
                color: AppColors.textHint, size: 12),
          ],
        ),
      ),
    );
  }
}

/// Cupertino 휠 픽커 모달 — 선택값을 반환 (취소 시 null).
Future<T?> showWheelPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T current,
  required String Function(T) labelOf,
}) {
  var tempIndex = values.indexOf(current);
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => Container(
      height: 280,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('취소',
                      style: TextStyle(color: AppColors.textHint)),
                  onPressed: () => Navigator.pop(ctx),
                ),
                Text(title, style: AppText.sectionTitle),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('확인',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  onPressed: () => Navigator.pop(ctx, values[tempIndex]),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Expanded(
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                  initialItem: values.indexOf(current)),
              itemExtent: 40,
              onSelectedItemChanged: (index) => tempIndex = index,
              children: values
                  .map((v) => Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          child: Text(labelOf(v),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              // 토큰 1 step 아래(18→16) — sectionTitle 사이즈,
                              // 휠 안에선 w400 유지.
                              style: AppText.sectionTitle.copyWith(
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.textPrimary)),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
}
