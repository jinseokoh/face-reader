import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 분석 진행 단계 (APPLE.md §54 1~3단계). 4·5단계는 리포트 본문의 섹션이다.
const List<String> kMeasureAnalysisStages = [
  '얼굴 측정 중',
  '얼굴 기하학 분석',
  '첫인상 분석',
];

/// 단계당 최소 표시 시간. 분석 자체는 이보다 빠르므로 흐름은 이 시간을 채운 뒤
/// 결과로 넘어간다 (§54 — 단순 "점수 생성" 으로 느끼지 않게).
const Duration kAnalysisStageStep = Duration(milliseconds: 800);

/// 정보 확인 화면 위에 덮이는 단계 표시 — 문구가 순서대로 바뀐다.
class AnalysisStageOverlay extends StatefulWidget {
  final List<String> stages;
  final Duration step;

  const AnalysisStageOverlay({
    super.key,
    this.stages = kMeasureAnalysisStages,
    this.step = kAnalysisStageStep,
  });

  @override
  State<AnalysisStageOverlay> createState() => _AnalysisStageOverlayState();
}

class _AnalysisStageOverlayState extends State<AnalysisStageOverlay> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.step, (t) {
      if (_index >= widget.stages.length - 1) {
        t.cancel();
        return;
      }
      setState(() => _index++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(widget.stages[_index], style: AppText.display),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${_index + 1} / ${widget.stages.length}',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }
}
