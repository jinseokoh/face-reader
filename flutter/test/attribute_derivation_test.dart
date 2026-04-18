import 'package:face_reader/data/enums/attribute.dart';
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
}) {
  return deriveAttributeScoresDetailed(
    tree: scoreTree(z),
    gender: gender,
    isOver50: isOver50,
    hasLateral: hasLateral,
    lateralFlags: flags,
  );
}

void main() {
  group('Stage 1 — base linear per-node', () {
    test('single-node metric flows into basePerNode', () {
      final b = _run({'nasalHeightRatio': 2.0});
      // nose gets nasalHeightRatio only → ownMeanZ = 2.0
      final wealth = b.basePerNode[Attribute.wealth]!;
      // weight nose @ wealth = 0.50 (male no delta on nose wealth → +0.05 = 0.55)
      expect(wealth['nose'], closeTo(2.0 * 0.55, 1e-9));
    });

    test('gender delta changes effective weight', () {
      const z = {'nasalHeightRatio': 1.0};
      final male = _run(z, gender: Gender.male);
      final female = _run(z, gender: Gender.female);
      // wealth.nose: male +0.05, female -0.05
      expect(male.basePerNode[Attribute.wealth]!['nose'],
          closeTo(1.0 * 0.55, 1e-9));
      expect(female.basePerNode[Attribute.wealth]!['nose'],
          closeTo(1.0 * 0.45, 1e-9));
    });

    test('proximity path used for face node in wealth', () {
      // faceAspectRatio alone → face.ownMeanZ = 1.0, proximity = (2-1)*1 = 1.0
      final b = _run({'faceAspectRatio': 1.0});
      expect(
          b.basePerNode[Attribute.wealth]!['face'], closeTo(1.0 * 0.15, 1e-9));
      // z=0 proximity = 0
      final z0 = _run({'faceAspectRatio': 0.0});
      expect(z0.basePerNode[Attribute.wealth]!['face'] ?? 0.0, 0.0);
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
      // philtrumLength z=1.0 → philtrum mean 1.0, weight 0.40, polarity -1.
      final b = _run({'philtrumLength': 1.0});
      expect(b.basePerNode[Attribute.libido]!['philtrum'],
          closeTo(-1.0 * 0.40, 1e-9));
    });
  });

  group('Stage 1b — distinctiveness', () {
    test('attractiveness penalty grows with face roll-up abs-z', () {
      // Pure extreme face → negative attractiveness distinctiveness
      final b = _run({'faceAspectRatio': 2.0});
      expect(b.distinctiveness[Attribute.attractiveness]!, lessThan(0.0));
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

    test('P-09 명궁 never triggers (glabella metric gap)', () {
      final b = _run({
        'upperFaceRatio': 2.0,
        'foreheadWidth': 2.0,
        'eyebrowThickness': 2.0,
        'nasalHeightRatio': 2.0,
      });
      expect(b.palaceRules.map((r) => r.id), isNot(contains('P-09')));
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

    test('breakdown sum consistency: total == base + distinct + rules', () {
      final b = _run({
        'nasalHeightRatio': 1.5,
        'mouthWidthRatio': 1.5,
        'lipFullnessRatio': 1.5,
      });
      for (final attr in Attribute.values) {
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
        expect(b.total[attr], closeTo(baseSum + distinct + ruleSum, 1e-9));
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

    test('no rule targets glabella directly (P-09 skipped)', () {
      final b = _run({});
      final allRuleIds = [
        ...b.zoneRules,
        ...b.organRules,
        ...b.palaceRules,
        ...b.ageRules,
        ...b.lateralRules,
      ].map((r) => r.id);
      expect(allRuleIds, isNot(contains('P-09')));
    });

    test('proximity saturates: extreme z diminishes vs moderate', () {
      // face z=0.5 → proximity = (2-0.5)*0.5 = 0.75 (peak near ±1)
      // face z=3.0 → proximity = (2-3)*3 = -3.0 (flips sign past |z|=2)
      final mod = _run({'faceAspectRatio': 0.5});
      final ext = _run({'faceAspectRatio': 3.0});
      // wealth uses proximity for face: mod should be positive, ext negative
      expect(mod.basePerNode[Attribute.wealth]!['face']!, greaterThan(0.0));
      expect(ext.basePerNode[Attribute.wealth]!['face']!, lessThan(0.0));
    });
  });

  group('Prototype face sanity', () {
    test('"ideal wealth face" lands wealth in top half of attributes', () {
      // Strong nose, strong mouth, solid chin, balanced face.
      final b = _run({
        'nasalHeightRatio': 1.5,
        'nasalWidthRatio': -0.3, // slim nose = positive on width-polarity
        'mouthWidthRatio': 1.2,
        'lipFullnessRatio': 1.0,
        'gonialAngle': 0.8,
        'chinAngle': 0.8,
        'lowerFaceRatio': 0.8,
        'faceAspectRatio': 0.5,
        'faceTaperRatio': 0.5,
      });
      final ranked = b.total.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topHalf = ranked.take(5).map((e) => e.key).toSet();
      expect(topHalf, contains(Attribute.wealth));
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
