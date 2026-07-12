import 'package:flutter/material.dart';

import 'package:facely/core/storage/thumbnail_paths.dart';

/// 상세 페이지 공용 아바타 — **56px 원형 + 1.5px ring**. 관상 상세의 원형이
/// 기준 구조: 이미지는 [ClipOval] 로 ring **안쪽**에 클리핑해 border 가 사진
/// 밖에 깔끔히 선다. 배경 fill 은 두지 않는다 — 원형 가장자리 안티앨리어스
/// 에서 밝은 바탕이 헤일로처럼 새어 보이는 문제의 원인 (§2.5 공용 승격,
/// 2026-07-12).
///
/// ring 색은 카드 배경에 맞춘다 — 다크 카드(관상·궁합 hero)는 기본값
/// white 30%, 흰 배경(케미 방 멤버 그리드)은 [borderColor] 로
/// AppColors.border 지정.
///
/// 이미지 3단: 로컬 thumbnailPath → CDN thumbnailKey → [fallback].
class DetailAvatar extends StatelessWidget {
  final String? thumbnailPath;
  final String? thumbnailKey;
  final Widget fallback;
  final Color? borderColor;

  const DetailAvatar({
    super.key,
    required this.thumbnailPath,
    required this.thumbnailKey,
    required this.fallback,
    this.borderColor,
  });

  static const double size = 56;

  @override
  Widget build(BuildContext context) {
    final file = ThumbnailPaths.resolveFileSync(thumbnailPath);
    final cdn = ThumbnailPaths.cdnUrl(thumbnailKey);
    Widget inner = fallback;
    if (file != null && file.existsSync()) {
      inner = Image.file(file, width: size, height: size, fit: BoxFit.cover);
    } else if (cdn != null) {
      inner = Image.network(
        cdn,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: ClipOval(child: inner),
    );
  }
}
