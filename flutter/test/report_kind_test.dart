// 카드 종류(ReportKind) — measure/physiognomy 를 섞지 않는 분기 규칙.

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/edition.dart';

import 'support/fake_report.dart';

void main() {
  test('parse — physiognomy 만 physiognomy, 없거나 다른 값은 measure', () {
    expect(ReportKind.parse('physiognomy'), ReportKind.physiognomy);
    expect(ReportKind.parse('measure'), ReportKind.measure);
    expect(ReportKind.parse(null), ReportKind.measure);
  });

  test('body 왕복 — kind 보존', () {
    final r = fakeReport(Random(3), gender: Gender.male, age: AgeGroup.values[1]);
    final body = jsonDecode(r.toBodyJson()) as Map<String, dynamic>;
    expect(body['kind'], 'measure');
    body['kind'] = 'physiognomy';
    final back = FaceReadingReport.fromJsonString(jsonEncode(body));
    expect(back.kind, ReportKind.physiognomy);
    expect(back.isMeasure, isFalse);
  });

  test('화면 분기 — 카드 종류 우선, measure 에디션은 항상 measure', () {
    final m = fakeReport(Random(1), gender: Gender.male, age: AgeGroup.values[1]);
    final p = FaceReadingReport.fromJsonString(
        m.toBodyJson().replaceFirst('"kind":"measure"', '"kind":"physiognomy"'));
    expect(showMeasureView(m), isTrue);
    expect(showMeasurePair(m, p), isTrue);
    expect(showMeasurePair(p, m), isTrue);
    // physiognomy 카드끼리는 에디션이 정한다.
    expect(showMeasureView(p), kMeasureEdition);
    expect(showMeasurePair(p, p), kMeasureEdition);
  });
}
