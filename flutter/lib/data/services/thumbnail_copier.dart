import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/data/services/r2_uploader.dart';

/// 구매한 궁합의 사진을 **내 소유로 복사**한다.
///
/// 동결 스냅샷(`compatibilities.a_body`/`b_body`)에 남의 사진 주소만 베껴 두면,
/// 원본 주인이 재촬영하거나 탈퇴하는 순간 산 사람 화면이 깨진다. 실제로 그렇게
/// 확인 쌍 13개 중 8개가 깨졌다. `privacy.md:27` 이 약속한 "상대방의 데이터
/// 삭제 여부와 무관하게 이용" 은 주소가 아니라 **사본**이 있어야 지켜진다.
///
/// 바이트는 로컬 캐시에 있으면 그걸 쓰고, 없으면 CDN 에서 받는다(public read).
/// 구매 시점엔 그 사진을 화면에 띄우고 있으므로 사실상 항상 손에 있다.
class ThumbnailCopier {
  ThumbnailCopier._();

  /// [sourceKey] 의 사진을 내 폴더로 복사하고 새 키를 돌려준다.
  /// 이미 내 것이면 그대로, 못 하면 null — 호출부는 원본 키로 진행하고
  /// 시작 시 대조에 맡긴다. **구매를 막지 않는다.**
  static Future<String?> copyToMyScope(String sourceKey) async {
    final uid = AuthService().sessionUserId;
    if (uid == null) return null;
    if (sourceKey.startsWith('thumbnails/$uid/')) return sourceKey;
    try {
      final bytes = await _bytesOf(sourceKey);
      if (bytes == null) return null;
      final p = await R2Uploader().upload(
        prefix: 'thumbnails',
        hash: ThumbnailPaths.hashBytes(bytes),
        accessToken: AuthService().accessToken,
        bytes: bytes,
      );
      debugPrint('[ThumbnailCopier] $sourceKey → ${p.key}');
      return p.key;
    } catch (e) {
      debugPrint('[ThumbnailCopier] 복사 실패 $sourceKey: $e');
      return null;
    }
  }

  /// body JSON 문자열의 `thumbnailKey` 를 내 사본 키로 갈아끼운다.
  /// 복사가 안 되면 원본 문자열 그대로 — 스냅샷은 어차피 저장돼야 한다.
  static Future<String> withCopiedThumbnail(String bodyJson) async {
    try {
      final map = jsonDecode(bodyJson) as Map<String, dynamic>;
      final key = map['thumbnailKey'] as String?;
      if (key == null || key.isEmpty) return bodyJson;
      final mine = await copyToMyScope(key);
      if (mine == null || mine == key) return bodyJson;
      map['thumbnailKey'] = mine;
      return jsonEncode(map);
    } catch (e) {
      debugPrint('[ThumbnailCopier] body 패치 실패: $e');
      return bodyJson;
    }
  }

  /// 로컬 캐시 우선, 없으면 CDN. 캐시 파일명이 키의 basename 이라 남의 키여도
  /// 이 기기가 이미 받아둔 파일이 있으면 그대로 쓴다.
  static Future<Uint8List?> _bytesOf(String key) async {
    final file = await ThumbnailPaths.cacheFile(key);
    if (file != null && await file.exists()) return file.readAsBytes();
    final url = ThumbnailPaths.cdnUrl(key);
    if (url == null) return null;
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) return null;
    return res.bodyBytes;
  }
}
