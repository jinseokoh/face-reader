import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 방금 결제(unlock)한 궁합 상대의 supabaseId. 받은 카드 CTA 로 결제 후 궁합
/// 탭으로 이동했을 때, 해당 항목을 '확인' 리스트 맨 위에 고정(pin)해 사용자가
/// 즉시 결과를 찾도록 한다. 정렬 기준(score/newest)과 무관하게 최상단 노출.
///
/// 사용자가 정렬을 바꾸거나 카드를 누르면 [clear] 로 해제 — 이후엔 일반 정렬.
final recentUnlockFocusProvider =
    NotifierProvider<RecentUnlockFocusNotifier, String?>(
  RecentUnlockFocusNotifier.new,
);

class RecentUnlockFocusNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void focus(String? supabaseId) => state = supabaseId;
  void clear() => state = null;
}
