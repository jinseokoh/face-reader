import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/hive/hive_setup.dart';
import '../../core/theme.dart';
import '../../data/services/ad_image_service.dart';
import 'primary_button.dart';

/// 설정 탭 진입 시 노출되는 배너 광고 팝업 — 상단 full-width 배너 이미지
/// (탭 = link_url) + 하단 [다시 보지 않기 체크 / 닫기 / 확인] 패널.
///
/// 노출 규칙: 배너별로 ① '다시 보지 않기' 체크 시 영구 제외(Hive prefs),
/// ② 같은 실행(session)에선 1회만. 활성 배너 중 노출 가능한 첫 번째
/// (sort_order 순) 하나만 띄운다. 조회 실패는 조용히 생략.
class AdBannerDialog extends StatefulWidget {
  final AdImageBanner banner;
  const AdBannerDialog({super.key, required this.banner});

  /// 이번 실행에서 이미 보여준 배너 id — 탭을 오갈 때마다 다시 뜨지 않게.
  static final _shownThisSession = <String>{};

  static String _dismissKey(String id) => 'adBannerDismissed:$id';

  static Future<void> maybeShow(BuildContext context) async {
    final List<AdImageBanner> banners;
    try {
      banners = await AdImageService().activeBanners();
    } catch (_) {
      return; // 네트워크 실패 — 광고는 조용히 생략.
    }
    if (!context.mounted) return;
    final prefs = Hive.box<String>(HiveBoxes.prefs);
    for (final b in banners) {
      if (_shownThisSession.contains(b.id)) continue;
      if (prefs.get(_dismissKey(b.id)) != null) continue;
      if (b.imageUrl.isEmpty) continue;
      _shownThisSession.add(b.id);
      await showDialog<void>(
        context: context,
        builder: (_) => AdBannerDialog(banner: b),
      );
      return; // 한 번에 하나만.
    }
  }

  @override
  State<AdBannerDialog> createState() => _AdBannerDialogState();
}

class _AdBannerDialogState extends State<AdBannerDialog> {
  bool _neverAgain = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 배너 본체 — 탭하면 확인과 동일하게 링크로.
          GestureDetector(
            onTap: _openLink,
            child: CachedNetworkImage(
              imageUrl: widget.banner.imageUrl,
              fit: BoxFit.fitWidth,
              placeholder: (_, _) => Container(
                height: 200,
                color: AppColors.surface,
              ),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 다시 보지 않기 — 체크 상태로 닫히면 이 배너는 영구 제외.
                InkWell(
                  onTap: () => setState(() => _neverAgain = !_neverAgain),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _neverAgain,
                          onChanged: (v) =>
                              setState(() => _neverAgain = v ?? false),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Text('다시 보지 않기', style: AppText.body),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _close,
                        child: Text(
                          '닫기',
                          style: AppText.body.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: PrimaryButton(label: '확인', onPressed: _openLink)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _persistDismiss() {
    if (!_neverAgain) return;
    Hive.box<String>(HiveBoxes.prefs).put(
      AdBannerDialog._dismissKey(widget.banner.id),
      DateTime.now().toIso8601String(),
    );
  }

  void _close() {
    _persistDismiss();
    Navigator.of(context).pop();
  }

  Future<void> _openLink() async {
    _persistDismiss();
    final link = widget.banner.linkUrl;
    Navigator.of(context).pop();
    if (link != null && link.isNotEmpty) {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    }
  }
}
