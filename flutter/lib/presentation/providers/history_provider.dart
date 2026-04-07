import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/domain/models/face_reading_report.dart';

final historyProvider = NotifierProvider<HistoryNotifier, List<FaceReadingReport>>(
  HistoryNotifier.new,
);

class HistoryNotifier extends Notifier<List<FaceReadingReport>> {
  @override
  List<FaceReadingReport> build() => [];

  void add(FaceReadingReport report) {
    state = [report, ...state];
  }

  void remove(int index) {
    state = [...state]..removeAt(index);
  }
}
