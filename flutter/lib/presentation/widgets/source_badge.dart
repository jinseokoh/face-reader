import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';

/// 카메라/앨범 source 표기용 outlined pill — 색 없이 border 만.
/// 관상 list / 궁합 list 양쪽에서 동일 위젯 사용 (DESIGN.md §0.0.1 통일성).
class SourceBadge extends StatelessWidget {
  final AnalysisSource source;
  const SourceBadge({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        switch (source) {
          AnalysisSource.camera => '카메라',
          AnalysisSource.album => '앨범',
          AnalysisSource.received => '받음',
        },
        style: AppText.hint.copyWith(color: AppColors.textHint),
      ),
    );
  }
}
