// 빈 탭 연출 — 문구가 위에서 0.5초 만에 뚝 떨어져 멈춘 뒤,
// 그 아래로 일러스트와 문구가 fade in 한다.
//
// 실행: flutter test test/credits_empty_state_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facely/presentation/widgets/credits_empty_state.dart';
import 'package:facely/presentation/widgets/emotion_empty_state.dart';

const _lines = [
  '관상은 미래의 운명을',
  '단정짓는 점술이 아니라,',
  '내 삶의 모습을 살피고',
  '돌아보게 하는',
  '오랜 지혜입니다.',
];
const _message = '관상 추가 버튼을 누르면, 내 관상을 볼 수 있습니다.';
const _height = 560.0;
const _width = 360.0;

/// 떨어지는 0.5초를 넘긴다.
const _afterDrop = Duration(seconds: 2);

/// 떨어짐 → fade in 까지 전부 흘린다. fade 는 떨어짐이 끝나는 **그 프레임에**
/// 시작하므로 프레임을 한 번 더 줘야 진행된다.
Future<void> _settleAll(WidgetTester tester) async {
  await tester.pump(_afterDrop);
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

Widget _subjectWith({bool active = true}) => CreditsEmptyState(
  lines: _lines,
  asset: 'assets/images/emotion-frown.png',
  message: _message,
  active: active,
);

Widget get _subject => _subjectWith();

Future<void> _pumpAndPrime(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump();
}

Future<void> _pump(WidgetTester tester, {bool active = true}) => _pumpAndPrime(
  tester,
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          height: _height,
          width: _width,
          child: _subjectWith(active: active),
        ),
      ),
    ),
  ),
);

/// 탭 셸과 같은 구조 — IndexedStack 은 숨은 탭도 build 하므로 이 위젯은 앱을
/// 켤 때 이미 만들어져 있다. 연출의 시작 신호는 생성 시점이 아니라 `active` 다.
Future<void> _pumpInTabShell(WidgetTester tester, int index) => _pumpAndPrime(
  tester,
  MaterialApp(
    home: Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < 2; i++)
            TickerMode(
              enabled: i == index,
              child: SizedBox(
                height: _height,
                width: _width,
                child: i == 0
                    ? _subjectWith(active: index == 0)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    ),
  ),
);

Finder get _text => find.text(_lines.join('\n'));

/// 문구 블록 중심의 세로 위치 — 영역 위쪽 기준.
double _textCenter(WidgetTester tester, {bool skipOffstage = true}) {
  final finder = find.text(_lines.join('\n'), skipOffstage: skipOffstage);
  final regionTop = tester
      .getTopLeft(find.byType(CreditsEmptyState, skipOffstage: false))
      .dy;
  return tester.getCenter(finder).dy - regionTop;
}

/// 일러스트·문구를 감싼 FadeTransition 의 현재 불투명도.
double _revealOpacity(WidgetTester tester) => tester
    .widgetList<FadeTransition>(
      find.ancestor(
        of: find.byType(EmotionEmptyState),
        matching: find.byType(FadeTransition),
      ),
    )
    .first
    .opacity
    .value;

void main() {
  testWidgets('위에서 떨어져 제자리에 멈춘다', (tester) async {
    await _pump(tester);
    final start = _textCenter(tester);
    final blockHeight = tester.getSize(_text).height;

    await tester.pump(_afterDrop);
    final rest = _textCenter(tester);

    expect(rest, greaterThan(start), reason: '아래로 내려온다');
    // 시작 높이는 문구 블록의 1.6 배 위 — 화면 밖에서 들어와야 한다.
    expect(
      rest - start,
      closeTo(blockHeight * 1.6, 1),
      reason: '문구 높이의 1.6 배만큼 떨어진다',
    );
  });

  testWidgets('0.5초면 다 떨어진다 — 그 뒤로는 움직이지 않는다', (tester) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final atHalf = _textCenter(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(_textCenter(tester), atHalf, reason: '0.5초에 이미 끝나 있다');
  });

  testWidgets('떨어지는 동안에는 일러스트가 안 보인다', (tester) async {
    await _pump(tester);
    expect(_revealOpacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 250));
    expect(_revealOpacity(tester), 0, reason: '아직 떨어지는 중');

    await _settleAll(tester);
    expect(_revealOpacity(tester), 1, reason: '멈춘 뒤 떠오른다');
  });

  testWidgets('문구는 사라지지 않고 화면에 남는다', (tester) async {
    // 예전 크레딧은 위로 빠져나가 사라졌다. 지금은 안내와 함께 읽혀야 한다.
    await _pump(tester);
    await _settleAll(tester);
    expect(_text, findsOneWidget);
    expect(find.text(_message), findsOneWidget);
  });

  testWidgets('기기 "애니메이션 제거" 설정에도 지속시간이 줄지 않는다', (tester) async {
    // 이 설정이 켜지면 AnimationController 는 지속시간을 5% 로 줄인다 —
    // 0.5초 연출이 25ms 가 되어 탭을 열자마자 끝나 있다.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await _pump(tester);
    final start = _textCenter(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_revealOpacity(tester), 0, reason: '50ms 에 이미 끝나 있으면 안 된다');
    expect(_textCenter(tester), closeTo(start, 5), reason: '거의 안 움직였다');
  });

  testWidgets('숨은 탭에서는 시작하지 않고, 탭이 열린 순간부터 떨어진다', (tester) async {
    await _pumpInTabShell(tester, 1);
    final start = _textCenter(tester, skipOffstage: false);
    await tester.pump(const Duration(seconds: 5));
    expect(
      _textCenter(tester, skipOffstage: false),
      start,
      reason: '숨은 동안에는 제자리 — 안 보이는 곳에서 끝나 있으면 안 된다',
    );

    await _pumpInTabShell(tester, 0);
    expect(_textCenter(tester), start, reason: '열린 순간에도 아직 처음 위치');
    await tester.pump(_afterDrop);
    expect(_textCenter(tester), greaterThan(start));
  });

  testWidgets('탭을 다시 열어도 되감기지 않는다 — 최초 1회만', (tester) async {
    await _pumpInTabShell(tester, 1);
    await _pumpInTabShell(tester, 0); // 최초 진입 — 여기서 시작
    await _settleAll(tester);
    final rest = _textCenter(tester);

    await _pumpInTabShell(tester, 1); // 다른 탭
    await _pumpInTabShell(tester, 0); // 돌아옴
    expect(_textCenter(tester), rest, reason: '다시 떨어지지 않는다');
    expect(_revealOpacity(tester), 1);
  });

  testWidgets('active 가 false 면 시작조차 하지 않는다', (tester) async {
    await _pump(tester, active: false);
    final start = _textCenter(tester);
    await tester.pump(_afterDrop);
    expect(_textCenter(tester), start);
    expect(_revealOpacity(tester), 0);
  });

  testWidgets('SliverFillRemaining 안에서도 레이아웃 예외 없이 그려진다', (tester) async {
    await _pumpAndPrime(
      tester,
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('관상')),
          body: RefreshIndicator(
            onRefresh: () async {},
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(hasScrollBody: false, child: _subject),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull, reason: 'intrinsic 조회에 견뎌야 한다');
    expect(_text, findsOneWidget);

    final start = tester.getCenter(_text).dy;
    await _settleAll(tester);
    expect(tester.getCenter(_text).dy, greaterThan(start));
    expect(_revealOpacity(tester), 1);
    expect(tester.takeException(), isNull);
  });
}
