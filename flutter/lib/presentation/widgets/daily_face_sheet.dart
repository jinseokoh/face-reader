import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 설정 > 오늘의 관상 공개 — opt-in 전환 bottom sheet.
///
/// 내 관상은 opt 여부와 무관하게 facely.kr "오늘의 관상"에 표시된다 —
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
              '내 관상은 facely.kr 홈의 "오늘의 관상"에 썸네일과 나이대·성별·'
              '관상 유형으로 표시됩니다. 공개를 켜면 원본 썸네일로, 끄면 '
              '모자이크로 가려진 상태로 표시됩니다.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          showBonus ? '공개하면 보너스 3코인' : '관상 공개',
                          style: AppText.subTitle,
                        ),
                        if (showBonus) ...[
                          const SizedBox(height: 2),
                          Text(
                            '공개를 연속 7일 유지하면 지급됩니다 (최초 1회)\n'
                            '7일 전에 끄면 유지 일수는 다시 계산됩니다',
                            style: AppText.caption
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          if (keptDays != null && keptDays < 7) ...[
                            const SizedBox(height: 2),
                            Text(
                              '공개 유지 $keptDays일째 · ${7 - keptDays}일 후 지급',
                              style: AppText.caption
                                  .copyWith(color: AppColors.textHint),
                            ),
                          ],
                        ] else ...[
                          const SizedBox(height: 2),
                          Text(
                            '보너스 수령 완료',
                            style: AppText.caption
                                .copyWith(color: AppColors.textHint),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Switch(
                    value: optedIn,
                    activeTrackColor: AppColors.success,
                    onChanged: _busy ? null : (v) => _toggle(v),
                  ),
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
