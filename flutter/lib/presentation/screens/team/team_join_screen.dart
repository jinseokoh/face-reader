import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/team_sync_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import 'team_room_screen.dart';

/// 초대받은 그룹 합류 화면 (P3 A7 원격 경로). 딥링크 `/g/{id}` 가 여기로 보낸다.
/// 서버에서 그룹을 미리보기로 fetch → 참여자 칩 + "당신 자리가 비어 있어요" →
/// [이 그룹에 참여]: 로그인 게이트 → 내 관상 확보(없으면 셀카) → joinRemoteTeam.
class TeamJoinScreen extends ConsumerStatefulWidget {
  final String teamId;

  const TeamJoinScreen({super.key, required this.teamId});

  @override
  ConsumerState<TeamJoinScreen> createState() => _TeamJoinScreenState();
}

class _TeamJoinScreenState extends ConsumerState<TeamJoinScreen> {
  RemoteTeam? _remote;
  bool _loading = true;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final remote =
          await ref.read(teamsProvider.notifier).peekRemoteTeam(widget.teamId);
      if (!mounted) return;
      setState(() {
        _remote = remote;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  FaceReadingReport? _findMyFace() {
    for (final r in ref.read(historyProvider)) {
      if (r.isMyFace) return r;
    }
    return null;
  }

  /// 합류. [slotName] 이 있으면 방장이 깐 그 대기 슬롯("까불이")으로 들어가
  /// 그 자리를 채운다(claim). 없으면 내 이름(닉네임)으로 새 멤버 합류.
  Future<void> _join({String? slotName}) async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      // 1) 로그인 게이트 — 원격 합류은 안정적 소유/멤버 식별이 필요.
      if (!ref.read(authProvider.notifier).isLoggedIn) {
        final ok = await showLoginBottomSheet(context, ref);
        if (!ok || !mounted) return;
      }
      // 2) 내 관상 확보 (없으면 셀카 등록).
      var myFace = _findMyFace();
      if (myFace == null) {
        await startMyFaceCapture(context, ref);
        if (!mounted) return;
        myFace = _findMyFace();
        if (myFace == null) return;
      }
      final reportId = myFace.supabaseId;
      if (reportId == null) return;
      // 3) 합류 — 슬롯 선택 시 그 이름으로(claim), 아니면 내 닉네임으로.
      final myName = slotName ??
          (ref.read(authProvider)?.nickname ?? myFace.alias ?? '게스트');
      final room = await ref.read(teamsProvider.notifier).joinRemoteTeam(
            widget.teamId,
            myReportId: reportId,
            myName: myName,
          );
      if (!mounted) return;
      if (room == null) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.success(message: '합류에 실패했어요'),
        );
        return;
      }
      // 4) 그룹 화면으로 교체 진입.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TeamRoomScreen(roomId: room.id)),
      );
    } catch (_) {
      // RLS(점유된 이름) · 중복 metrics 등 — 이미 참여했거나 그 이름은 사용 중.
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.success(message: '이미 참여했거나 사용 중인 이름이에요'),
        );
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final remote = _remote;
    if (remote == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Center(
          child: Text(
            '초대 링크가 만료되었거나 존재하지 않는 그룹이에요.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    // 등록 완료(점유) 멤버 vs 방장이 깐 빈 대기 슬롯(이름만).
    final joined = remote.members.where((m) => m.metricsId != null).toList();
    final pending = remote.members.where((m) => m.metricsId == null).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          Text(remote.title, style: AppText.display, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${joined.length}명 참여 중',
            style: AppText.caption.copyWith(color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
          if (joined.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [for (final m in joined) _memberChip(m.name)],
            ),
          ],
          // 방장이 미리 깔아둔 빈 자리 — 탭하면 그 이름으로 들어가 그 슬롯을 채운다.
          if (pending.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(
              '내 자리를 골라주세요',
              style: AppText.caption.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final m in pending)
                  _memberChip(m.name, onTap: () => _join(slotName: m.name)),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                const FaIcon(FontAwesomeIcons.userPlus,
                    size: 16, color: AppColors.textHint),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    pending.isNotEmpty
                        ? '내 이름이 위에 있으면 그 자리를 고르세요. 없으면 아래로 새로 참여할 수 있어요.'
                        : '얼굴을 등록하면 이 그룹 안에서 나와 케미가 가장 좋은 사람을 알 수 있어요.',
                    style:
                        AppText.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: pending.isNotEmpty ? '내 이름으로 새로 참여' : '이 그룹에 참여',
            busy: _joining,
            onPressed: _join,
          ),
        ],
      ),
    );
  }

  /// 단일톤 참여자 칩 — create/그룹설정 칩과 동일 토큰. [onTap] 있으면 탭 가능.
  Widget _memberChip(String name, {VoidCallback? onTap}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        name,
        style: AppText.body.copyWith(color: AppColors.textPrimary),
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: _joining ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: chip,
    );
  }
}
