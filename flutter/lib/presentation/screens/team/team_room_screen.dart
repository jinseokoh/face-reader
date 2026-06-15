import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/config/router.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/domain/services/share/share_publisher.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/screens/home/album_capture_page.dart';
import 'package:facely/presentation/screens/home/face_mesh_page.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import 'team_matrix_screen.dart';

/// 교감도 — 팀(방) 화면. PIVOT A6 방 화면 스펙:
/// 모임명 · 스캔 진행(scanned/total) · 멤버 그리드(스캔 완료=얼굴 / 대기=이름+
/// 점선 탭→스캔, walk-in [+]) · [멤버 직접 스캔] · [카카오톡으로 초대](공유 시트) ·
/// [교감도 보기](스캔 3명↑) · 방장 [마감].
class TeamRoomScreen extends ConsumerStatefulWidget {
  final String roomId;

  const TeamRoomScreen({super.key, required this.roomId});

  @override
  ConsumerState<TeamRoomScreen> createState() => _TeamRoomScreenState();
}

/// 빈 자리 점선 원 — Flutter 기본 위젯엔 점선 테두리가 없어 직접 그린다.
class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    const dashCount = 28;
    const sweep = 6.283185307179586 / dashCount; // 2π / n
    for (int i = 0; i < dashCount; i++) {
      final start = sweep * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 0.75),
        start,
        sweep * 0.55, // dash 길이 (gap 0.45)
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) => false;
}

/// 멤버 셀 — 스캔 완료면 얼굴 아바타, 대기(미스캔)면 이름 + 점선 빈 원(탭→스캔).
/// 방장은 gold 테두리 + 좌상단 "나" 배지. 길게 눌러 제거(방장 제외).
class _MemberCell extends StatelessWidget {
  final TeamMember member;
  final FaceReadingReport? report;
  final bool isOwner;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _MemberCell({
    super.key,
    required this.member,
    required this.report,
    required this.isOwner,
    this.onTap,
    this.onLongPress,
  });

  bool get _scanned => member.isScanned && report != null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isOwner
                      ? Border.all(color: AppColors.gold, width: 2)
                      : null,
                ),
                padding: const EdgeInsets.all(2),
                child: _scanned ? _faceAvatar() : _pendingAvatar(),
              ),
              if (isOwner)
                Positioned(
                  left: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs + 1, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '나',
                      style: AppText.hint.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: _scanned ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _faceAvatar() {
    const size = 56.0;
    final file = ThumbnailPaths.resolveFileSync(report!.thumbnailPath);
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
        color: AppColors.surface,
      ),
      child: const Center(
        child: FaIcon(FontAwesomeIcons.user,
            size: 20, color: AppColors.textHint),
      ),
    );
  }

  /// 대기 멤버 — 점선 빈 원 안에 카메라 아이콘 (탭하면 스캔).
  Widget _pendingAvatar() {
    return SizedBox(
      width: 56,
      height: 56,
      child: CustomPaint(
        painter: _DashedCirclePainter(),
        child: const Center(
          child: FaIcon(FontAwesomeIcons.camera,
              size: 16, color: AppColors.textHint),
        ),
      ),
    );
  }
}

class _TeamRoomScreenState extends ConsumerState<TeamRoomScreen> {
  // 동의 안내(A9)는 방 세션당 1회만.
  bool _consentShown = false;
  bool _inviting = false;

  @override
  void initState() {
    super.initState();
    // 입장 시 서버 폴링 (P3) — push 된 그룹이면 합류자·마감을 끌어온다.
    // 로컬 전용 그룹은 fetch 가 null 이라 no-op. best-effort.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(teamsProvider.notifier)
          .refreshFromServer(widget.roomId)
          .catchError((_) => null);
    });
  }

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
    final notifier = ref.read(teamsProvider.notifier);
    final total = room.members.length;
    final scanned = room.scannedCount;
    final canMatrix = scanned >= TeamRoom.kMinMembers;
    final canAddMore = !room.isClosed && total < TeamRoom.kMaxMembers;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(room.title),
        actions: [
          if (!room.isClosed)
            IconButton(
              tooltip: '그룹 설정',
              onPressed: () => _showGroupSettings(room),
              icon: const FaIcon(
                FontAwesomeIcons.gear,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          // 당겨서 새로고침 — push 된 그룹이면 합류자·마감을 서버에서 끌어온다.
          onRefresh: () async {
            await ref
                .read(teamsProvider.notifier)
                .refreshFromServer(widget.roomId);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // 스캔 진행 — 명단 중 몇 명을 찍었나.
              Row(
                children: [
                  Text('$scanned/$total명 등록', style: AppText.subTitle),
                  const SizedBox(width: AppSpacing.sm),
                  // 마감 = "마감" 금색 뱃지 ("나" 배지와 동일 idiom).
                  if (room.isClosed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        '마감',
                        style: AppText.hint.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : scanned / total,
                  minHeight: 6,
                  backgroundColor: AppColors.surface,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('참여 멤버', style: AppText.subTitle),
              const SizedBox(height: AppSpacing.lg),
              // 멤버 그리드 — 스캔 완료(얼굴) / 대기(이름+빈 점선, 탭→스캔).
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.lg,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 0.78,
                children: [
                  for (int i = 0; i < room.members.length; i++)
                    _MemberCell(
                      key: ValueKey(room.members[i].reportId ??
                          'pending:${room.members[i].name}'),
                      member: room.members[i],
                      report: notifier.reportFor(room.members[i]),
                      isOwner: i == 0,
                      onTap: room.isClosed || room.members[i].isScanned
                          ? null
                          : () => _scanIntoSlot(room, i),
                      onLongPress: room.isClosed || i == 0
                          ? null
                          : () => _confirmRemove(room, i),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.huge),
              // 액션 — 풀폭 스택.
              if (!room.isClosed) ...[
                PrimaryButton(
                  label: '멤버 직접 등록',
                  icon: FontAwesomeIcons.camera,
                  onPressed: canAddMore ? () => _scanNewMember(room) : null,
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: '카카오톡으로 초대',
                  icon: FontAwesomeIcons.comment,
                  busy: _inviting,
                  onPressed: () => _inviteViaKakao(room),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              // 마감된 그룹이면 버튼 위에 작은 안내 라벨.
              if (room.isClosed) ...[
                Text(
                  '이미 마감된 그룹입니다.',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              // 그룹 케미 보기 — 스캔 3명부터 (A7: 부분 공개, 마감과 무관).
              // 인원 미달이면 버튼 대신 배경 없는 작은 안내 텍스트.
              if (canMatrix)
                PrimaryButton(
                  label: '그룹 케미 보기',
                  onPressed: () => _openMatrix(room),
                )
              else
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    '앞으로 ${total - scanned}명 더 등록하면 마감됩니다',
                    textAlign: TextAlign.center,
                    style:
                        AppText.caption.copyWith(color: AppColors.textHint),
                  ),
                ),
              // 수동 마감 — 전원 스캔 완료 전에만. 완료 시 자동 마감되므로 숨김.
              if (!room.isClosed && scanned < total) ...[
                const SizedBox(height: AppSpacing.md),
                SecondaryButton(
                  label: '마감하고 결과 발표',
                  onPressed: canMatrix ? () => _confirmClose(room) : null,
                ),
              ],
            ],
            ),
          ),
        ),
      ),
    );
  }

  /// walk-in 스캔 후 이름 정하기 — 아직 안 찍힌 빈자리(이름만 있는 슬롯)를
  /// 칩으로 먼저 고르게 하고, 거기 없을 때만 직접 입력. 반환: 빈자리 선택 시
  /// 그 인덱스+이름, 직접 입력 시 인덱스 null+입력 이름. 취소(barrier)면 null.
  Future<_NameChoice?> _chooseMemberName(List<({int index, String name})> pending) {
    return showDialog<_NameChoice>(
      context: context,
      builder: (_) => _AssignNameDialog(pending: pending),
    );
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

  Future<void> _confirmRemove(TeamRoom room, int index) async {
    if (index <= 0 || index >= room.members.length) return;
    final name = room.members[index].name;
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
    if (ok == true) {
      await ref.read(teamsProvider.notifier).removeMemberAt(room.id, index);
    }
  }

  Future<bool> _ensureConsent() async {
    if (_consentShown) return true;
    final ok = await _showConsentDialog();
    if (ok && mounted) _consentShown = true;
    return ok;
  }

  /// 카카오 공유 시트로 초대 — 원격 합류은 서버 그룹이 전제라, 로그인 게이트 후
  /// 그룹을 서버로 push 하고 링크를 보낸다 (lazy sync, P3).
  Future<void> _inviteViaKakao(TeamRoom room) async {
    if (_inviting) return;
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final ok = await showLoginBottomSheet(context, ref);
      if (!ok || !mounted) return;
    }
    setState(() => _inviting = true);
    try {
      final pushed =
          await ref.read(teamsProvider.notifier).pushToServer(room.id);
      if (!pushed) {
        if (mounted) {
          showTopSnackBar(
            Overlay.of(context),
            CompactSnackBar.success(message: '로그인이 필요해요'),
          );
        }
        return;
      }
      await SharePublisher.instance
          .publishTeamInvite(teamTitle: room.title, roomId: room.id);
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  void _openMatrix(TeamRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamMatrixScreen(roomId: room.id),
      ),
    );
  }

  /// 대기 슬롯(이름만) 을 스캔으로 채운다 — 동의 1회 → 촬영 → 해당 슬롯에 부여.
  Future<void> _scanIntoSlot(TeamRoom room, int index) async {
    if (!await _ensureConsent() || !mounted) return;
    final report = await _captureOne();
    if (!mounted || report == null) return;
    final id = report.supabaseId;
    if (id == null) return;
    final ok =
        await ref.read(teamsProvider.notifier).fillSlot(room.id, index, id);
    if (!mounted) return;
    if (!ok) {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.success(message: '이미 참여한 얼굴이에요'),
      );
      return;
    }
    // 슬롯 이름을 카드 별칭으로도 반영 (관상 탭 표시 일관).
    final name = ref.read(teamsProvider.notifier).byId(room.id)?.members[index].name;
    if (name != null && name.isNotEmpty) {
      await ref.read(historyProvider.notifier).updateAliasById(id, name);
    }
  }

  /// 멤버 직접 스캔 → 빈자리 이름 칩에서 고르거나 직접 입력 → 슬롯 채움 or 추가.
  Future<void> _scanNewMember(TeamRoom room) async {
    if (!await _ensureConsent() || !mounted) return;
    final report = await _captureOne();
    if (!mounted || report == null) return;
    final id = report.supabaseId;
    if (id == null) return;

    // 아직 안 찍힌 빈자리(이름만 있는 슬롯) — 방장(0) 제외.
    final pending = <({int index, String name})>[
      for (int i = 1; i < room.members.length; i++)
        if (!room.members[i].isScanned && room.members[i].name.isNotEmpty)
          (index: i, name: room.members[i].name),
    ];

    final choice = await _chooseMemberName(pending);
    if (!mounted || choice == null) return;

    final notifier = ref.read(teamsProvider.notifier);
    // 직접 입력한 이름이 빈자리와 같으면 그 자리를 채운다 (중복 슬롯 방지).
    int? slotIndex = choice.slotIndex;
    if (slotIndex == null && choice.name.isNotEmpty) {
      for (final p in pending) {
        if (p.name == choice.name) {
          slotIndex = p.index;
          break;
        }
      }
    }
    final aliasName = choice.name;
    final bool ok;
    if (slotIndex != null) {
      // 빈자리 → 그 슬롯을 이 얼굴로 채운다.
      ok = await notifier.fillSlot(room.id, slotIndex, id);
    } else {
      // 명단에 없는 새 멤버 → walk-in 추가.
      ok = await notifier.addScannedMember(
        room.id,
        name: aliasName.isEmpty ? '게스트' : aliasName,
        reportId: id,
      );
    }
    if (!mounted) return;
    if (!ok) {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.success(message: '이미 참여한 얼굴이에요'),
      );
      return;
    }
    if (aliasName.isNotEmpty) {
      await ref.read(historyProvider.notifier).updateAliasById(id, aliasName);
    }
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

  /// 그룹 설정 — 그룹명 + 멤버 명단(명수) 편집. 방장·스캔 완료는 보존,
  /// 대기 이름만 추가/삭제. 저장 시 provider 가 명단을 통째 갱신.
  Future<void> _showGroupSettings(TeamRoom room) async {
    final scannedNames = [
      for (final m in room.members)
        if (m.isScanned) m.name,
    ];
    final pending = [
      for (final m in room.members)
        if (!m.isScanned) m.name,
    ];
    final result = await showDialog<({String title, List<String> pending})>(
      context: context,
      builder: (_) => _GroupSettingsDialog(
        initialTitle: room.title,
        scannedNames: scannedNames,
        initialPending: pending,
      ),
    );
    if (result == null || !mounted) return;
    final title = result.title.isEmpty ? room.title : result.title;
    await ref
        .read(teamsProvider.notifier)
        .updateRoster(room.id, title: title, pendingNames: result.pending);
  }
}

/// 그룹 설정 다이얼로그 — 그룹명 + 멤버 명단(명수) 편집. 방장·스캔 완료
/// 멤버는 제거 불가 칩(얼굴 보유, 그리드 길게눌러 제거)으로 표시하고, 대기
/// 이름만 X 로 빼거나 새로 추가한다. 컨트롤러는 이 State 의 dispose 에서만
/// 해제 (닫힘 애니메이션 중 재사용 방지). 취소=null, 저장=(제목, 대기명단).
class _GroupSettingsDialog extends StatefulWidget {
  final String initialTitle;
  final List<String> scannedNames;
  final List<String> initialPending;

  const _GroupSettingsDialog({
    required this.initialTitle,
    required this.scannedNames,
    required this.initialPending,
  });

  @override
  State<_GroupSettingsDialog> createState() => _GroupSettingsDialogState();
}

class _GroupSettingsDialogState extends State<_GroupSettingsDialog> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.initialTitle);
  final TextEditingController _nameController = TextEditingController();
  late final List<String> _pending = [...widget.initialPending];

  int get _total => widget.scannedNames.length + _pending.length;
  bool get _canAddMore => _total < TeamRoom.kMaxMembers;

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// 대기 이름 추가 — 공백·중복(스캔/대기·예약어 '나')·하드캡 12 차단.
  void _addName([String? raw]) {
    final name = (raw ?? _nameController.text).trim();
    _nameController.clear();
    if (name.isEmpty || !_canAddMore) return;
    if (name == '나' ||
        _pending.contains(name) ||
        widget.scannedNames.contains(name)) {
      return;
    }
    setState(() => _pending.add(name));
  }

  void _removeName(String name) => setState(() => _pending.remove(name));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      title: const Text('그룹 설정', style: AppText.modalTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('그룹명',
                style: AppText.caption.copyWith(color: AppColors.textHint)),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _titleController,
              maxLength: 20,
              style: AppText.body.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(counterText: ''),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('멤버 ($_total/${TeamRoom.kMaxMembers})',
                style: AppText.caption.copyWith(color: AppColors.textHint)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final n in widget.scannedNames) _chip(n, null),
                for (final n in _pending) _chip(n, () => _removeName(n)),
              ],
            ),
            if (_canAddMore) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.done,
                maxLength: 10,
                style: AppText.body.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '이름 입력 후 엔터',
                  hintStyle: AppText.body.copyWith(color: AppColors.textHint),
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
                    color: AppColors.textPrimary,
                    onPressed: () => _addName(),
                  ),
                ),
                onSubmitted: _addName,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              const Text('취소', style: TextStyle(color: AppColors.textHint)),
        ),
        TextButton(
          onPressed: () {
            if (_nameController.text.trim().isNotEmpty) _addName();
            Navigator.pop(
              context,
              (
                title: _titleController.text.trim(),
                pending: List<String>.from(_pending),
              ),
            );
          },
          child: const Text('저장',
              style: TextStyle(color: AppColors.textPrimary)),
        ),
      ],
    );
  }

  /// 단일톤 멤버 칩 — 생성 페이지 _MemberChip 과 동일 토큰. onRemove 없으면
  /// 제거 불가(방장·스캔 완료).
  Widget _chip(String name, VoidCallback? onRemove) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs + 1,
        onRemove != null ? AppSpacing.sm : AppSpacing.md,
        AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              style: AppText.body.copyWith(color: AppColors.textPrimary)),
          if (onRemove != null) ...[
            const SizedBox(width: AppSpacing.xs),
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: FaIcon(FontAwesomeIcons.xmark,
                    size: 12, color: AppColors.textHint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 멤버 직접 스캔 후 이름 선택 결과 — [slotIndex] 가 있으면 기존 빈자리를 고른
/// 것(그 슬롯을 채움), null 이면 직접 입력한 새 멤버(walk-in).
class _NameChoice {
  final int? slotIndex;
  final String name;
  const _NameChoice.slot(this.slotIndex, this.name);
  const _NameChoice.fresh(this.name) : slotIndex = null;
}

/// 이름 정하기 다이얼로그 — 아직 안 찍힌 빈자리 이름을 칩으로 먼저 보여주고,
/// 원하는 이름이 없을 때만 [+ 직접 입력] 으로 텍스트 필드를 연다. 컨트롤러는
/// 이 State 의 dispose 에서만 해제 (닫힘 애니메이션 중 재사용 방지).
class _AssignNameDialog extends StatefulWidget {
  final List<({int index, String name})> pending;

  const _AssignNameDialog({required this.pending});

  @override
  State<_AssignNameDialog> createState() => _AssignNameDialogState();
}

class _AssignNameDialogState extends State<_AssignNameDialog> {
  final TextEditingController _controller = TextEditingController();
  // 빈자리가 없으면 처음부터 직접 입력만 노출.
  late bool _typing = widget.pending.isEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPending = widget.pending.isNotEmpty;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      title: const Text('누구인가요?', style: AppText.modalTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPending) ...[
            Text(
              '명단에서 고르기',
              style: AppText.caption.copyWith(color: AppColors.textHint),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final p in widget.pending)
                  _pill(
                    p.name,
                    () => Navigator.pop(
                        context, _NameChoice.slot(p.index, p.name)),
                  ),
                if (!_typing)
                  _pill('+ 직접 입력', () => setState(() => _typing = true)),
              ],
            ),
          ],
          if (_typing) ...[
            if (hasPending) const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 10,
              style: AppText.body.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '예) 성주',
                hintStyle: AppText.body.copyWith(color: AppColors.textHint),
                counterText: '',
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const _NameChoice.fresh('')),
          child: const Text('건너뛰기',
              style: TextStyle(color: AppColors.textHint)),
        ),
        if (_typing)
          TextButton(
            onPressed: () => Navigator.pop(
                context, _NameChoice.fresh(_controller.text.trim())),
            child: const Text('저장',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
      ],
    );
  }

  /// 단일톤 선택 pill (§3.3) — 명단 이름·직접입력 토글 공용.
  Widget _pill(String label, VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 1,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
