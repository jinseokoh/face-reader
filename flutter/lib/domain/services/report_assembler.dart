import 'package:facely/data/constants/archetype_text_blocks.dart';
import 'package:facely/data/constants/archetype_text_blocks_v2.dart';
import 'package:facely/data/constants/rule_text_blocks.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/domain/services/life_question_narrative.dart';

/// 조립된 본문 + 원본 rule block 참조.
/// `selectedBlocks` 는 UI 렌더링에서 직접 사용하지 않고,
/// 외부 디버그·내보내기 경로에서 fired rule snapshot 이 필요할 때 사용.
class AssembledReport {
  final String assembledText;
  final List<RuleTextBlock> selectedBlocks;

  const AssembledReport({
    required this.assembledText,
    required this.selectedBlocks,
  });
}

/// [narrativeVersion] 미지정 시 v1. 호출부가 `AppConfigService.instance
/// .narrativeVersion` 을 넘기면 원격 설정이 그대로 반영된다.
AssembledReport assembleReport(
  FaceReadingReport report, {
  NarrativeVersion narrativeVersion = NarrativeVersion.v1,
}) {
  final buf = StringBuffer();
  final isV2 = narrativeVersion == NarrativeVersion.v2;

  // Archetype intro (성별 분기)
  final intro = _archetypeIntro(report, isV2);
  if (intro.isNotEmpty) {
    buf.write(intro);
    buf.write('\n\n');
  }

  // 8 인생 질문 본문 (장점 → 단점 → 조언 구조)
  buf.write(assembleLifeQuestions(report, version: narrativeVersion));

  // 특수 관상 문장
  final special = report.archetype.specialArchetype;
  if (special != null) {
    final specialText =
        (isV2 ? specialArchetypeTextsV2 : specialArchetypeTexts)[special];
    if (specialText != null && specialText.isNotEmpty) {
      buf.write('\n\n');
      buf.write(specialText);
    }
  }

  // 나이대 마무리
  final closing =
      (isV2 ? ageClosingsV2 : ageClosings)[report.ageGroup.isOver50] ?? '';
  if (closing.isNotEmpty) {
    buf.write('\n\n');
    buf.write(closing);
  }

  // Fired rule block snapshot (외부 경로용)
  final triggeredIds = report.rules.map((r) => r.id).toSet();
  final selected = ruleTextBlocks.values
      .where((block) => triggeredIds.contains(block.ruleId))
      .toList();

  return AssembledReport(
    assembledText: buf.toString(),
    selectedBlocks: selected,
  );
}

// ─── Helpers ─────────────────────────────────────────────────────────────

String _archetypeIntro(FaceReadingReport report, bool isV2) {
  final label = report.archetype.primaryLabel;
  final genderMap = (isV2 ? archetypeIntrosV2 : archetypeIntros)[label];
  if (genderMap == null) return '';
  return genderMap[report.gender] ?? '';
}

