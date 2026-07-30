import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:facely/core/theme.dart';

/// 리스트 정렬 셀렉터 — 우측 정렬 "라벨 ▾" + PopupMenu (§2.5 공용 승격,
/// 2026-07-12. 궁합 미확인/확인에서 시작해 케미 그룹 리스트까지 공유).
class SortSelector<T> extends StatelessWidget {
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  /// 케미 내 그룹처럼 정렬이 아니라 상태 필터로 쓰일 땐 '필터'.
  final String tooltip;
  const SortSelector({
    super.key,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
    this.tooltip = '정렬',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        PopupMenuButton<T>(
          tooltip: tooltip,
          initialValue: value,
          padding: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          onSelected: onChanged,
          itemBuilder: (ctx) => values
              .map(
                (o) => PopupMenuItem<T>(
                  value: o,
                  child: Text(labelOf(o), style: AppText.body),
                ),
              )
              .toList(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labelOf(value),
                style: AppText.caption.copyWith(color: AppColors.textHint),
              ),
              const SizedBox(width: AppSpacing.sm),
              const FaIcon(
                FontAwesomeIcons.chevronDown,
                size: 12,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
