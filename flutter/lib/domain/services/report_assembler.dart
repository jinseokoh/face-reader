import 'package:face_reader/data/constants/archetype_text_blocks.dart';
import 'package:face_reader/data/constants/rule_text_blocks.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/life_question_narrative.dart';

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

AssembledReport assembleReport(FaceReadingReport report) {
  final buf = StringBuffer();

  // Archetype intro (성별 분기)
  final intro = _archetypeIntro(report);
  if (intro.isNotEmpty) {
    buf.write(intro);
    buf.write('\n\n');
  }

  // 8 인생 질문 본문 (장점 → 단점 → 조언 구조)
  buf.write(assembleLifeQuestions(report));

  // 특수 관상 문장
  final special = report.archetype.specialArchetype;
  if (special != null) {
    final specialText = specialArchetypeTexts[special];
    if (specialText != null && specialText.isNotEmpty) {
      buf.write('\n\n');
      buf.write(specialText);
    }
  }

  // 나이대 마무리
  final closing = ageClosings[report.ageGroup.isOver50] ?? '';
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

String _archetypeIntro(FaceReadingReport report) {
  final label = report.archetype.primaryLabel;
  final genderMap = archetypeIntros[label];
  if (genderMap == null) return '';
  return genderMap[report.gender] ?? '';
}

