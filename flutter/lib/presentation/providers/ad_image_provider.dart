import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/data/services/ad_image_service.dart';

/// 홈 배너용 활성 ad_images. 홈 탭 진입 시 1회 fetch (autoDispose).
final adImagesProvider = FutureProvider.autoDispose<List<AdImageBanner>>((ref) {
  return AdImageService().activeBanners();
});
