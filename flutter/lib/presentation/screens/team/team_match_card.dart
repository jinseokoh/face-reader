import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/team_service.dart';
import '../../../domain/models/team.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/primary_button.dart';
import 'team_chat_screen.dart';

/// 베스트 쌍 전용 매칭 성사 카드 — UX 문서 §E.2/§E.3.
/// fetchMatch + watchMatch 로 상태 파생, 상태 5종:
/// (i) 응답 전 — [채팅방 열기]/[이번엔 거부]
/// (ii) 나 수락·상대 대기 — 대기 카피
/// (iii) 성사(openedAt) — [채팅방 이동] → TeamChatScreen
/// (iv) 종결(한쪽 거절) — 주어 없는 종결 카피 (danger 색 미사용 — 실패 아님)
/// (v) 만료 — 발표(closedAt) 후 48시간 무응답 = 자동 거부 취급. 버튼 없이
///     종결 카피만 (서버 respond_match 의 MATCH_EXPIRED 와 같은 기준).
class TeamMatchCard extends StatefulWidget {
  final String teamId;
  final String otherUserId;
  final String otherNickname;
  final String otherGender;

  /// 결과 발표 시각(teams.closed_at) — 응답 시한(+48h) 판정의 기준.
  final DateTime? closedAt;

  const TeamMatchCard({
    super.key,
    required this.teamId,
    required this.otherUserId,
    required this.otherNickname,
    required this.otherGender,
    this.closedAt,
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

    // 응답 시한 경과 — 발표 후 48시간 (fetchPendingMatchProposals 와 동일
    // 계산). 이미 열린 채팅방은 만료와 무관하게 유지.
    final deadline = widget.closedAt?.add(matchResponseWindow);
    final expired =
        deadline != null && DateTime.now().toUtc().isAfter(deadline);

    final Widget footer;
    if (match.isOpen) {
      footer = _openFooter();
    } else if (theirConsent == false || myConsent == false) {
      footer = _closedFooter('이번에는 채팅방이 열리지 않았습니다');
    } else if (expired) {
      // 무응답 만료 = 자동 거부 취급 — 버튼 없이 종결 카피만.
      footer = _closedFooter('응답 기한(48시간)이 지나 채팅방이 열리지 않았습니다');
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
          const SizedBox(height: AppSpacing.xl),
          footer,
        ],
      ),
    );
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) _service.unwatch(ch);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _service.watchMatch(widget.teamId, _reloadMatch);
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
          // Stack 의 loose 제약에서 Column 이 내용 폭으로 줄어 왼쪽에 붙는
          // 문제 — full-width 강제로 타이틀·사진·상태 카피 전부 수평 중앙.
          child: SizedBox(width: double.infinity, child: child),
        ),
        // 우상단 공개 범위 고지 — 회색 최소 폰트(hint).
        Positioned(
          right: AppSpacing.md,
          top: AppSpacing.sm,
          child: Text(
            '이 카드는 매칭된 두 사람에게만 표시됩니다.',
            style: AppText.hint,
          ),
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

  /// 종결 — 누가 거절했는지 화면이 지목하지 않는 주어 없는 카피로 통일.
  /// 거절·만료가 첫 줄 문구만 다르고 같은 형식을 공유한다.
  Widget _closedFooter(String message) {
    return Column(
      children: [
        Text(
          message,
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _genderFallback() => Center(
    child: SvgPicture.asset(
      widget.otherGender == 'male'
          ? 'assets/svgs/male.svg'
          : 'assets/svgs/female.svg',
      height: 88,
      colorFilter: const ColorFilter.mode(
        AppColors.textHint,
        BlendMode.srcIn,
      ),
    ),
  );

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
          label: '채팅방 이동',
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

  Widget _questionFooter() {
    return Column(
      children: [
        Text(
          '${widget.otherNickname}님과 채팅방을 열까요?',
          // sectionTitle(16) → subTitle(14) 한 단계 다운.
          style: AppText.subTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '두 사람 모두 48시간 이내에 채팅방 열기를 선택하면 채팅방이 열립니다.',
          style: AppText.caption,
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: AppSpacing.lg),
        // 거부(좌) · 열기(우) — 한 줄 2버튼, 두 번째 강조는 outlined 원칙.
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: '이번엔 거부',
                onPressed: _responding ? null : () => _respond(false),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PrimaryButton(
                label: '채팅방 열기',
                busy: _responding,
                onPressed: () => _respond(true),
              ),
            ),
          ],
        ),
      ],
    );
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

  Widget _waitingFooter() {
    return Column(
      children: [
        Text(
          '${widget.otherNickname}님의 선택을 기다리고 있습니다',
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
