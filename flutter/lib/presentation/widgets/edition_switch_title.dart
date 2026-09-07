import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/edition.dart';
import '../../core/edition_copy.dart';
import '../../core/theme.dart';
import '../providers/edition_provider.dart';

/// 관상 탭 앱바 제목 — Android 에서는 "관상 | 첫인상" 스위치. 활성 쪽은 제목색,
/// 비활성 쪽은 흐리게. 흐린 쪽을 누르면 확인 뒤 앱 전체 모드가 바뀐다.
/// iOS·컴파일 고정 빌드에서는 그냥 제목이다.
class EditionSwitchTitle extends ConsumerWidget {
  const EditionSwitchTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kEditionSwitchable) return Text(EditionCopy.faceTitle);
    final measure = ref.watch(editionModeProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _side(context, ref, label: '관상', active: !measure, toMeasure: false),
        Text(' | ',
            style: AppText.appBarTitle.copyWith(color: AppColors.textHint)),
        _side(context, ref, label: '첫인상', active: measure, toMeasure: true),
      ],
    );
  }

  Widget _side(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required bool active,
    required bool toMeasure,
  }) {
    final text = Text(
      label,
      style: active
          ? AppText.appBarTitle
          : AppText.appBarTitle.copyWith(color: AppColors.textHint),
    );
    if (active) return text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _confirm(context, ref, toMeasure: toMeasure),
      child: text,
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref,
      {required bool toMeasure}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          toMeasure ? '첫인상 분석으로 전환할까요?' : '관상 분석으로 전환할까요?',
          style: AppText.modalTitle,
        ),
        content: Text(
          toMeasure
              ? '관상 대신 얼굴 계측과 첫인상 지표로 봅니다. 저장된 얼굴은 그대로이고, '
                  '언제든 관상으로 되돌릴 수 있습니다.'
              : '첫인상 대신 관상 해석으로 봅니다. 저장된 얼굴은 그대로이고, '
                  '언제든 첫인상으로 되돌릴 수 있습니다.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: AppText.subTitle),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('전환', style: AppText.subTitle),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(editionModeProvider.notifier).switchTo(measure: toMeasure);
    }
  }
}
