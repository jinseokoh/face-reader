import 'package:flutter_riverpod/flutter_riverpod.dart';

final selectedTabProvider = NotifierProvider<SelectedTabNotifier, int>(
  SelectedTabNotifier.new,
);

/// 앱을 열면 케미 탭에서 시작한다.
///
/// 탭 순서는 인원수 위계(1인 관상 → 2인 궁합 → 다인 케미 → 채팅 → 설정)라
/// 관상이 0번이지만, 첫 화면은 케미다. 관상은 케미에 넣는 재료지 출발점이
/// 아니고, 케미 목록은 내 관상 없이도 열려 있어 처음 연 사람도 볼 것이 있다.
///
/// 이 값을 온보딩 쪽에 두면 안 된다. 온보딩은 "다시 보지 않기" 를 눌렀거나
/// 내 관상이 이미 등록된 사용자에게는 뜨지 않아, 착지 탭 지정이 그 조건에
/// 가려진다. 시작 탭은 조건 없는 사실이므로 기본값 자리에 적는다.
const int kInitialTabIndex = 2;

class SelectedTabNotifier extends Notifier<int> {
  @override
  int build() => kInitialTabIndex;
  void selectTab(int index) => state = index;
}

final historyTabProvider = NotifierProvider<HistoryTabNotifier, int>(
  HistoryTabNotifier.new,
);

class HistoryTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void selectTab(int index) => state = index;
}
