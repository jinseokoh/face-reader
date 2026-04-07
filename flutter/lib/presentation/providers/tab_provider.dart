import 'package:flutter_riverpod/flutter_riverpod.dart';

final selectedTabProvider = NotifierProvider<SelectedTabNotifier, int>(
  SelectedTabNotifier.new,
);

class SelectedTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void selectTab(int index) => state = index;
}
