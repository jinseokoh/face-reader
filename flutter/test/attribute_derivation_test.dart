import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

AttributeBreakdown _run(
  Map<String, double> z, {
  Gender gender = Gender.male,
  bool isOver50 = false,
  bool hasLateral = false,
  Map<String, bool> flags = const {},
  FaceShape shape = FaceShape.unknown,
  double conf = 0.0,
}) {
  return deriveAttributeScoresDetailed(
    tree: scoreTree(z),
    gender: gender,
    isOver50: isOver50,
    hasLateral: hasLateral,
    lateralFlags: flags,
    faceShape: shape,
    shapeConfidence: conf,
  );
}

void main() {
  group('Stage 0 — face-shape preset (v2.2: retired)', () {
    // v2.2 (2026-04-18): 얼굴형 preset 이 raw score 에 주는 영향을 완전 제거.
    // FaceShape 는 archetype overlay + narrative 에만 반영. shapePreset 은
    // 모든 조합에서 항상 0 을 반환해야 한다.
    test('모든 shape × confidence 조합에서 shapePreset = 0', () {
      for (final shape in FaceShape.values) {
        for (final conf in [0.0, 0.5, 0.8, 1.0]) {
          final b = _run({}, shape: shape, conf: conf);
          for (final attr in Attribute.values) {
            expect(b.shapePreset[attr], 0.0,
                reason: 'shape=$shape conf=$conf attr=${attr.name} '
                    'must be 0 (preset retired)');
          }
        }
      }
    });
  });

  group('Stage 1 — base linear per-node', () {
    test('single-node metric flows into basePerNode', () {
      // nasalHeightRatio z=2.0 → nose ownMeanZ = 2.0 (2 frontal metric 중 1개만).
      // Actually nose has 2 frontal metrics; with only one metric supplied,
      // ownMeanZ = sum / count_of_PRESENT metrics = 2.0 / 1.
      final b = _run({'nasalHeightRatio': 2.0});
      final wealth = b.basePerNode[Attribute.wealth]!;
      // wealth.nose weight = 0.20, male delta +0.05 → 0.25 (v2.7 decorrelated).
      expect(wealth['nose'], closeTo(2.0 * 0.25, 1e-9));
    });

    test('gender delta changes effective weight', () {
      const z = {'nasalHeightRatio': 1.0};
      final male = _run(z, gender: Gender.male);
      final female = _run(z, gender: Gender.female);
      // wealth.nose: 0.20 + male +0.05 / female -0.05 (v2.7 decorrelated).
      expect(male.basePerNode[Attribute.wealth]!['nose'],
          closeTo(1.0 * 0.25, 1e-9));
      expect(female.basePerNode[Attribute.wealth]!['nose'],
          closeTo(1.0 * 0.15, 1e-9));
    });

    test('face root node 는 weight matrix 에서 제외', () {
      final b = _run({'faceAspectRatio': 1.0});
      for (final attr in Attribute.values) {
        expect(b.basePerNode[attr]!.containsKey('face'), isFalse,
            reason: '${attr.name} still has face entry');
      }
    });

    test('missing node contributes zero (no entry)', () {
      final b = _run({}); // empty
      for (final attr in Attribute.values) {
        final per = b.basePerNode[attr]!;
        for (final v in per.values) {
          expect(v, 0.0);
        }
      }
    });

    test('libido philtrum has negative polarity', () {
      // philtrumLength z=1.0 → philtrum mean 1.0, weight 0.15, polarity -1 (v2.6).
      final b = _run({'philtrumLength': 1.0});
      expect(b.basePerNode[Attribute.libido]!['philtrum'],
          closeTo(-1.0 * 0.15, 1e-9));
    });
  });

  group('Stage 1b — distinctiveness', () {
    test('attractiveness distinctiveness 철수 (v2.2) — 항상 0', () {
      // v2.2: monotonic/bell 모두 제거. attr 는 node + rule 로만 결정.
      final neutral = _run({'faceAspectRatio': 0.0});
      final moderate = _run({'faceAspectRatio': 0.7});
      final extreme = _run({
        'faceAspectRatio': 3.0,
        'eyeFissureRatio': 3.0,
        'mouthWidthRatio': 3.0,
      });
      expect(neutral.distinctiveness[Attribute.attractiveness], 0.0);
      expect(moderate.distinctiveness[Attribute.attractiveness], 0.0);
      expect(extreme.distinctiveness[Attribute.attractiveness], 0.0);
    });

    test('intelligence bonus requires upper abs > 0.5', () {
      final small = _run({'upperFaceRatio': 0.3});
      expect(small.distinctiveness[Attribute.intelligence], 0.0);
      final big = _run({'upperFaceRatio': 1.5});
      expect(big.distinctiveness[Attribute.intelligence]!, greaterThan(0.0));
    });

    test('emotionality bonus requires lower abs > 0.5', () {
      final small = _run({'gonialAngle': 0.2});
      expect(small.distinctiveness[Attribute.emotionality], 0.0);
      final big = _run({'gonialAngle': -1.8});
      expect(big.distinctiveness[Attribute.emotionality]!, greaterThan(0.0));
    });
  });

  group('Stage 2 — zone rules', () {
    test('Z-01 balanced three zones triggers stability bonus', () {
      final b = _run({
        'upperFaceRatio': 0.1,
        'eyeFissureRatio': 0.1,
        'gonialAngle': 0.1,
      });
      expect(b.zoneRules.map((r) => r.id), contains('Z-01'));
    });

    test('Z-02 upper-only dominance', () {
      final b = _run({
        'upperFaceRatio': 1.5,
        'foreheadWidth': 1.5,
      });
      expect(b.zoneRules.map((r) => r.id), contains('Z-02'));
    });

    test('Z-04 lower dominance boosts sensuality/libido and drops stability',
        () {
      final b = _run({
        'lowerFaceRatio': 1.5,
        'gonialAngle': 1.5,
        'chinAngle': 1.5,
        'philtrumLength': 1.5,
        'mouthWidthRatio': 1.5,
      });
      final ids = b.zoneRules.map((r) => r.id).toList();
      expect(ids, contains('Z-04'));
    });

    test('Z-05 upper-strong lower-weak antithesis', () {
      final b = _run({
        'upperFaceRatio': 1.5,
        'foreheadWidth': 1.5,
        'gonialAngle': -1.5,
        'chinAngle': -1.5,
        'philtrumLength': -1.5,
        'mouthWidthRatio': -1.5,
      });
      expect(b.zoneRules.map((r) => r.id), contains('Z-05'));
    });

    test('Z-07 full dominance lifts leadership', () {
      final b = _run({
        'upperFaceRatio': 1.5,
        'foreheadWidth': 1.5,
        'nasalHeightRatio': 1.5,
        'eyeFissureRatio': 1.5,
        'gonialAngle': 1.5,
        'chinAngle': 1.5,
      });
      expect(b.zoneRules.map((r) => r.id), contains('Z-07'));
    });

    test('Z-11 중정 비율 큼 (midFaceRatio ≥ 1)', () {
      final b = _run({'midFaceRatio': 1.2});
      expect(b.zoneRules.map((r) => r.id), contains('Z-11'));
    });

    test('Z-12 하정 비율 큼 (lowerFaceRatio ≥ 1)', () {
      final b = _run({'lowerFaceRatio': 1.2});
      expect(b.zoneRules.map((r) => r.id), contains('Z-12'));
    });

    test('Z-13 하정 비율 작음 (lowerFaceRatio ≤ -1)', () {
      final b = _run({'lowerFaceRatio': -1.2});
      expect(b.zoneRules.map((r) => r.id), contains('Z-13'));
    });
  });

  group('Stage 3 — organ rules', () {
    test('O-NM1 nose+mouth both strong boosts wealth', () {
      final b = _run({
        'nasalHeightRatio': 1.5,
        'mouthWidthRatio': 1.5,
        'lipFullnessRatio': 1.5,
      });
      expect(b.organRules.map((r) => r.id), contains('O-NM1'));
    });

    test('O-PH1 short philtrum triggers libido', () {
      final b = _run({'philtrumLength': -1.5});
      expect(b.organRules.map((r) => r.id), contains('O-PH1'));
    });

    test('O-EB1 eye+eyebrow both strong triggers leadership', () {
      final b = _run({
        'eyeFissureRatio': 1.5,
        'eyebrowThickness': 1.5,
      });
      expect(b.organRules.map((r) => r.id), contains('O-EB1'));
    });

    test('O-DC1 살짝 매부리 구간 [1.5, 3.0)', () {
      final mild = _run({'dorsalConvexity': 2.0});
      expect(mild.organRules.map((r) => r.id), contains('O-DC1'));
      // strong aquiline is L-AQ territory → O-DC1 stops at z=3.0
      final strong = _run({'dorsalConvexity': 3.2});
      expect(strong.organRules.map((r) => r.id), isNot(contains('O-DC1')));
      // below threshold → not fired
      final flat = _run({'dorsalConvexity': 1.0});
      expect(flat.organRules.map((r) => r.id), isNot(contains('O-DC1')));
    });

    test('O-DC2 살짝 오목 구간 (-3.0, -1.5]', () {
      final mild = _run({'dorsalConvexity': -2.0});
      expect(mild.organRules.map((r) => r.id), contains('O-DC2'));
      final strong = _run({'dorsalConvexity': -3.5});
      expect(strong.organRules.map((r) => r.id), isNot(contains('O-DC2')));
    });

    test('O-NF1 비전두각 큼 z ≥ 1.5', () {
      final b = _run({'nasofrontalAngle': 1.6});
      expect(b.organRules.map((r) => r.id), contains('O-NF1'));
    });

    test('O-NF2 비전두각 작음 z ≤ -1.5', () {
      final b = _run({'nasofrontalAngle': -1.6});
      expect(b.organRules.map((r) => r.id), contains('O-NF2'));
    });

    test('O-CK 광대 강 — leadership·wealth 가산', () {
      final b = _run({'cheekboneWidth': 1.5});
      final ids = b.organRules.map((r) => r.id);
      expect(ids, contains('O-CK'));
      // O-CK 하나만 발동 (조합 rule 은 nose/chin/forehead 없음)
      expect(ids, isNot(contains('O-CKN')));
      expect(ids, isNot(contains('O-CKC')));
      expect(ids, isNot(contains('O-CKF')));
    });

    test('O-CB 광대 약 — leadership 감점, sociability 가점', () {
      final b = _run({'cheekboneWidth': -1.5});
      expect(b.organRules.map((r) => r.id), contains('O-CB'));
    });

    test('O-CKN 광대+코 동반 강 — 중정 병립', () {
      final b = _run({
        'cheekboneWidth': 1.5,
        'nasalHeightRatio': 1.5,
      });
      final ids = b.organRules.map((r) => r.id);
      expect(ids, contains('O-CKN'));
      expect(ids, contains('O-CK'));
    });

    test('O-CKC 광대+턱 동반 강 — 중·하정 결합', () {
      final b = _run({
        'cheekboneWidth': 1.5,
        'chinAngle': 1.5,
      });
      expect(b.organRules.map((r) => r.id), contains('O-CKC'));
    });

    test('O-CKF 광대+이마 동반 강 — 관료·학자', () {
      final b = _run({
        'cheekboneWidth': 1.5,
        'foreheadWidth': 1.5,
      });
      expect(b.organRules.map((r) => r.id), contains('O-CKF'));
    });
  });

  group('Stage 4 — palace rules', () {
    test('P-01 nose+eye both strong', () {
      final b = _run({
        'nasalHeightRatio': 1.5,
        'eyeFissureRatio': 1.5,
      });
      expect(b.palaceRules.map((r) => r.id), contains('P-01'));
    });

    test('P-06 canthal tilt palace requires eye distinctive + tilt strong', () {
      final b = _run({
        'eyeCanthalTilt': 1.5,
        'intercanthalRatio': 1.0,
      });
      expect(b.palaceRules.map((r) => r.id), contains('P-06'));
    });

    test('P-09 명궁 넓음 — browSpacing z ≥ 1 → wealth·stability 가산', () {
      final b = _run({'browSpacing': 1.5});
      expect(b.palaceRules.map((r) => r.id), contains('P-09'));
    });

    test('P-09B 명궁 좁음 — browSpacing z ≤ -1 → emotionality 가산', () {
      final b = _run({'browSpacing': -1.5});
      expect(b.palaceRules.map((r) => r.id), contains('P-09B'));
    });

    test('P-09 중립 구간 |z|<1 은 미발동', () {
      final b = _run({'browSpacing': 0.5});
      final ids = b.palaceRules.map((r) => r.id);
      expect(ids, isNot(contains('P-09')));
      expect(ids, isNot(contains('P-09B')));
    });
  });

  group('Stage 5 — age gate', () {
    test('ageRules empty when isOver50 = false', () {
      final b = _run({
        'gonialAngle': -1.5,
        'lowerFaceRatio': -1.5,
        'chinAngle': -1.5,
        'philtrumLength': -1.5,
        'mouthWidthRatio': -1.5,
      });
      expect(b.ageRules, isEmpty);
    });

    test('A-01 fires when isOver50 and lower zone weak', () {
      final b = _run({
        'gonialAngle': -1.5,
        'lowerFaceRatio': -1.5,
        'chinAngle': -1.5,
        'philtrumLength': -1.5,
        'mouthWidthRatio': -1.5,
      }, isOver50: true);
      expect(b.ageRules.map((r) => r.id), contains('A-01'));
    });

    test('A-02 upper preserved bonus when isOver50', () {
      final b = _run({
        'upperFaceRatio': 1.0,
        'foreheadWidth': 1.0,
      }, isOver50: true);
      expect(b.ageRules.map((r) => r.id), contains('A-02'));
    });
  });

  group('Stage 5 — lateral flag gate', () {
    test('lateralRules empty when hasLateral = false', () {
      final b = _run({}, flags: {'aquilineNose': true});
      expect(b.lateralRules, isEmpty);
    });

    test('L-AQ fires with aquilineNose flag', () {
      final b =
          _run({}, hasLateral: true, flags: {'aquilineNose': true});
      expect(b.lateralRules.map((r) => r.id), contains('L-AQ'));
    });

    test('L-SN fires with snubNose flag', () {
      final b = _run({}, hasLateral: true, flags: {'snubNose': true});
      expect(b.lateralRules.map((r) => r.id), contains('L-SN'));
    });

    test('L-EL fires with both lip E-line metrics strong', () {
      final b = _run({
        'upperLipEline': 1.5,
        'lowerLipEline': 1.5,
      }, hasLateral: true);
      expect(b.lateralRules.map((r) => r.id), contains('L-EL'));
    });
  });

  group('Orchestrator — total integration', () {
    test('total is populated for all 10 attributes', () {
      final b = _run({'faceAspectRatio': 1.0});
      expect(b.total.keys.toSet(), Attribute.values.toSet());
    });

    test('empty metrics → base zero; balanced-zone rule may fire benignly', () {
      final b = _run({});
      // 모든 node base 기여 = 0 (no metrics).
      for (final attr in Attribute.values) {
        for (final v in b.basePerNode[attr]!.values) {
          expect(v, 0.0);
        }
      }
      // age/lateral gate 는 꺼져 있으므로 무조건 비어야 함.
      expect(b.ageRules, isEmpty);
      expect(b.lateralRules, isEmpty);
      // threshold 기반 rule (≥1.0, ≤-1.0) 는 발동 불가.
      final firedIds = [
        ...b.organRules,
        ...b.palaceRules,
      ].map((r) => r.id).toSet();
      expect(firedIds, isEmpty,
          reason: 'organ/palace rules require |z| ≥ 1.0 — empty must not fire');
      // total 은 유한값.
      for (final v in b.total.values) {
        expect(v.isFinite, isTrue);
      }
    });

    test('deriveAttributeScores() matches detailed.total', () {
      const z = {
        'nasalHeightRatio': 1.2,
        'mouthWidthRatio': 0.8,
        'gonialAngle': -0.3,
      };
      final tree = scoreTree(z);
      final flat = deriveAttributeScores(
        tree: tree,
        gender: Gender.male,
        isOver50: false,
        hasLateral: false,
      );
      final detailed = deriveAttributeScoresDetailed(
        tree: tree,
        gender: Gender.male,
        isOver50: false,
        hasLateral: false,
      );
      for (final attr in Attribute.values) {
        expect(flat[attr], closeTo(detailed.total[attr]!, 1e-12));
      }
    });

    test('breakdown sum consistency: total == shape + base + distinct + rules',
        () {
      final b = _run({
        'nasalHeightRatio': 1.5,
        'mouthWidthRatio': 1.5,
        'lipFullnessRatio': 1.5,
      }, shape: FaceShape.oval, conf: 1.0);
      for (final attr in Attribute.values) {
        final shape = b.shapePreset[attr] ?? 0.0;
        final baseSum = b.basePerNode[attr]!
            .values
            .fold<double>(0.0, (a, v) => a + v);
        final distinct = b.distinctiveness[attr] ?? 0.0;
        final ruleSum = [
          ...b.zoneRules,
          ...b.organRules,
          ...b.palaceRules,
          ...b.ageRules,
          ...b.lateralRules,
        ].fold<double>(0.0, (a, r) => a + (r.effects[attr] ?? 0.0));
        expect(b.total[attr],
            closeTo(shape + baseSum + distinct + ruleSum, 1e-9));
      }
    });
  });

  group('Breakdown debug path', () {
    test('topContributors returns sorted |value| entries', () {
      final b = _run({
        'nasalHeightRatio': 2.0, // nose strong
        'mouthWidthRatio': 1.5,
        'lipFullnessRatio': 1.5,
      });
      final top = b.topContributors(Attribute.wealth, n: 3);
      expect(top.length, lessThanOrEqualTo(3));
      // Sorted by |value| desc
      for (int i = 1; i < top.length; i++) {
        expect(top[i - 1].value.abs(),
            greaterThanOrEqualTo(top[i].value.abs() - 1e-9));
      }
    });

    test('topContributors skips near-zero node entries (|v| ≤ 0.05)', () {
      // very small input → node contributions all below threshold
      final b = _run({'nasalHeightRatio': 0.05});
      final top = b.topContributors(Attribute.wealth);
      for (final e in top) {
        expect(e.value.abs(), greaterThan(0.05));
      }
    });

    test('topContributors key prefixes distinguish sources', () {
      final b = _run({
        'nasalHeightRatio': 1.5,
        'mouthWidthRatio': 1.5,
        'lipFullnessRatio': 1.5,
      });
      final top = b.topContributors(Attribute.wealth, n: 10);
      final keys = top.map((e) => e.key).toList();
      expect(keys.any((k) => k.startsWith('node:')), isTrue);
      // O-NM1 fires for wealth
      expect(keys, contains('O-NM1'));
    });
  });

  group('Edge cases', () {
    test('unsupported ear node never appears in basePerNode', () {
      final b = _run({'intercanthalRatio': 1.0});
      for (final attr in Attribute.values) {
        expect(b.basePerNode[attr]!.containsKey('ear'), isFalse);
      }
    });

    test('empty metrics → glabella rule (P-09/P-09B) 미발동', () {
      final b = _run({});
      final allRuleIds = [
        ...b.zoneRules,
        ...b.organRules,
        ...b.palaceRules,
        ...b.ageRules,
        ...b.lateralRules,
      ].map((r) => r.id);
      expect(allRuleIds, isNot(contains('P-09')));
      expect(allRuleIds, isNot(contains('P-09B')));
    });

  });

  group('Prototype face sanity', () {
    test('"ideal wealth face" lands wealth in top half of attributes', () {
      // 관상 고전 재물 얼굴: 강한 코(재백궁)·이마(관록궁)·턱(노복궁) 삼위.
      // v2.7: mouth 계 metric 은 charm cluster 로 몰려 빼고, 재물 특화 signal 만.
      final b = _run({
        'nasalHeightRatio': 1.8,
        'nasalWidthRatio': -0.5,
        'foreheadWidth': 1.2,
        'upperFaceRatio': 1.0,
        'cheekboneWidth': 1.0,
        'gonialAngle': 1.0,
        'chinAngle': 1.0,
        'lowerFaceRatio': 0.8,
        'lowerFaceFullness': 0.8,
      });
      final ranked = b.total.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topHalf = ranked.take(5).map((e) => e.key).toSet();
      expect(topHalf, contains(Attribute.wealth),
          reason: 'ranked=${ranked.map((e) => '${e.key.name}:${e.value.toStringAsFixed(2)}').join(', ')}');
    });

    test('"ideal intelligence face" lands intelligence in top 3', () {
      // Strong forehead + eye + eyebrow, upper zone dominance.
      final b = _run({
        'upperFaceRatio': 1.5,
        'foreheadWidth': 1.5,
        'eyebrowThickness': 1.2,
        'eyebrowCurvature': 1.0,
        'eyeFissureRatio': 1.2,
        'eyeAspect': 1.0,
      });
      final ranked = b.total.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top3 = ranked.take(3).map((e) => e.key).toSet();
      expect(top3, contains(Attribute.intelligence));
    });
  });
}
