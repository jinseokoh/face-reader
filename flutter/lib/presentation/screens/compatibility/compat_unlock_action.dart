import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_pair_key.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/data/services/compat_unlock_service.dart';
import 'package:facely/data/services/supabase_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/compat_unlock_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:facely/presentation/widgets/purchase_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 궁합 1코인 unlock 공용 흐름. 궁합 탭의 잠금 카드와 받은 카드(report_page)의
/// CTA 가 같은 결제 로직을 공유해 두 진입점의 과금 일관성을 보장한다.
///
/// [confirm] true 면 "1코인 필요" 확인 다이얼로그를 거치고(궁합 탭 리스트),
/// false 면 호출부 버튼이 이미 비용("1코인으로 풀이 보기")을 고지했다는 전제로
/// 바로 결제한다(받은 카드 CTA).
///
/// 반환: 결제되어(또는 이미 unlock 돼) 결과 진입이 가능하면 true. 취소·로그인
/// 실패·잔액 부족·RPC 오류면 false.
Future<bool> runCompatUnlock(
  BuildContext context,
  WidgetRef ref, {
  required FaceReadingReport my,
  required FaceReadingReport album,
  bool confirm = true,
}) async {
  AnalyticsService.instance.logClickCompat();
  // 1. 로그인 확인.
  final auth = ref.read(authProvider.notifier);
  if (!auth.isLoggedIn) {
    final ok = await showLoginBottomSheet(context, ref);
    if (!ok || !context.mounted) return false;
  }

  // 2. supabaseId 보장 — 없으면 saveMetrics 로 생성 후 Hive 갱신.
  try {
    await _ensureSupabaseId(ref, my);
    await _ensureSupabaseId(ref, album);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('저장 중 오류: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
    return false;
  }

  final key = tryPairKey(my, album);
  if (key == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('저장된 ID 를 찾을 수 없습니다. 잠시 후 다시 시도해 주세요.')),
      );
    }
    return false;
  }

  // 이미 unlock 된 상대면 재결제 없이 통과 (partner_id = 상대 id, 내 사진
  // 교체와 무관하게 유지).
  final already =
      ref.read(compatUnlocksProvider).asData?.value ?? const <String>{};
  if (already.contains(key)) {
    return true;
  }

  // 3. 잔액 확인.
  if (auth.coins < 1) {
    if (!context.mounted) return false;
    // 충전 시트 — 구매 성공 시 같은 흐름을 재시도(네비게이션 없이 unlock 만 반영).
    await PurchaseSheet.show(context, onPurchased: () {
      runCompatUnlock(context, ref, my: my, album: album, confirm: confirm);
    });
    return false;
  }

  // 4. 확인 다이얼로그 — 버튼이 이미 비용을 고지한 경우(confirm=false)는 생략.
  if (confirm) {
    if (!context.mounted) return false;
    final ok = await _showConfirmDialog(context);
    if (ok != true) return false;
  }

  // 5. RPC. unlock 직전에 분석을 실행해 total_score 를 함께 기록 — admin 콘솔
  // (refine) 에서 점수별 정렬·필터 가능하도록. alias 는 결제 시점 이름 스냅샷
  // (내 쪽 = 프로필 닉네임, 상대 쪽 = 카드에 지정한 이름).
  final preBundle = analyzeCompatibilityFromReports(my: my, album: album);
  final int newBalance;
  try {
    newBalance = await CompatUnlockService().unlock(
      key,
      userBody: my.toBodyJson(),
      partnerBody: album.toBodyJson(),
      userAlias: AuthService().currentUser?.nickname,
      partnerAlias: album.alias,
      totalScore: preBundle.report.total,
    );
  } catch (e, st) {
    debugPrint('[CompatUnlock] unlock failed: $e\n$st');
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('해제 중 오류: $e'),
        backgroundColor: Colors.red.shade700,
      ),
    );
    return false;
  }
  if (!context.mounted) return false;
  if (newBalance == -1) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('코인이 부족합니다.')),
    );
    return false;
  }

  // 6. 갱신.
  await auth.refreshCoins();
  ref.invalidate(compatUnlocksProvider);
  return true;
}

/// 궁합 진입 시 metrics row 를 서버에 보장.
///
/// - **본인 얼굴(isMyFace)**: 멀티디바이스 복원(로그인 후 `where user_id=나`)을
///   위해 supabaseId 가 이미 있어도 **항상 upsert** (서버에 내 카드 보장).
///   saveMetrics 는 upsert 라 idempotent.
/// - **그 외(상대/앨범)**: supabaseId 있으면 skip — 남의(받은) 카드를 내 user_id 로
///   upload·claim 하지 않기 위함. null 일 때만 id 발급.
Future<void> _ensureSupabaseId(WidgetRef ref, FaceReadingReport report) async {
  if (!report.isMyFace && report.supabaseId != null) return;
  final uuid = await SupabaseService().saveMetrics(report);
  if (report.supabaseId != uuid) {
    report.supabaseId = uuid;
    await ref.read(historyProvider.notifier).updateHive();
  }
}

/// "1코인이 필요합니다" 확인 다이얼로그 — 카메라 path 의 instructional modal 과
/// 동일 스타일 (compatibility.png + 타이틀 + 안내 + [취소] [궁합보기]).
Future<bool?> _showConfirmDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/compatibility.png',
              height: 200,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 16),
            Text(
              '궁합 보기',
              style: AppText.modalTitle.copyWith(
                color: const Color(0xFF1F1F1F),
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '궁합을 보려면 1코인이 필요합니다.\n궁합을 보시겠습니까?',
              style: AppText.body.copyWith(
                color: AppColors.accent,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF555555),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '취소',
                        style: AppText.subTitle.copyWith(
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F1F1F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '궁합보기',
                        style: AppText.subTitle.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
