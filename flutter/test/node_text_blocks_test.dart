// 14-node × 3-band 관상 해석 본문 SSOT sanity.
//
// - 14 노드 전부 high/mid/low 3 band 보유.
// - 각 band 본문(shared or male or female) ≥ 120자 (ear 는 예외).
// - 성별 분기 4 node 는 high/low band 에서 male·female 모두 제공.
// - metricDisplayLabels 가 physiognomy_tree 의 모든 metric 을 커버.
//
// Run via: flutter test test/node_text_blocks_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/node_text_blocks.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/physiognomy_tree.dart';

void main() {
  const genderSplitNodes = {'eye', 'nose', 'mouth', 'cheekbone'};
  const unsupportedNodes = {'ear'};

  test('14 노드 × 3 band 전부 존재', () {
    expect(nodeTextBlocks.length, 14,
        reason: 'all 14 tree nodes must have entries');
    for (final node in allNodes) {
      final set = nodeTextBlocks[node.id];
      expect(set, isNotNull, reason: 'missing NodeTextSet for ${node.id}');
    }
  });

  test('각 band 본문 최소 길이 기준 충족 (ear 제외)', () {
    // high/low = 200자 이상 (핵심 해석), mid = 100자 이상 (간결한 균형형).
    for (final entry in nodeTextBlocks.entries) {
      if (unsupportedNodes.contains(entry.key)) continue;
      for (final case_ in [
        ('high', entry.value.high, 120),
        ('mid', entry.value.mid, 100),
        ('low', entry.value.low, 120),
      ]) {
        final (name, block, floor) = case_;
        final male = resolveNodeBody(block, Gender.male);
        final female = resolveNodeBody(block, Gender.female);
        expect(male.length, greaterThanOrEqualTo(floor),
            reason: '${entry.key}/$name male body too short (${male.length})');
        expect(female.length, greaterThanOrEqualTo(floor),
            reason:
                '${entry.key}/$name female body too short (${female.length})');
      }
    }
  });

  test('성별 분기 4 node 는 high/low band 에서 male·female 본문 제공', () {
    for (final nodeId in genderSplitNodes) {
      final set = nodeTextBlocks[nodeId]!;
      for (final band in [set.high, set.low]) {
        expect(band.male, isNotNull,
            reason: '$nodeId high/low band missing male text');
        expect(band.female, isNotNull,
            reason: '$nodeId high/low band missing female text');
        expect(band.male != band.female, isTrue,
            reason: '$nodeId male/female bodies identical');
      }
    }
  });

  test('metricDisplayLabels 가 tree metric 전부 커버', () {
    for (final metricId in nodeByMetricId.keys) {
      expect(metricDisplayLabels.containsKey(metricId), isTrue,
          reason: 'metricDisplayLabels missing $metricId');
    }
  });

  test('nodeBlockForZ band 경계 (z ≥ +1.0 → high, z ≤ -1.0 → low)', () {
    final highBlock = nodeBlockForZ('forehead', 1.5);
    final midBlock = nodeBlockForZ('forehead', 0.0);
    final lowBlock = nodeBlockForZ('forehead', -1.5);
    expect(highBlock, isNotNull);
    expect(midBlock, isNotNull);
    expect(lowBlock, isNotNull);
    expect(highBlock != midBlock, isTrue);
    expect(lowBlock != midBlock, isTrue);

    // 경계 정확: z=1.0 은 high, z=0.99 는 mid, z=-1.0 은 low.
    expect(nodeBlockForZ('forehead', 1.0), same(nodeTextBlocks['forehead']!.high));
    expect(nodeBlockForZ('forehead', 0.99), same(nodeTextBlocks['forehead']!.mid));
    expect(nodeBlockForZ('forehead', -1.0), same(nodeTextBlocks['forehead']!.low));
  });

  test('unknown nodeId 는 null 반환', () {
    expect(nodeBlockForZ('nonexistent', 0.0), isNull);
  });

  test('resolveNodeBody — male override 가 shared 보다 우선', () {
    const block = NodeTextBlock(
      shared: 'shared-text',
      male: 'male-text',
      female: 'female-text',
    );
    expect(resolveNodeBody(block, Gender.male), 'male-text');
    expect(resolveNodeBody(block, Gender.female), 'female-text');

    const sharedOnly = NodeTextBlock(shared: 'shared-only');
    expect(resolveNodeBody(sharedOnly, Gender.male), 'shared-only');
    expect(resolveNodeBody(sharedOnly, Gender.female), 'shared-only');
  });
}
