import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/config/router.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/screens/home/album_capture_page.dart';
import 'package:facely/presentation/screens/home/face_mesh_page.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';

import 'team_matrix_screen.dart';

/// 팀 케미 맵 — 팀(방) 화면. PIVOT A6 방 화면 스펙:
/// 모임명 · 참여 n/12 진행 · 멤버 칩 그리드(👑/+) · [📷 직접 스캔] ·
/// [💬 카톡으로 초대](P3 활성화) · 방장 [마감](3명 미만 비활성) ·
/// [팀 케미 맵 보기](3명↑).
class TeamRoomScreen extends ConsumerStatefulWidget {
  final String roomId;

  const TeamRoomScreen({super.key, required this.roomId});

  @override
  ConsumerState<TeamRoomScreen> createState() => _TeamRoomScreenState();
}

class _TeamRoomScreenState extends ConsumerState<TeamRoomScreen> {
  // 동의 안내(A9)는 방 세션당 1회만.
  bool _consentShown = false;

  @override
  Widget build(BuildContext context) {
    // teams/history 양쪽 변화에 반응 — 멤버 추가·별칭 변경 즉시 반영.
    final rooms = ref.watch(teamsProvider);
    ref.watch(historyProvider);
    TeamRoom? found;
    for (final r in rooms) {
      if (r.id == widget.roomId) {
        found = r;
        break;
      }
    }
    final room = found;
    if (room == null) {
      return const Scaffold(backgroundColor: Colors.white);
    }
    final members = ref.read(teamsProvider.notifier).resolveMembers(room);
    final count = room.memberReportIds.length;
    final canMatrix = members.length >= TeamRoom.kMinMembers;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(room.title),
        actions: [
          if (!room.isClosed)
            IconButton(
              tooltip: '모임명 변경',
              onPressed: () => _showRenameDialog(room),
              icon: const FaIcon(
                FontAwesomeIcons.penToSquare,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 참여 진행 — n/12 + 권장 가이드 (A3).
              Row(
                children: [
                  Text(
                    '$count/${TeamRoom.kMaxMembers}명 참여',
                    style: AppText.subTitle,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (room.isClosed)
                    Text(
                      '발표 완료',
                      style: AppText.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.gold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: LinearProgressIndicator(
                  value: count / TeamRoom.kMaxMembers,
                  minHeight: 6,
                  backgroundColor: AppColors.surface,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '4~8명이 가장 재밌어요',
                style: AppText.hint,
              ),
              const SizedBox(height: AppSpacing.xl),
              // 멤버 칩 그리드 — 썸네일+이름, 방장 👑, 추가 칩.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (int i = 0; i < members.length; i++)
                    _MemberChip(
                      report: members[i],
                      isOwner: i == 0,
                      onLongPress: room.isClosed || i == 0
                          ? null
                          : () => _confirmRemove(room, members[i]),
                    ),
                  if (!room.isClosed &&
                      count < TeamRoom.kMaxMembers)
                    _AddChip(onTap: () => _scanLoop(room)),
                ],
              ),
              // 기본 배경 — 아직 방장 혼자면 team-chemistry-map.png 로
              // 빈 영역을 채운다 (홈 빈 상태와 동일 비주얼·토큰).
              if (members.length <= 1) ...[
                const SizedBox(height: AppSpacing.xl),
                Image.asset(
                  'assets/images/team-chemistry-map.png',
                  height: 200,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '멤버를 스캔하면 팀 케미 맵이 채워져요',
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.huge),
              // 액션 — [📷 직접 스캔] · [💬 카톡으로 초대] 나란히 (A6).
              if (!room.isClosed)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: count >= TeamRoom.kMaxMembers
                            ? null
                            : () => _scanLoop(room),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.textPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.surface,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.lg),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        icon: const FaIcon(FontAwesomeIcons.camera, size: 16),
                        label: const Text(
                          '직접 스캔',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: ElevatedButton.icon(
                        // P3(원격 경로)에서 활성화.
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          disabledBackgroundColor: AppColors.surface,
                          disabledForegroundColor: AppColors.textHint,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.lg),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        icon: const FaIcon(FontAwesomeIcons.comment, size: 16),
                        label: const Text(
                          '카톡 초대 (준비 중)',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              if (!room.isClosed) const SizedBox(height: AppSpacing.md),
              // 팀 케미 맵 보기 — 3명부터 (A7: 부분 공개, 마감과 무관).
              ElevatedButton(
                onPressed: canMatrix ? () => _openMatrix(room) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.surface,
                  disabledForegroundColor: AppColors.textHint,
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: Text(
                  canMatrix
                      ? '팀 케미 맵 보기'
                      : '${TeamRoom.kMinMembers}명부터 팀 케미 맵을 볼 수 있어요',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (!room.isClosed) ...[
                const SizedBox(height: AppSpacing.md),
                // 방장 [마감] — 두번째 강조 = outlined 검정 (3명 미만 비활성).
                OutlinedButton(
                  onPressed: canMatrix ? () => _confirmClose(room) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.textPrimary),
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: const Text(
                    '마감하고 베스트 페어 발표',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openMatrix(TeamRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamMatrixScreen(roomId: room.id),
      ),
    );
  }

  /// 연속 스캔 루프 (A6-B = C 의 장점 포함): 동의 안내 1회 → 촬영(앨범 숏컷
  /// 포함) → 확인 → 이름 붙이기 → "다음 사람"/"끝".
  Future<void> _scanLoop(TeamRoom room) async {
    if (!_consentShown) {
      final ok = await _showConsentDialog();
      if (!ok || !mounted) return;
      _consentShown = true;
    }
    while (mounted) {
      final current = ref.read(teamsProvider.notifier).byId(room.id);
      if (current == null ||
          current.memberReportIds.length >= TeamRoom.kMaxMembers) {
        return;
      }
      final report = await _captureOne();
      if (!mounted || report == null) return;
      final id = report.supabaseId;
      if (id == null) return;
      final added =
          await ref.read(teamsProvider.notifier).addMember(room.id, id);
      if (!mounted) return;
      if (!added) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.success(message: '이미 참여한 멤버예요'),
        );
        return;
      }
      await _showNameDialog(report);
      if (!mounted) return;
      final more = await _showNextDialog();
      if (!mounted || !more) return;
    }
  }

  /// 한 명 캡처 — 홈 [내 관상 만들기]와 동일한 카메라(좌하단 앨범 숏컷) 재사용.
  Future<FaceReadingReport?> _captureOne() async {
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
    if (!mounted || result == null) return null;
    CaptureResult? capture;
    if (result is FaceMeshAlbumRequest) {
      // 앨범 경로 — 기존 정책과 동일하게 로그인 게이트.
      if (!ref.read(authProvider.notifier).isLoggedIn) {
        final loggedIn = await showLoginBottomSheet(context, ref);
        if (!loggedIn || !mounted) return null;
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
    if (!mounted || capture == null) return null;
    final popped = await context.push(
      '/capture/confirm',
      extra: CaptureExtras(
        capture: capture,
        metadataFuture: capture.metadataFuture,
        popWithReport: true,
      ),
    );
    return popped is FaceReadingReport ? popped : null;
  }

  Future<bool> _showConsentDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('촬영 전 확인', style: AppText.modalTitle),
        content: const Text(
          '얼굴 촬영과 케미 분석은 본인 동의를 받은 뒤 진행해 주세요.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('동의 받았어요',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _showNameDialog(FaceReadingReport report) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('이름 붙이기', style: AppText.modalTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 10,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '예: 민지',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('건너뛰기',
                style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('저장',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
    controller.dispose();
    final id = report.supabaseId;
    if (name != null && name.isNotEmpty && id != null) {
      await ref.read(historyProvider.notifier).updateAliasById(id, name);
    }
  }

  Future<bool> _showNextDialog() async {
    final more = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('추가 완료', style: AppText.modalTitle),
        content: const Text('계속해서 다음 사람을 스캔할까요?',
            style: AppText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('끝', style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('다음 사람',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
    return more ?? false;
  }

  Future<void> _confirmRemove(TeamRoom room, FaceReadingReport member) async {
    final name = member.alias ??
        '${member.ageGroup.labelKo} ${member.gender.labelKo}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: Text('$name 님을 팀에서 뺄까요?', style: AppText.modalTitle),
        content: const Text('분석 기록은 관상 탭에 남아 있습니다.',
            style: AppText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('빼기', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && member.supabaseId != null) {
      await ref
          .read(teamsProvider.notifier)
          .removeMember(room.id, member.supabaseId!);
    }
  }

  Future<void> _confirmClose(TeamRoom room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('마감할까요?', style: AppText.modalTitle),
        content: const Text(
          '마감하면 멤버를 더 추가할 수 없고 베스트 페어가 발표됩니다.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('마감',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(teamsProvider.notifier).close(room.id);
      if (!mounted) return;
      _openMatrix(room);
    }
  }

  Future<void> _showRenameDialog(TeamRoom room) async {
    final controller = TextEditingController(text: room.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('모임명 변경', style: AppText.modalTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('저장',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      await ref.read(teamsProvider.notifier).rename(room.id, name);
    }
  }
}

/// 멤버 칩 — 썸네일(없으면 이니셜) + 이름, 방장 👑 (A6).
class _MemberChip extends StatelessWidget {
  final FaceReadingReport report;
  final bool isOwner;
  final VoidCallback? onLongPress;

  const _MemberChip({
    required this.report,
    required this.isOwner,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final name = report.alias ??
        '${report.ageGroup.labelKo} ${report.gender.labelKo}';
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _avatar(),
            const SizedBox(width: AppSpacing.sm),
            Text(
              isOwner ? '👑 $name' : name,
              style: AppText.caption.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    const size = 28.0;
    final file = ThumbnailPaths.resolveFileSync(report.thumbnailPath);
    if (file != null && file.existsSync()) {
      return ClipOval(
        child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.border,
      ),
      child: const Center(
        child: FaIcon(
          FontAwesomeIcons.user,
          size: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// 빈 자리 "+" 칩 — 탭 = 스캔 루프 (A6).
class _AddChip extends StatelessWidget {
  final VoidCallback onTap;

  const _AddChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
              ),
              child: const Center(
                child: FaIcon(
                  FontAwesomeIcons.plus,
                  size: 12,
                  color: AppColors.textHint,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '추가',
              style: AppText.caption.copyWith(color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }
}
