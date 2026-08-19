// 관상 미등록 첫 화면 — 크레딧이 3/4 에서 1/4 로 올라가 멈춘 뒤,
// 일러스트와 문구가 화면 중앙에 fade in 한다.
//
// 실행: flutter test test/credits_empty_state_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facely/presentation/widgets/credits_empty_state.dart';
import 'package:facely/presentation/widgets/emotion_empty_state.dart';

const _lines = ['첫 줄이로다.', '둘째 줄입니다.'];
const _message = '아직 관상을 등록하지 않았다니!';
const _height = 400.0;
const _width = 360.0;

/// 스크롤 1회(10초)를 넘기는 시간.
const _afterScroll = Duration(seconds: 12);

/// 스크롤 → 일러스트 등장까지 전부 흘린다. 등장은 스크롤의 `whenComplete`
/// 로 시작하므로 프레임을 한 번 더 줘야 진행된다.
Future<void> _settleAll(WidgetTester tester) async {
  await tester.pump(_afterScroll);
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

/// 문구 블록 아래끝 — 영역 위끝 기준. 0 이하면 화면에서 완전히 빠져나갔다.
double _textBottom(WidgetTester tester) =>
    _textCenter(tester) + tester.getSize(_text).height / 2;

Widget get _subject => const CreditsEmptyState(
  lines: _lines,
  asset: 'assets/images/emotion-frown.png',
  message: _message,
);

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(height: _height, width: _width, child: _subject),
      ),
    ),
  ),
);

/// 탭 셸과 같은 구조 — IndexedStack 은 숨은 탭도 build 하므로, 선택된 탭만
/// TickerMode 로 열어 줘야 애니메이션이 "보이는 순간" 부터 시작한다.
Future<void> _pumpInTabShell(WidgetTester tester, int index) =>
    tester.pumpWidget(
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
                    child: i == 0 ? _subject : const SizedBox.shrink(),
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
/// 라우트 전환용 FadeTransition 이 위에 더 있을 수 있어 가장 가까운 것만
/// 본다 (find.ancestor 는 안쪽부터 바깥쪽 순서).
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
  testWidgets('맨 아래에서 시작해 위로 완전히 빠져나간다', (tester) async {
    await _pump(tester);
    // 시작할 때 문구 아래끝이 영역 아래끝(= 하단 탭 바 바로 위)에 붙는다.
    expect(_textBottom(tester), closeTo(_height, 1));

    await _settleAll(tester);
    // 끝날 때 마지막 글자까지 영역 위끝 밖으로 나간다.
    expect(_textBottom(tester), lessThanOrEqualTo(0));

    // 빠져나간 뒤로는 더 움직이지 않는다 (1회만).
    final end = _textCenter(tester);
    await tester.pump(const Duration(seconds: 20));
    expect(_textCenter(tester), end);
  });

  testWidgets('멈추지 않고 일정한 속도로 올라간다', (tester) async {
    await _pump(tester);
    const step = Duration(seconds: 2);
    final marks = <double>[_textCenter(tester)];
    for (var i = 0; i < 5; i++) {
      await tester.pump(step);
      marks.add(_textCenter(tester));
    }
    final deltas = [
      for (var i = 1; i < marks.length; i++) marks[i - 1] - marks[i],
    ];
    // 2초마다 같은 거리만큼 올라간다 — 중간에 느려지거나 멈추지 않는다.
    for (final d in deltas) {
      expect(d, closeTo(deltas.first, 0.5));
      expect(d, greaterThan(0));
    }
  });

  testWidgets('일러스트·문구는 크레딧이 다 빠져나간 뒤에야 떠오른다', (tester) async {
    await _pump(tester);
    expect(_revealOpacity(tester), 0, reason: '시작 시점엔 보이지 않는다');

    // 문구가 아직 화면에 걸쳐 있는 동안에는 겹쳐 보이면 안 된다.
    await tester.pump(const Duration(seconds: 9));
    expect(_textBottom(tester), greaterThan(0), reason: '아직 남아 있다');
    expect(_revealOpacity(tester), 0, reason: '남아 있으면 아직 안 뜬다');

    await _settleAll(tester);
    expect(_textBottom(tester), lessThanOrEqualTo(0));
    expect(_revealOpacity(tester), 1, reason: '다 빠져나간 뒤 완전히 드러난다');
    expect(find.text(_message), findsOneWidget);
  });

  testWidgets('기기 "애니메이션 제거" 설정에도 지속시간이 줄지 않는다', (tester) async {
    // 이 설정이 켜지면 AnimationController 는 기본값(normal)에서 지속시간을
    // 5% 로 줄인다 — 10초 연출이 0.5초가 되어 탭을 열자마자 끝나 있다.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await _pump(tester);
    final start = _textCenter(tester);

    // 5% 로 줄었다면 이 시점엔 이미 화면 밖으로 다 빠져나갔다.
    await tester.pump(const Duration(seconds: 1));
    final afterOneSecond = _textCenter(tester);
    expect(afterOneSecond, lessThan(start), reason: '움직이긴 한다');
    expect(
      afterOneSecond,
      greaterThan(_height * 0.5),
      reason: '1초 만에 절반 넘게 가면 안 된다',
    );
  });

  testWidgets('숨은 탭에서는 흐르지 않고, 탭이 열린 순간부터 시작한다', (tester) async {
    await _pumpInTabShell(tester, 1);
    final start = _textCenter(tester, skipOffstage: false);
    await tester.pump(const Duration(seconds: 20));
    expect(
      _textCenter(tester, skipOffstage: false),
      start,
      reason: '숨은 동안에는 제자리 — 애니메이션이 먼저 끝나면 안 된다',
    );

    await _pumpInTabShell(tester, 0);
    expect(_textCenter(tester), start, reason: '열린 순간에도 아직 처음 위치');
    await tester.pump(const Duration(seconds: 3));
    expect(_textCenter(tester), lessThan(start));
  });

  testWidgets('SliverFillRemaining 안에서도 레이아웃 예외 없이 그려진다', (tester) async {
    await tester.pumpWidget(
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
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getCenter(_text).dy, lessThan(start));
    await _settleAll(tester);
    expect(_revealOpacity(tester), 1);
    expect(tester.takeException(), isNull);
  });
}
