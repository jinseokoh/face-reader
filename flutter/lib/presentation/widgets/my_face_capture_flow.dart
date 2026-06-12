import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:facely/config/router.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/screens/home/album_capture_page.dart';
import 'package:facely/presentation/screens/home/face_mesh_page.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';

/// 내 관상 등록 공용 플로우 — 홈 헤더와 전 탭 nudge 배너가 공유.
/// 전면 카메라 즉시 오픈(좌하단 앨범 숏컷, 보정 사진 등록 경로) → 정보 확인 →
/// InfoConfirm 이 isMyFace 로 등록 (PIVOT A5 ①). 앨범 경로는 기존 정책과
/// 동일하게 로그인 게이트.
Future<void> startMyFaceCapture(BuildContext context, WidgetRef ref) async {
  AnalyticsService.instance.logCameraOpen();
  final size = MediaQuery.of(context).size;
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints.tightFor(
      width: size.width,
      height: size.height,
    ),
    builder: (_) => const FaceMeshPage(albumShortcut: true),
  );
  if (!context.mounted || result == null) return;

  CaptureResult? capture;
  if (result is FaceMeshAlbumRequest) {
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final loggedIn = await showLoginBottomSheet(context, ref);
      if (!loggedIn || !context.mounted) return;
    }
    capture = await showModalBottomSheet<CaptureResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints.tightFor(
        width: size.width,
        height: size.height,
      ),
      builder: (_) => const AlbumCapturePage(),
    );
  } else if (result is CaptureResult) {
    capture = result;
  }
  if (!context.mounted || capture == null) return;

  await context.push(
    '/capture/confirm',
    extra: CaptureExtras(
      capture: capture,
      metadataFuture: capture.metadataFuture,
      asMyFace: true,
    ),
  );
}
