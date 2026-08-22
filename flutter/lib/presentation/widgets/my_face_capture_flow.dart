import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:facely/config/router.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/screens/chemistry/album_capture_page.dart';
import 'package:facely/presentation/screens/chemistry/face_mesh_page.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:facely/presentation/widgets/primary_button.dart';

/// 관상 사진을 어디서 가져올지 — 진입 시트의 선택값.
enum _CaptureSource { camera, album }

/// 내 관상 등록 공용 플로우 — 홈 헤더와 전 탭 nudge 배너가 공유.
/// 소스 선택 시트 → 카메라 촬영 또는 앨범 선택 → 정보 확인 →
/// InfoConfirm 이 isMyFace 로 등록 (PIVOT A5 ①). 앨범 경로는 로그인 게이트.
Future<void> startMyFaceCapture(BuildContext context, WidgetRef ref) =>
    _startCapture(context, ref, asMyFace: true);

/// 다른 사람 관상 플로우 — 내 관상 등록과 완전히 동일한 UX. 같은 자리
/// (FaceScanPill)에 있는 두 버튼이라 진입 시트도 같은 것을 쓴다.
/// isMyFace 로 등록하지 않는 것만 다르다.
Future<void> startOtherFaceCapture(BuildContext context, WidgetRef ref) =>
    _startCapture(context, ref, asMyFace: false);

/// [상대방 관상 추가]·[내 관상 등록] 진입 시트 — 카메라 / 앨범 / 닫기.
/// 취소(바깥 탭·닫기)는 null.
Future<_CaptureSource?> _showSourceSheet(BuildContext context) {
  return showModalBottomSheet<_CaptureSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xxl,
          AppSpacing.xxl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              label: '카메라로 촬영하기',
              icon: FontAwesomeIcons.camera,
              onPressed: () => Navigator.of(ctx).pop(_CaptureSource.camera),
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: '앨범으로 추가하기',
              icon: FontAwesomeIcons.image,
              onPressed: () => Navigator.of(ctx).pop(_CaptureSource.album),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('닫기', style: AppText.subTitle),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _startCapture(
  BuildContext context,
  WidgetRef ref, {
  required bool asMyFace,
}) async {
  final source = await _showSourceSheet(context);
  if (source == null || !context.mounted) return;

  final size = MediaQuery.of(context).size;
  CaptureResult? capture;

  if (source == _CaptureSource.camera) {
    AnalyticsService.instance.logCameraOpen();
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
    // 카메라 화면 안 [앨범에서 선택] 숏컷 — 진입 시트의 앨범과 같은 경로.
    if (result is FaceMeshAlbumRequest) {
      capture = await _pickFromAlbum(context, ref, size);
    } else if (result is CaptureResult) {
      capture = result;
    }
  } else {
    capture = await _pickFromAlbum(context, ref, size);
  }
  if (!context.mounted || capture == null) return;

  await context.push(
    '/capture/confirm',
    extra: CaptureExtras(
      capture: capture,
      metadataFuture: capture.metadataFuture,
      asMyFace: asMyFace,
    ),
  );
}

/// 앨범 경로 — 로그인 게이트 통과 후 앨범 시트. 취소·미로그인은 null.
Future<CaptureResult?> _pickFromAlbum(
  BuildContext context,
  WidgetRef ref,
  Size size,
) async {
  if (!ref.read(authProvider.notifier).isLoggedIn) {
    final loggedIn = await showLoginBottomSheet(context, ref);
    if (!loggedIn || !context.mounted) return null;
  }
  return showModalBottomSheet<CaptureResult>(
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
}
