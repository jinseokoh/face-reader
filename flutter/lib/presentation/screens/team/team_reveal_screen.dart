import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/battle.dart' as engine;
import 'package:face_engine/domain/services/compat/compat_adapter.dart';

import '../../../config/router.dart';
import '../../../core/storage/thumbnail_paths.dart';
import '../../../core/theme.dart';
import '../../../data/services/battle_service.dart';
import '../../../domain/models/battle.dart';
import '../../providers/auth_provider.dart';
import '../../providers/battle_provider.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/primary_button.dart';
import '../compatibility/compat_unlock_action.dart';
import 'battle_band.dart';
import 'battle_match_card.dart';

/// 배틀 결과 — payload(스코어보드)가 없으면 snapshot 으로 계산해 1회 기록
/// (first-writer-wins)하고, 있으면 그대로 렌더한다.
class TeamRevealScreen extends ConsumerStatefulWidget {
  final String battleId;
  final bool ceremony;
  const TeamRevealScreen(
      {super.key, required this.battleId, this.ceremony = false});

  @override
  ConsumerState<TeamRevealScreen> createState() => _TeamRevealScreenState();
}

enum _Phase { loading, countdown, board, orphan }

class _TeamRevealScreenState extends ConsumerState<TeamRevealScreen> {
  final _service = BattleService.instance;
  _Phase _phase = _Phase.loading;
  int _count = 3;
  Battle? _battle;
  Map<String, dynamic>? _payload;
  List<BattleRosterEntry> _roster = const [];
  int? _mySlot;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final battle = await _service.fetchBattle(widget.battleId);
    if (!mounted) return;
    if (battle == null) {
      Navigator.of(context).maybePop();
      return;
    }
    final roster = await _service.fetchRoster(widget.battleId);
    if (!mounted) return;
    Map<String, dynamic>? payload = battle.resultPayload;
    if (payload == null) {
      final snapshot = battle.chemistrySnapshot;
      if (snapshot == null) {
        // revealing 고아(스냅샷 부재는 구조상 없지만 completed+payload null 안전망).
        setState(() {
          _battle = battle;
          _phase = _Phase.orphan;
        });
        return;
      }
      final players =
          assembleBattlePlayers(roster: roster, snapshot: snapshot);
      if (players.length < 2) {
        setState(() {
          _battle = battle;
          _phase = _Phase.orphan;
        });
        return;
      }
      payload = engine
          .computeBattle(players,
              matchOnly: battle.roomKind == BattleRoomKind.match)
          .toPayload();
      // 결정론 — 선착 기록만 유효, 실패(후착·비참가자)는 무해.
      try {
        await _service.submitResult(widget.battleId, payload);
      } catch (_) {}
      if (!mounted) return;
      ref.invalidate(myBattlesProvider);
    }
    if (!mounted) return;
    final myUid = _service.myUid;
    int? mySlot;
    for (final r in roster) {
      if (r.userId == myUid) mySlot = r.slotNo;
    }
    setState(() {
      _battle = battle;
      _payload = payload;
      _roster = roster;
      _mySlot = mySlot;
      _phase = widget.ceremony ? _Phase.countdown : _Phase.board;
    });
    if (widget.ceremony) _tickCountdown();
  }

  void _tickCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_count <= 1) {
        t.cancel();
        setState(() => _phase = _Phase.board);
      } else {
        setState(() => _count--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ── payload 파생 ──────────────────────────────────────────────
  List<Map<String, dynamic>> get _players =>
      [for (final p in _payload!['players'] as List) p as Map<String, dynamic>];
  List<Map<String, dynamic>> get _pairs =>
      [for (final p in _payload!['pairs'] as List) p as Map<String, dynamic>];
  Map<String, dynamic> get _best => _payload!['best'] as Map<String, dynamic>;

  String _nameOf(int slot) {
    for (final p in _players) {
      if (p['slot'] == slot) return p['name'] as String;
    }
    return '참가자';
  }

  String? _genderOf(int slot) {
    for (final p in _players) {
      if (p['slot'] == slot) return p['gender'] as String?;
    }
    return null;
  }

  /// 뷰어가 베스트 쌍 본인이면 상대 (userId, slot) — 아니면 null.
  ({String userId, int slot})? get _bestMatchOther {
    final myUid = _service.myUid;
    if (myUid == null) return null;
    final a = (_best['a'] as num).toInt();
    final b = (_best['b'] as num).toInt();
    String? uidOf(int slot) {
      for (final r in _roster) {
        if (r.slotNo == slot) return r.userId;
      }
      return null;
    }

    final uidA = uidOf(a);
    final uidB = uidOf(b);
    if (uidA == myUid && uidB != null) return (userId: uidB, slot: b);
    if (uidB == myUid && uidA != null) return (userId: uidA, slot: a);
    return null;
  }

  int? _bandOf(int a, int b) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    for (final p in _pairs) {
      if (p['a'] == lo && p['b'] == hi) return (p['band'] as num).toInt();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_battle?.title ?? '케미 배틀')),
      body: SafeArea(
        top: false,
        child: switch (_phase) {
          _Phase.loading =>
            const Center(child: CircularProgressIndicator()),
          _Phase.countdown => Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text('$_count',
                    key: ValueKey(_count), style: AppText.display),
              ),
            ),
          _Phase.orphan => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.huge),
                child: Text('결과가 생성되지 않은 배틀입니다',
                    style: AppText.body, textAlign: TextAlign.center),
              ),
            ),
          _Phase.board => _board(),
        },
      ),
    );
  }

  Widget _board() {
    final matchOther = _bestMatchOther;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _bestCard(),
        if (matchOther != null) ...[
          const SizedBox(height: AppSpacing.xl),
          BattleMatchCard(
            teamId: widget.battleId,
            otherUserId: matchOther.userId,
            otherNickname: _nameOf(matchOther.slot),
            otherGender: _genderOf(matchOther.slot) ?? 'male',
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text('상호 케미 맵', style: AppText.sectionTitle),
        const SizedBox(height: AppSpacing.md),
        _matrix(),
        if (_mySlot != null) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('나와의 케미 순위', style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.md),
          ..._myRanking(),
        ],
        const SizedBox(height: AppSpacing.xl),
        _legend(),
      ],
    );
  }

  Widget _bestCard() {
    final a = (_best['a'] as num).toInt();
    final b = (_best['b'] as num).toInt();
    final score = (_best['score'] as num).toInt();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.textPrimary),
      ),
      child: Column(
        children: [
          Text('🏆 베스트 케미', style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.md),
          Text('${_nameOf(a)} × ${_nameOf(b)}', style: AppText.display),
          const SizedBox(height: AppSpacing.sm),
          Text('$score점', style: AppText.modalTitle),
        ],
      ),
    );
  }

  /// 뷰어 행 최상단 고정 매트릭스 — 셀 = 밴드 색 점.
  /// match 방은 남(행)×여(열) 직사각(동성 쌍 부재) — 뷰어가 포함된 성별을
  /// 행 축으로 삼는다. all 방은 기존 정방 유지.
  Widget _matrix() {
    final rows = <int>[];
    final cols = <int>[];
    if (_battle?.roomKind == BattleRoomKind.match) {
      final males = <int>[];
      final females = <int>[];
      for (final p in _players) {
        final slot = (p['slot'] as num).toInt();
        if (p['gender'] == 'male') {
          males.add(slot);
        } else {
          females.add(slot);
        }
      }
      final myGender = _mySlot == null ? null : _genderOf(_mySlot!);
      if (myGender == 'female') {
        rows.addAll(females);
        cols.addAll(males);
      } else {
        rows.addAll(males);
        cols.addAll(females);
      }
    } else {
      final slots = [for (final p in _players) (p['slot'] as num).toInt()];
      rows.addAll(slots);
      cols.addAll(slots);
    }
    if (_mySlot != null && rows.contains(_mySlot)) {
      rows
        ..remove(_mySlot)
        ..insert(0, _mySlot!);
    }
    // 행(남)·열(여) 이름은 같은 역할 — 토큰 하나로 통일 (색·크기 분리 금지).
    Widget nameCell(int slot) => SizedBox(
          width: 64,
          child: Text(
            _nameOf(slot),
            style: AppText.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SizedBox(width: 64),
            for (final c in cols) nameCell(c),
          ]),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(children: [
                nameCell(row),
                for (final col in cols)
                  SizedBox(
                    width: 64,
                    child: row == col
                        ? Text('—', style: AppText.hint)
                        : InkWell(
                            onTap: () => _openPair(row, col),
                            child: Text(
                              _bandOf(row, col)?.bandEmoji ?? '',
                              style: AppText.body,
                            ),
                          ),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  List<Widget> _myRanking() {
    final rows = <Widget>[];
    for (final p in _pairs) {
      final a = (p['a'] as num).toInt();
      final b = (p['b'] as num).toInt();
      if (a != _mySlot && b != _mySlot) continue;
      final other = a == _mySlot ? b : a;
      final band = (p['band'] as num).toInt();
      rows.add(
        InkWell(
          onTap: () => _openPair(_mySlot!, other),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Text(band.bandEmoji, style: AppText.body),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(_nameOf(other), style: AppText.subTitle)),
                Text(band.bandLabel,
                    style: AppText.caption.copyWith(color: band.bandColor)),
              ],
            ),
          ),
        ),
      );
    }
    return rows;
  }

  Widget _legend() {
    return Wrap(
      spacing: AppSpacing.md,
      children: [
        for (int band = 0; band < 4; band++)
          Text('${band.bandEmoji} ${band.bandLabel}', style: AppText.hint),
      ],
    );
  }

  /// 쌍 상세 = 기존 궁합 unlock 흐름 (1🪙). 두 참가자의 현재 my-face 를
  /// live resolve 해 기존 runCompatUnlock → pushCompat 계약으로 넘긴다.
  Future<void> _openPair(int slotA, int slotB) async {
    String? uidOf(int slot) {
      for (final r in _roster) {
        if (r.slotNo == slot) return r.userId;
      }
      return null;
    }

    final uidA = uidOf(slotA);
    final uidB = uidOf(slotB);
    if (uidA == null || uidB == null) {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.error(message: '탈퇴한 참가자와의 상세는 볼 수 없습니다'),
      );
      return;
    }
    final myUid = _service.myUid;
    // 내 쌍은 내 리포트를 my 로 — 기존 궁합 상세의 시점 규약.
    final firstUid = uidA == myUid ? uidA : (uidB == myUid ? uidB : uidA);
    final secondUid = firstUid == uidA ? uidB : uidA;
    final my = await _service.fetchLiveReport(firstUid);
    final album = await _service.fetchLiveReport(secondUid);
    if (!mounted) return;
    if (my == null || album == null) {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.error(message: '상세를 불러올 수 없습니다'),
      );
      return;
    }
    await openBattlePairDetail(context, ref, my: my, album: album);
  }
}

/// 쌍 상세 unlock 시트 — runCompatUnlock/pushCompat 호출과 동일 계약.
/// 무료 = 밴드 닷 + 라벨만(케미 배틀 payload 는 best 외 점수를 싣지 않는다,
/// A2 정책) → [1🪙 상세 보기] → runCompatUnlock → 성공 시 pushCompat.
Future<void> openBattlePairDetail(
  BuildContext context,
  WidgetRef ref, {
  required FaceReadingReport my,
  required FaceReadingReport album,
}) async {
  final bundle = analyzeCompatibilityFromReports(my: my, album: album);
  final band = bundle.report.label.index;
  final unlock = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) {
      final coins = ref.read(authProvider)?.coins ?? 0;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.md,
          AppSpacing.xxl,
          AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 닫기.
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(ctx, false),
                icon: const FaIcon(FontAwesomeIcons.xmark,
                    size: 20, color: AppColors.textSecondary),
              ),
            ),
            // 밴드 닷 + 라벨 (점수 비노출).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: band.bandColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(band.bandLabel, style: AppText.body),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            // 두 인물 — 큰 아바타 + 이름 + 나이·성별.
            Row(
              children: [
                Expanded(child: _pairPersonColumn(my)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text('×',
                      style: AppText.body.copyWith(
                        color: AppColors.textHint,
                        fontSize: AppText.body.fontSize! * 2,
                      )),
                ),
                Expanded(child: _pairPersonColumn(album)),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            // 잠금 안내 박스.
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const FaIcon(FontAwesomeIcons.lock,
                      size: 13, color: AppColors.textHint),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '상세 풀이는 1코인 지불 후 확인가능합니다.',
                      style: AppText.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: '1코인으로 풀이 보기',
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '보유 코인 $coins개',
              style: AppText.caption.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    },
  );
  if (unlock != true || !context.mounted) return;
  // 기존 1:1 unlock 흐름 그대로 — 로그인·잔액·중복 unlock 전부 처리.
  final ok = await runCompatUnlock(
    context,
    ref,
    my: my,
    album: album,
    confirm: false,
  );
  if (!ok || !context.mounted) return;
  context.pushCompat(my: my, album: album);
}

/// 페어 시트용 세로 인물 — 큰 아바타 + 이름 + 나이·성별.
Widget _pairPersonColumn(FaceReadingReport r) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _pairAvatar(r, size: 64),
      const SizedBox(height: AppSpacing.sm),
      Text(
        r.alias ?? '${r.ageGroup.labelKo} ${r.gender.labelKo}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.body.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        '${r.ageGroup.labelKo} ${r.gender.labelKo}',
        style: AppText.caption.copyWith(color: AppColors.textHint),
      ),
    ],
  );
}

/// 원형 thumbnail 아바타 — 1순위 로컬 파일 → 2순위 CDN(thumbnailKey) →
/// 사람 아이콘.
Widget _pairAvatar(FaceReadingReport r, {double size = 28}) {
  final file = ThumbnailPaths.resolveFileSync(r.thumbnailPath);
  if (file != null && file.existsSync()) {
    return ClipOval(
      child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
    );
  }
  final cdn = ThumbnailPaths.cdnUrl(r.thumbnailKey);
  if (cdn != null) {
    return ClipOval(
      child: Image.network(
        cdn,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _pairIconAvatar(size),
      ),
    );
  }
  return _pairIconAvatar(size);
}

Widget _pairIconAvatar(double size) {
  return Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.border,
    ),
    child: Center(
      child: FaIcon(FontAwesomeIcons.user,
          size: size * 0.45, color: AppColors.textHint),
    ),
  );
}
