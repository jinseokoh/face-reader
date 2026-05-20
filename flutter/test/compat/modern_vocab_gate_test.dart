/// `shared/lib/domain/services/compat/` 의 *코드 라인* 에 한자가 한 자도 나오지
/// 않는지 검사하는 CI gate. 사용자 노출 narrative 가 전부 모던 한국어인지를
/// 빌드 시점에 강제한다.
///
/// 화이트리스트:
///   - `compat_label.dart` / `palace.dart` / `five_element.dart` — 각 enum 의
///     `.hanja` getter 가 한자 메타데이터를 의도적으로 반환한다.
///   - `modern_vocab.dart` — vocab SSOT. 한자가 직접 들어가지는 않지만 안전망.
///   - 모든 파일의 `//`·`///` 주석 영역 — 설계 doc 에 한자 인용 허용
///     (예: 『麻衣相法』). 코드 영역에서만 한자를 잡는다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compat narrative 코드에 한자 0 회', () {
    final dir = Directory('../shared/lib/domain/services/compat');
    expect(dir.existsSync(), isTrue, reason: 'compat 디렉토리를 찾을 수 없음');

    const whitelistedFiles = {
      'compat_label.dart',
      'palace.dart',
      'five_element.dart',
      'modern_vocab.dart',
    };

    final hanja = RegExp(r'[一-鿿]');
    final offenders = <String>[];

    for (final entity in dir.listSync(recursive: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final name = entity.uri.pathSegments.last;
      if (whitelistedFiles.contains(name)) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // 라인 시작이 doc 주석이면 skip.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        // 라인 중간 `//` 뒤의 inline comment 영역은 검사에서 제외.
        final codeOnly = line.split('//').first;
        if (hanja.hasMatch(codeOnly)) {
          offenders.add('  $name:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '산문 코드 라인에 한자 발견 — modern_vocab anchor 로 교체 필요:\n'
          '${offenders.join('\n')}',
    );
  });
}
