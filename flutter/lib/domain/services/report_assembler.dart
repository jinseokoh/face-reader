import 'package:face_reader/data/constants/archetype_text_blocks.dart';
import 'package:face_reader/data/constants/rule_text_blocks.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';

class AssembledReport {
  final String assembledText;
  final List<RuleTextBlock> selectedBlocks;

  const AssembledReport({
    required this.assembledText,
    required this.selectedBlocks,
  });
}

AssembledReport assembleReport(FaceReadingReport report) {
  // Step 1: Collect text blocks for triggered rules
  final triggeredIds = report.rules.map((r) => r.id).toSet();
  final matchedBlocks = ruleTextBlocks.values
      .where((block) => triggeredIds.contains(block.ruleId))
      .toList();

  if (matchedBlocks.isEmpty) {
    // No triggered rules — return minimal report with just archetype intro
    final intro = _archetypeIntro(report);
    final closing = ageClosings[report.ageGroup.isOver50] ?? '';
    return AssembledReport(
      assembledText: [intro, closing].where((s) => s.isNotEmpty).join('\n\n'),
      selectedBlocks: const [],
    );
  }

  // Step 2: Group blocks by attribute, sort groups by attribute score (descending)
  final blocksByAttribute = <Attribute, List<RuleTextBlock>>{};
  for (final block in matchedBlocks) {
    final attr = _attributeFromString(block.attribute);
    if (attr == null) continue;
    blocksByAttribute.putIfAbsent(attr, () => []).add(block);
  }

  // Sort attributes by their score descending
  final sortedAttributes = blocksByAttribute.keys.toList()
    ..sort((a, b) {
      final scoreA = report.attributeScores[a] ?? 0.0;
      final scoreB = report.attributeScores[b] ?? 0.0;
      return scoreB.compareTo(scoreA);
    });

  // Step 3: Select top 5 attributes only
  final topAttributes = sortedAttributes.take(5).toList();

  // Collect selected blocks in top-attribute order
  final selectedBlocks = <RuleTextBlock>[];
  for (final attr in topAttributes) {
    selectedBlocks.addAll(blocksByAttribute[attr]!);
  }

  // Step 4: Assemble text
  final buffer = StringBuffer();

  // Archetype intro
  final intro = _archetypeIntro(report);
  if (intro.isNotEmpty) {
    buffer.write(intro);
  }

  // Attribute sections
  for (final attr in topAttributes) {
    final blocks = blocksByAttribute[attr]!;
    buffer.write('\n\n## ${attr.labelKo}');
    for (final block in blocks) {
      buffer.write('\n${block.bodyKo}');
    }
  }

  // Special archetype text (if any)
  final special = report.archetype.specialArchetype;
  if (special != null) {
    final specialText = specialArchetypeTexts[special];
    if (specialText != null && specialText.isNotEmpty) {
      buffer.write('\n\n$specialText');
    }
  }

  // Age closing
  final closing = ageClosings[report.ageGroup.isOver50] ?? '';
  if (closing.isNotEmpty) {
    buffer.write('\n\n$closing');
  }

  // Step 5: Return
  return AssembledReport(
    assembledText: buffer.toString(),
    selectedBlocks: selectedBlocks,
  );
}

// ─── Helpers ───

String _archetypeIntro(FaceReadingReport report) {
  final label = report.archetype.primaryLabel;
  final genderMap = archetypeIntros[label];
  if (genderMap == null) return '';
  return genderMap[report.gender] ?? '';
}

Attribute? _attributeFromString(String value) {
  for (final attr in Attribute.values) {
    if (attr.name == value) return attr;
  }
  return null;
}
