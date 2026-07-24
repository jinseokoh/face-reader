import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';

/// 아바타 border 색 SSOT — 카메라 촬영 사진은 gold, 앨범 사진(및 source
/// 미상·공유받음)은 lightGray(AppColors.border). 관상·궁합·케미·채팅 전 탭
/// 아바타가 동일 규칙 사용 (refine 관상 리스트도 같은 hex 로 맞춘다).
Color sourceBorderColor(AnalysisSource? source) =>
    source == AnalysisSource.camera ? AppColors.gold : AppColors.border;

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
          AnalysisSource.received => '공유받음',
        },
        style: AppText.hint.copyWith(color: AppColors.textHint),
      ),
    );
  }
}
