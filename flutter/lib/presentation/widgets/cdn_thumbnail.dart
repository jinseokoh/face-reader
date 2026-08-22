import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// CDN 썸네일 한 장 — 전 탭 아바타가 공유하는 CDN 렌더 경로.
///
/// 디스크 캐시를 거친다. 썸네일 키가 내용 주소(sha256)라 **URL 이 불변**이므로
/// 캐시를 오래 들고 있어도 옛 얼굴이 나올 수 없다 — 사진이 바뀌면 URL 자체가
/// 바뀐다. 캐시가 없으면 앱을 켤 때마다 모든 아바타를 다시 받는다.
///
/// [fallback] 은 네트워크 실패·404 때 그 자리에 그린다 (source 아이콘·성별
/// 실루엣 등 화면마다 다르다).
Widget cdnThumbnail({
  required String url,
  required double size,
  required Widget fallback,
}) {
  return CachedNetworkImage(
    imageUrl: url,
    width: size,
    height: size,
    fit: BoxFit.cover,
    // 리스트 아바타가 스크롤마다 페이드로 깜빡이지 않게.
    fadeInDuration: Duration.zero,
    errorWidget: (_, _, _) => fallback,
  );
}
