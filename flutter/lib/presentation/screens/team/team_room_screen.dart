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
import 'package:facely/presentation/screens/chemistry/album_capture_page.dart';
import 'package:facely/presentation/screens/chemistry/face_mesh_page.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import 'team_matrix_screen.dart';

/// 교감도 — 팀(방) 화면. PIVOT A6 방 화면 스펙:
/// 모임명 · 스캔 진행(scanned/total) · 멤버 그리드(스캔 완료=얼굴 / 대기=이름+
/// 점선 탭→스캔, walk-in [+]) · [직접촬영] · [카카오톡으로 초대](공유 시트) ·
/// [교감도 보기](스캔 3명↑) · 방장 [마감].
class TeamRoomScreen extends ConsumerStatefulWidget {
  final String roomId;

  const TeamRoomScreen({super.key, required this.roomId});

  @override
  ConsumerState<TeamRoomScreen> createState() => _TeamRoomScreenState();
}

/// 이름 정하기 다이얼로그 — 아직 안 찍힌 빈자리 이름을 칩으로 먼저 보여주고,
/// 원하는 이름이 없을 때만 [+ 직접 입력] 으로 텍스트 필드를 연다. 컨트롤러는
/// 이 State 의 dispose 에서만 해제 (닫힘 애니메이션 중 재사용 방지).
class _AssignNameDialog extends StatefulWidget {
  final List<({int index, String name})> pending;

  /// 그룹의 현재 멤버 이름 전체(스캔 완료 + 대기) — 직접 입력 중복 차단용.
  /// 이름이 서버 슬롯 키(team_id, name)라 중복은 push 충돌로 이어진다.
  final Set<String> taken;

  const _AssignNameDialog({required this.pending, required this.taken});

  @override
  State<_AssignNameDialog> createState() => _AssignNameDialogState();
}

class _AssignNameDialogState extends State<_AssignNameDialog> {
  final TextEditingController _controller = TextEditingController();
  // 빈자리가 없으면 처음부터 직접 입력만 노출.
  late bool _typing = widget.pending.isEmpty;
  String? _error;

  /// 직접 입력 저장 — 중복(명단 전체·예약어 '나')이면 다이얼로그를 유지한 채
  /// 오류 노출 (생성 페이지·그룹 설정과 동일 문구).
  void _submitFresh() {
    final name = _controller.text.trim();
    if (name.isNotEmpty && (name == '나' || widget.taken.contains(name))) {
      setState(
          () => _error = '같은 그룹내에 동일이름은 허용하지 않습니다.');
      return;
    }
    Navigator.pop(context, _NameChoice.fresh(name));
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
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppText.hint.copyWith(color: AppColors.danger),
              ),
            ],
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
            onPressed: _submitFresh,
            child: const Text('저장',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
  String? _nameError;

  bool get _canAddMore => _total < TeamRoom.kMaxMembers;
  int get _total => widget.scannedNames.length + _pending.length;

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
              // 생성 페이지와 동일한 중복 이름 안내 (hint + danger).
              if (_nameError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _nameError!,
                  style: AppText.hint.copyWith(color: AppColors.danger),
                ),
              ],
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
      setState(
          () => _nameError = '같은 그룹내에 동일이름은 허용하지 않습니다.');
      return;
    }
    setState(() {
      _pending.add(name);
      _nameError = null;
    });
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

  void _removeName(String name) => setState(() => _pending.remove(name));
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
    // 1순위 로컬 파일 → 2순위 CDN(thumbnailKey) → user 아이콘 (관상 리스트·
    // 궁합 아바타와 동일 3단). rehydrate 복원 내 관상·원격 합류 멤버는
    // thumbnailPath=null 이지만 thumbnailKey 로 실제 얼굴을 띄운다.
    const size = 56.0;
    final file = ThumbnailPaths.resolveFileSync(report!.thumbnailPath);
    if (file != null && file.existsSync()) {
      return ClipOval(
        child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
      );
    }
    final cdn = ThumbnailPaths.cdnUrl(report!.thumbnailKey);
    if (cdn != null) {
      return ClipOval(
        child: Image.network(
          cdn,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _iconAvatar(size),
        ),
      );
    }
    return _iconAvatar(size);
  }

  Widget _iconAvatar(double size) {
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

/// 직접촬영 후 이름 선택 결과 — [slotIndex] 가 있으면 기존 빈자리를 고른
/// 것(그 슬롯을 채움), null 이면 직접 입력한 새 멤버(walk-in).
class _NameChoice {
  final int? slotIndex;
  final String name;
  const _NameChoice.fresh(this.name) : slotIndex = null;
  const _NameChoice.slot(this.slotIndex, this.name);
}

class _TeamRoomScreenState extends ConsumerState<TeamRoomScreen> {
  // 동의 안내(A9)는 방 세션당 1회만.
  bool _consentShown = false;

  /// 진행 중인 초대 액션 라벨(타일 스피너·중복 차단용). null = idle.
  String? _busyInvite;

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
                  // 마감 = "완료" 금색 뱃지 ("나" 배지와 동일 idiom) —
                  // 결과표 생성 언어에 맞춰 "발표" 표기 폐기.
                  if (room.isClosed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        '완료',
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
                      report: notifier.reportForInRoom(room, i),
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
                // 직접촬영 — 아래 초대 타일과 같은 surface+border 타일 패밀리.
                _scanTile(
                  enabled: canAddMore,
                  onTap: () => _scanNewMember(room),
                ),
                const SizedBox(height: AppSpacing.md),
                // 초대 3종 — 카톡(친구) · 링크 공유(아무 채널/비연락처) · 복사.
                Row(
                  children: [
                    Expanded(
                      child: _inviteTile(
                        icon: FontAwesomeIcons.kakaoTalk,
                        label: '카톡 초대',
                        onTap: () => _inviteViaKakao(room),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _inviteTile(
                        icon: FontAwesomeIcons.shareNodes,
                        label: '링크 공유',
                        onTap: () => _shareInviteLink(room),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _inviteTile(
                        icon: FontAwesomeIcons.link,
                        label: '링크 복사',
                        onTap: () => _copyInviteLink(room),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              // 결과표는 "누가 발표하는 것"이 아니라 전원 등록 시 자동으로
              // 만들어지는 것 — 카피도 생성 언어로. 마감된 그룹이면 안내 라벨.
              if (room.isClosed) ...[
                Text(
                  '이미 결과표가 만들어진 그룹입니다.',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                ),
                const SizedBox(height: AppSpacing.sm),
              ] else ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    '${total - scanned}명 더 등록하면, 그룹 케미 결과표 생성',
                    textAlign: TextAlign.center,
                    style:
                        AppText.caption.copyWith(color: AppColors.textHint),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              // 버튼은 상태 무관 단일 — 안 만들어졌으면 탭 시 부족 인원
              // validation 안내 (조기 마감 경로 폐기, 2026-07-12).
              SecondaryButton(
                label: '생성된 케미 결과표 보기',
                onPressed: () {
                  if (room.isClosed) {
                    _openMatrix(room);
                  } else {
                    showTopSnackBar(
                      Overlay.of(context),
                      CompactSnackBar.error(
                        message:
                            '아직 ${total - scanned}명이 부족해 안 만들어졌어요.',
                      ),
                    );
                  }
                },
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

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

  /// walk-in 스캔 후 이름 정하기 — 아직 안 찍힌 빈자리(이름만 있는 슬롯)를
  /// 칩으로 먼저 고르게 하고, 거기 없을 때만 직접 입력. 반환: 빈자리 선택 시
  /// 그 인덱스+이름, 직접 입력 시 인덱스 null+입력 이름. 취소(barrier)면 null.
  Future<_NameChoice?> _chooseMemberName(
    List<({int index, String name})> pending,
    Set<String> taken,
  ) {
    return showDialog<_NameChoice>(
      context: context,
      builder: (_) => _AssignNameDialog(pending: pending, taken: taken),
    );
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

  void _copyInviteLink(TeamRoom room) => _runInvite(room, '링크 복사', (_) async {
        await Clipboard.setData(
          ClipboardData(text: SharePublisher.instance.teamInviteUrl(room.id)),
        );
        if (mounted) {
          showTopSnackBar(
            Overlay.of(context),
            CompactSnackBar.success(message: '링크를 복사했어요'),
          );
        }
      });

  Future<bool> _ensureConsent() async {
    if (_consentShown) return true;
    final ok = await _showConsentDialog();
    if (ok && mounted) _consentShown = true;
    return ok;
  }

  /// 초대 게이트 — 원격 합류은 서버 그룹이 전제라, 로그인 후 그룹을 서버로 push
  /// (lazy sync, P3). 통과해야 초대 링크가 살아있다. 복사·공유·카톡 공통.
  Future<bool> _ensureInviteReady(TeamRoom room) async {
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final ok = await showLoginBottomSheet(context, ref);
      if (!ok || !mounted) return false;
    }
    final pushed = await ref.read(teamsProvider.notifier).pushToServer(room.id);
    if (!pushed) {
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.success(message: '로그인이 필요해요'),
        );
      }
      return false;
    }
    return true;
  }

  Widget _inviteTile({
    required FaIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final busy = _busyInvite == label;
    final disabled = _busyInvite != null;
    return Opacity(
      opacity: disabled && !busy ? 0.4 : 1,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 22,
                child: Center(
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.textPrimary,
                            ),
                          ),
                        )
                      : FaIcon(icon, size: 20, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: AppText.caption.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _inviteViaKakao(TeamRoom room) => _runInvite(
        room,
        '카톡 초대',
        (origin) => SharePublisher.instance.publishTeamInvite(
          teamTitle: room.title,
          roomId: room.id,
          sharePositionOrigin: origin,
        ),
      );

  void _openMatrix(TeamRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamMatrixScreen(roomId: room.id),
      ),
    );
  }

  /// 초대 액션 공통 러너 — 게이트 통과 후 [deliver] 실행. [label] 타일에 스피너.
  Future<void> _runInvite(
    TeamRoom room,
    String label,
    Future<void> Function(Rect? origin) deliver,
  ) async {
    if (_busyInvite != null) return;
    // iOS 공유 시트 anchor — async gap 전에 미리 계산해 둔다.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    setState(() => _busyInvite = label);
    try {
      if (!await _ensureInviteReady(room)) return;
      await deliver(origin);
    } finally {
      if (mounted) setState(() => _busyInvite = null);
    }
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

  /// 직접촬영 → 빈자리 이름 칩에서 고르거나 직접 입력 → 슬롯 채움 or 추가.
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

    final choice =
        await _chooseMemberName(pending, {for (final m in room.members) m.name});
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

  /// 초대 아이콘 타일 — 등폭 모노톤(브랜드색 금지, §UI 통일). 진행 중이면 스피너,
  /// 다른 타일은 흐려서 비활성 표시.
  /// 직접촬영 — 초대 타일(_inviteTile)과 동일한 surface+border 디자인의
  /// 풀폭 타일 버튼. 같은 행동 패밀리 = 같은 시각 언어.
  Widget _scanTile({required bool enabled, required VoidCallback onTap}) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FaIcon(
                FontAwesomeIcons.solidCamera, // fill — regular(outline) 금지
                size: 16,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('직접촬영', style: AppText.subTitle),
            ],
          ),
        ),
      ),
    );
  }

  void _shareInviteLink(TeamRoom room) => _runInvite(
        room,
        '링크 공유',
        (origin) => SharePublisher.instance.shareTeamInviteLink(
          teamTitle: room.title,
          roomId: room.id,
          sharePositionOrigin: origin,
        ),
      );

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
