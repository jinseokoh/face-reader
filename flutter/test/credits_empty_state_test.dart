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

/// 스크롤 1회를 넉넉히 넘기는 시간. 지속시간은 이동 거리 / 속도라
/// 문구 길이에 따라 달라진다.
const _afterScroll = Duration(seconds: 30);

/// 스크롤 → 일러스트 등장까지 전부 흘린다. 등장은 스크롤의 `whenComplete`
/// 로 시작하므로 프레임을 한 번 더 줘야 진행된다.
Future<void> _settleAll(WidgetTester tester) async {
  await tester.pump(_afterScroll);
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

/// 문구 블록 위끝 — 영역 위끝 기준. 영역 높이 이상이면 아직 화면 아래 바깥.
double _textTop(WidgetTester tester) =>
    _textCenter(tester) - tester.getSize(_text).height / 2;

/// 문구 블록 아래끝 — 영역 위끝 기준. 0 이하면 화면에서 완전히 빠져나갔다.
double _textBottom(WidgetTester tester) =>
    _textCenter(tester) + tester.getSize(_text).height / 2;

Widget _subjectWith({bool active = true}) => CreditsEmptyState(
  lines: _lines,
  asset: 'assets/images/emotion-frown.png',
  message: _message,
  active: active,
);

Widget get _subject => _subjectWith();

/// 첫 프레임 뒤(post-frame)에 시작되는 애니메이션의 첫 tick 을 잡아 주는
/// 0초 pump 를 붙인다. 이게 없으면 다음 `pump(d)` 가 시작 시각으로 소비돼
/// 시간이 흐르지 않는다. 실기에서는 매 프레임이 이어지므로 해당 없음.
Future<void> _pumpAndPrime(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump();
}

Future<void> _pump(WidgetTester tester) => _pumpAndPrime(
  tester,
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(height: _height, width: _width, child: _subject),
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
  testWidgets('화면 아래 바깥에서 시작해 위로 완전히 빠져나간다', (tester) async {
    await _pump(tester);
    // 시작할 때 문구 위끝이 영역 아래끝(= 하단 탭 바 바로 위)에 있다.
    // 문구가 화면보다 길어도 시작 자세가 화면을 채우지 않는다.
    expect(_textTop(tester), closeTo(_height, 1));

    await _settleAll(tester);
    // 끝날 때 마지막 글자까지 영역 위끝 밖으로 나간다.
    expect(_textBottom(tester), lessThanOrEqualTo(0));

    // 빠져나간 뒤로는 더 움직이지 않는다 (1회만).
    final end = _textCenter(tester);
    await tester.pump(const Duration(seconds: 20));
    expect(_textCenter(tester), end);
  });

  testWidgets('문구가 화면보다 길어도 화면 아래 바깥에서 시작한다', (tester) async {
    // 문구는 계속 길어진다. 출발 자세가 문구 길이에 따라 달라지면(예: 아래끝
    // 맞춤) 화면을 가득 채운 채 시작해 "위에서 시작" 처럼 보인다.
    final long = [for (var i = 0; i < 40; i++) '$i 번째 줄이로다.'];
    await _pumpAndPrime(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: _height,
              width: _width,
              child: CreditsEmptyState(
                lines: long,
                asset: 'assets/images/emotion-frown.png',
                message: _message,
                active: true,
              ),
            ),
          ),
        ),
      ),
    );
    final text = find.text(long.join('\n'));
    final regionTop = tester
        .getTopLeft(find.byType(CreditsEmptyState, skipOffstage: false))
        .dy;
    final textHeight = tester.getSize(text).height;
    expect(
      textHeight,
      greaterThan(_height),
      reason: '이 테스트는 문구가 화면보다 긴 경우를 다룬다',
    );

    final top = tester.getTopLeft(text).dy - regionTop;
    expect(top, closeTo(_height, 1), reason: '첫 줄이 영역 아래끝에서 출발한다');

    // 속도는 문구 길이와 무관하게 일정하다 — 거리에서 지속시간을 역산한다.
    await tester.pump(const Duration(seconds: 1));
    final moved = _height - (tester.getTopLeft(text).dy - regionTop);
    expect(moved, closeTo(60, 2), reason: '초당 60px');

    // 길이에 비례한 시간이 지나면 마지막 글자까지 빠져나간다.
    final travel = _height + textHeight;
    await tester.pump(Duration(milliseconds: (travel / 60 * 1000).round()));
    final bottom = tester.getBottomLeft(text).dy - regionTop;
    expect(bottom, lessThanOrEqualTo(0));
  });

  testWidgets('멈추지 않고 일정한 속도로 올라간다', (tester) async {
    await _pump(tester);
    const step = Duration(seconds: 1);
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
    await tester.pump(const Duration(seconds: 4));
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
    final travel = _height + tester.getSize(_text).height;

    // 5% 로 줄었다면 이 시점엔 이미 화면 밖으로 다 빠져나갔다.
    await tester.pump(const Duration(seconds: 1));
    final moved = start - _textCenter(tester);
    expect(moved, greaterThan(0), reason: '움직이긴 한다');
    expect(moved, lessThan(travel * 0.5), reason: '1초 만에 절반 넘게 가면 안 된다');
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

  testWidgets('탭을 다시 열어도 되감기지 않는다 — 최초 1회만', (tester) async {
    await _pumpInTabShell(tester, 1);
    await _pumpInTabShell(tester, 0); // 최초 진입 — 여기서 시작
    await tester.pump(const Duration(seconds: 4));
    final afterFirstVisit = _textCenter(tester);

    // 다른 탭으로 갔다가 돌아온다.
    await _pumpInTabShell(tester, 1);
    await _pumpInTabShell(tester, 0);
    expect(
      _textCenter(tester),
      afterFirstVisit,
      reason: '되돌아왔다고 처음부터 다시 시작하면 안 된다',
    );
    await tester.pump(const Duration(seconds: 2));
    expect(_textCenter(tester), lessThan(afterFirstVisit), reason: '이어서 진행');
  });

  testWidgets('active 가 false 면 시작조차 하지 않는다', (tester) async {
    await _pumpAndPrime(
      tester,
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: _height,
              width: _width,
              child: _subjectWith(active: false),
            ),
          ),
        ),
      ),
    );
    final start = _textCenter(tester);
    await tester.pump(const Duration(seconds: 30));
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
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getCenter(_text).dy, lessThan(start));
    await _settleAll(tester);
    expect(_revealOpacity(tester), 1);
    expect(tester.takeException(), isNull);
  });
}
