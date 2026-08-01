import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 설정 > 오늘의 관상 공개 — opt-in 전환 bottom sheet.
///
/// 공개를 켜면 facely.kr 홈 "오늘의 관상" 그리드에 내 관상 썸네일·나이대·
/// 성별·관상 유형이 노출된다. 전환은 언제든 가능 (잠금 없음). 보너스
/// 3코인은 선지급이 아니라 연속 7일 공개 유지 달성 시 1회 지급 —
/// sheet 진입 시 claim RPC 로 달성분을 지급하고 수령 여부를 받아,
/// 기수령이면 보너스 안내를 숨긴다.
class DailyFaceSheet extends ConsumerStatefulWidget {
  const DailyFaceSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('7일 공개 유지 보너스 3코인이 지급되었습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final optedIn = user?.dailyFaceOptedIn ?? false;
    final optedSince = user?.dailyFaceOptedSince;
    final showBonus = _bonusReceived != true;
    // 공개 중이고 미수령일 때만 진행 표시 — 유지 일수는 연속 공개 시작 시각 기준.
    final keptDays = optedSince != null
        ? DateTime.now().difference(optedSince).inDays
        : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text('오늘의 관상 공개', style: AppText.modalTitle)),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              '공개를 켜면 facely.kr 홈의 "오늘의 관상"에 내 관상 썸네일과 '
              '나이대·성별·관상 유형이 표시됩니다. 이름과 계정 정보는 표시되지 '
              '않으며, 내 관상이 등록되어 있어야 표시됩니다.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '공개 여부는 언제든지 변경할 수 있고, 비공개로 전환하면 즉시 '
              '노출이 중단됩니다.',
              style: AppText.body,
            ),
            if (showBonus) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '공개를 연속 7일 유지하면 보너스 3코인이 지급됩니다 '
                '(기본 1코인, 프로모션 기간 한정 3코인 · 최초 1회). '
                '7일이 되기 전에 비공개로 전환하면 유지 일수는 다시 계산됩니다.',
                style: AppText.caption.copyWith(color: AppColors.textSecondary),
              ),
              // keptDays >= 7 은 claim 이 진입 시점에 지급·숨김 처리하므로
              // 정상 경로에선 안 보인다 — claim 실패(오프라인) 시 음수 표기
              // 방지 가드.
              if (keptDays != null && keptDays < 7) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '공개 유지 $keptDays일째 · ${7 - keptDays}일 후 지급',
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : () => _toggle(!optedIn),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg - 2),
                    side: const BorderSide(color: AppColors.textPrimary),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(optedIn ? '비공개로 전환' : '공개하기',
                        style: AppText.subTitle),
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
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(optIn ? '공개가 설정되었습니다' : '비공개로 전환되었습니다')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? '설정 변경에 실패했습니다')),
      );
    }
  }
}
