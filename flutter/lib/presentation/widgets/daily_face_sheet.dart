import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

/// Switch on 트랙 — CompactSnackBar.success(0xFF4CAF50) 와 동일 녹색.
/// AppColors.success(2E7D32) 는 너무 진해 snackbar 와 톤이 어긋난다.
const _kSwitchOn = Color(0xFF4CAF50);

/// 설정 > 오늘 등록된 관상 공개 — opt-in 전환 bottom sheet.
///
/// 내 관상은 opt 여부와 무관하게 facely.kr "오늘 등록된 관상"에 표시된다 —
/// 공개를 켜면 원본 썸네일, 끄면 모자이크. 전환은 Switch 하나 (on 녹색 /
/// off 무채색), 보너스(연속 7일 유지 시 3코인 · 최초 1회)는 테두리 박스로
/// 강조. sheet 진입 시 claim RPC 로 달성분을 지급하고 수령 여부를 받아,
/// 기수령이면 보너스 안내를 숨긴다.
class DailyFaceSheet extends ConsumerStatefulWidget {
  const DailyFaceSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      // 기본 시트 최대 높이(화면 절반 근처)가 내용보다 낮아 스크롤이 생기던
      // 문제 — 내용 높이만큼 시트가 늘어나게 한다.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const DailyFaceSheet(),
    );
  }

  @override
  ConsumerState<DailyFaceSheet> createState() => _DailyFaceSheetState();
}

class _DailyFaceSheetState extends ConsumerState<DailyFaceSheet> {
  bool _busy = false;

  /// claim RPC 의 수령 완료 상태. null = 조회 전 (보너스 안내는 일단 표시).
  bool? _bonusReceived;

  @override
  void initState() {
    super.initState();
    _claim();
  }

  Future<void> _claim() async {
    final res = await ref.read(authProvider.notifier).claimDailyFaceBonus();
    if (!mounted) return;
    setState(() => _bonusReceived = res.already);
    if (res.granted) {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.success(
            message: '7일 공개 유지 보너스 3코인이 지급되었습니다'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final optedIn = user?.dailyFaceOptedIn ?? false;
    final optedSince = user?.dailyFaceOptedSince;
    final showBonus = _bonusReceived != true;
    final keptDays = optedSince != null
        ? DateTime.now().difference(optedSince).inDays
        : null;

    return SafeArea(
      // 스크롤 위젯 없음 — isScrollControlled 시트가 내용 높이만큼 늘어나
      // 높이 상한이 없고, 스크롤 래퍼가 있으면 드래그마다 stretch 오버스크롤이
      // 발동해 "스크롤되는 시트"가 된다.
      child: Padding(
        // 4면 동일 패딩 — 박스 아래 여백 = 좌우 여백.
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text('오늘 등록된 관상 공개', style: AppText.modalTitle)),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              '내 관상은 facely.kr 홈의 "오늘 등록된 관상"에 썸네일과 나이대·성별·'
              '관상 유형으로 표시됩니다. 공개를 켜면 원본 썸네일로, 끄면 '
              '모자이크로 가려진 상태로 표시됩니다.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSpacing.md),
            // Switch 는 설명문과 박스 사이 별도 행 — 박스 텍스트가 전폭을
            // 써서 어색한 줄바꿈 없이 나열되게 한다.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('관상 공개', style: AppText.sectionTitle),
                Switch(
                  value: optedIn,
                  activeTrackColor: _kSwitchOn,
                  // off 는 확실한 무채색 — M3 기본 inactive 가 진해서 on/off
                  // 구분이 약하다. 연한 회색 트랙 + 흰 thumb + 외곽선 제거.
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: AppTheme.border,
                  trackOutlineColor:
                      const WidgetStatePropertyAll(Colors.transparent),
                  onChanged: _busy ? null : (v) => _toggle(v),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 박스 안은 전부 body(15) 단일 사이즈 — 제목은 굵기로만 구분.
                  Text(
                    showBonus ? '공개하면 보너스 3코인' : '보너스 수령 완료',
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (showBonus) ...[
                    const SizedBox(height: 2),
                    Text(
                      '공개를 연속 7일 유지하면 지급됩니다\n'
                      '7일 전에 끄면 유지 일수는 다시 계산됩니다',
                      style: AppText.body,
                    ),
                    const SizedBox(height: 2),
                    // 항상 채워지는 한 줄 슬롯 — off 안내 ↔ on 진행 표시가
                    // 같은 자리에서 교체돼 sheet 높이 점프 없음.
                    Text(
                      keptDays != null && keptDays < 7
                          ? '공개 유지 $keptDays일째 · ${7 - keptDays}일 후 지급'
                          : '최초 1회만 지급',
                      style: AppText.body.copyWith(color: AppColors.textHint),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(bool optIn) async {
    setState(() => _busy = true);
    final res =
        await ref.read(authProvider.notifier).setDailyFaceOptIn(optIn);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      // opt-in 녹색(success) / opt-out 파란색(info) — 상단 snackbar.
      showTopSnackBar(
        Overlay.of(context),
        optIn
            ? CompactSnackBar.success(message: '공개로 설정했습니다')
            : CompactSnackBar.info(message: '비공개로 설정했습니다'),
      );
    } else {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.error(message: res.message ?? '설정 변경에 실패했습니다'),
      );
    }
  }
}
