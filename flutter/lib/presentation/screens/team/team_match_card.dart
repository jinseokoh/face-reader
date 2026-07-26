import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/team_service.dart';
import '../../../domain/models/team.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/primary_button.dart';
import 'team_chat_screen.dart';

/// 베스트 쌍 전용 매칭 성사 카드 — UX 문서 §E.2/§E.3.
/// fetchMatch + watchMatch 로 상태 파생, 상태 4종:
/// (i) 응답 전 — [채팅방 열기]/[이번에는 넘어가기]
/// (ii) 나 수락·상대 대기 — 대기 카피
/// (iii) 성사(openedAt) — [채팅 시작하기] → TeamChatScreen
/// (iv) 종결(한쪽 거절) — 주어 없는 종결 카피 (danger 색 미사용 — 실패 아님)
class TeamMatchCard extends StatefulWidget {
  final String teamId;
  final String otherUserId;
  final String otherNickname;
  final String otherGender;

  const TeamMatchCard({
    super.key,
    required this.teamId,
    required this.otherUserId,
    required this.otherNickname,
    required this.otherGender,
  });

  @override
  State<TeamMatchCard> createState() => _TeamMatchCardState();
}

class _TeamMatchCardState extends State<TeamMatchCard> {
  final _service = TeamService.instance;
  TeamMatch? _match;
  String? _photoUrl;
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _service.watchMatch(widget.teamId, _reloadMatch);
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) _service.unwatch(ch);
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.fetchMatch(widget.teamId),
      _service.fetchMyFaceThumbnailUrls([widget.otherUserId]),
    ]);
    if (!mounted) return;
    setState(() {
      _match = results[0] as TeamMatch?;
      _photoUrl =
          (results[1] as Map<String, MyFaceThumb>)[widget.otherUserId]?.url;
      _loading = false;
    });
  }

  Future<void> _reloadMatch() async {
    final match = await _service.fetchMatch(widget.teamId);
    if (!mounted) return;
    setState(() => _match = match);
  }

  Future<void> _respond(bool accept) async {
    setState(() => _responding = true);
    try {
      await _service.respondMatch(widget.teamId, accept);
      await _reloadMatch();
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: mapTeamError(e).labelKo),
        );
      }
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _card(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final match = _match;
    // best 쌍 중 한 명 계정 삭제 등으로 매치 행이 사라진 경우 — 카드 자체 비노출.
    if (match == null) return const SizedBox.shrink();

    final myUid = _service.myUid;
    final myConsent = myUid == null ? null : match.consentOf(myUid);
    final theirConsent = myUid == null
        ? null
        : match.consentOf(match.otherOf(myUid));

    final Widget footer;
    if (match.isOpen) {
      footer = _openFooter();
    } else if (theirConsent == false || myConsent == false) {
      footer = _closedFooter();
    } else if (myConsent == true) {
      footer = _waitingFooter();
    } else {
      footer = _questionFooter();
    }

    return _card(
      child: Column(
        children: [
          // display(28) → appBarTitle(20) 한 단계 다운 — SongMyung 계열 유지.
          Text(
            '${widget.otherNickname}님과 매칭되었습니다',
            style: AppText.appBarTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          _photo(),
          const SizedBox(height: AppSpacing.sm),
          Text(widget.otherNickname, style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          // hint → caption 한 단계 업 — 사진 공개 범위 고지는 읽혀야 한다.
          Text('이 사진은 매칭된 두 사람에게만 보입니다', style: AppText.caption),
          const SizedBox(height: AppSpacing.xl),
          footer,
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    // 코너 태그가 카드 radius 밖으로 삐져나가지 않게 clip.
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      // 베스트 매칭 강조 — 방장 링과 같은 gold 토큰.
      border: Border.all(color: AppColors.gold),
    ),
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.huge,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: child,
        ),
        // 좌상단 gold 코너 태그 — 베스트 케미 카드와 동일 레시피.
        Positioned(
          left: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: const BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.only(
                bottomRight: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Text(
              '베스트 매칭',
              style: AppText.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// 상대 200×200 얼굴 사진 — 실패 시 성별 아이콘.
  /// border 는 foregroundDecoration — decoration 에 두면 child(이미지)가
  /// 곡선 구간에서 테두리 안쪽 절반을 덮어 코너가 끊겨 보인다.
  Widget _photo() {
    return Container(
      width: 200,
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: _photoUrl == null
          ? _genderFallback()
          : Image.network(
              _photoUrl!,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _genderFallback(),
            ),
    );
  }

  Widget _genderFallback() => Center(
    child: Image.asset(
      widget.otherGender == 'male'
          ? 'assets/icons/male.png'
          : 'assets/icons/female.png',
      width: 88,
      height: 88,
    ),
  );

  Widget _questionFooter() {
    return Column(
      children: [
        Text(
          '${widget.otherNickname}님과 채팅방을 열까요?',
          style: AppText.sectionTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '두 사람 모두 열기를 선택하면 채팅방이 열립니다. 응답은 결과 발표 후 '
          '48시간 동안 가능하고, 선택은 되돌릴 수 없습니다.',
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: '채팅방 열기',
          busy: _responding,
          onPressed: () => _respond(true),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: _responding ? null : () => _respond(false),
          child: Text(
            '이번에는 넘어가기',
            style: AppText.body.copyWith(color: AppColors.textHint),
          ),
        ),
      ],
    );
  }

  Widget _waitingFooter() {
    return Column(
      children: [
        Text(
          '${widget.otherNickname}님의 선택을 기다리고 있습니다',
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '채팅방이 열리면 이 화면과 매칭 결과에서 들어갈 수 있습니다',
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _openFooter() {
    return Column(
      children: [
        // 상태 고지 계열은 전부 caption 하나 — 사진 공개 고지와 동일 토큰.
        Text(
          '채팅방이 열렸습니다',
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: '채팅 시작하기',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TeamChatScreen(
                teamId: widget.teamId,
                otherUserId: widget.otherUserId,
                otherNickname: widget.otherNickname,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 종결 — 누가 거절했는지 화면이 지목하지 않는 주어 없는 카피로 통일.
  Widget _closedFooter() {
    return Column(
      children: [
        Text(
          '이번에는 채팅방이 열리지 않았습니다',
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        // 30일 purge 정책과 일치하는 사실 카피 ('계속' 은 허위였음).
        Text(
          '결과표는 30일간 유효합니다',
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
