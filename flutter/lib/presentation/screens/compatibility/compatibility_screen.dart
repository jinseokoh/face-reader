import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/compat/compat_pair_key.dart';
import 'package:face_engine/domain/services/compat/compat_pipeline.dart';
import 'package:face_engine/domain/services/compat/compat_sub_display.dart';
import 'package:face_engine/domain/services/compat/five_element.dart';
import 'package:face_engine/domain/services/compat/modern_vocab.dart';
import 'package:facely/config/router.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/data/services/compat_unlock_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/compat_unlock_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/recent_unlock_focus_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/screens/compatibility/compat_unlock_action.dart';
import 'package:facely/presentation/widgets/coin_chip.dart';
import 'package:facely/presentation/widgets/empty_state_placeholder.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:facely/presentation/widgets/source_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 궁합 탭 — 내 얼굴이 아닌 다른 인물 리스트. 기본 lock, 1 코인 해제.
/// 두 섹션 (미확인 → 확인) 으로 분리, 각 섹션은 자체 정렬 selector 보유.
class CompatibilityScreen extends ConsumerStatefulWidget {
  const CompatibilityScreen({super.key});

  @override
  ConsumerState<CompatibilityScreen> createState() =>
      _CompatibilityScreenState();
}

class _CompatibilityScreenState extends ConsumerState<CompatibilityScreen> {
  // 미확인 카드는 점수가 노출되지 않으므로 시간 기준 정렬만 의미 있음.
  _LockedSort _lockedSort = _LockedSort.newest;
  // 확인 카드는 점수까지 노출되므로 score 정렬을 기본값으로 (가장 흥미로운
  // 매치를 먼저 보여줌).
  _UnlockedSort _unlockedSort = _UnlockedSort.score;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final myFace = history
        .where((r) => r.isMyFace)
        .cast<FaceReadingReport?>()
        .firstOrNull;
    final others = history.where((r) => !r.isMyFace).toList(growable: false);
    final unlocksAsync = ref.watch(compatUnlocksProvider);
    final unlocked = unlocksAsync.asData?.value ?? const <String>{};
    final reconstructed =
        ref.watch(unlockedPartnerBodiesProvider).asData?.value ??
        const <FaceReadingReport>[];
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('궁합'),
            if (auth != null) ...[
              const SizedBox(width: AppSpacing.md),
              CoinChip(
                coins: auth.coins,
                onTap: () =>
                    ref.read(selectedTabProvider.notifier).selectTab(3),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 20),
            tooltip: '궁합 분석에 대하여',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: _body(context, myFace, others, unlocked, reconstructed),
    );
  }

  Widget _body(
    BuildContext context,
    FaceReadingReport? myFace,
    List<FaceReadingReport> others,
    Set<String> unlocked,
    List<FaceReadingReport> reconstructed,
  ) {
    if (myFace == null) {
      // 비교할 상대가 하나도 없으면 종전대로 빈 상태.
      if (others.isEmpty) {
        return const EmptyStatePlaceholder(
          icon: FontAwesomeIcons.userPlus,
          title: '내 관상이 등록되지 않았습니다',
          detail: '궁합을 보려면 내 관상 등록이 필요합니다',
        );
      }
      // 저장된 상대는 있는데 내 관상이 없으면 — "등록만 하면 이 사람들과 궁합을
      // 볼 수 있다"를 비활성 프리뷰로 한눈에 보여준다(원인 즉시 이해).
      // 등록 CTA 는 nudge 스낵바 [내 관상 등록하기]가 전담 (중복 제거).
      return _InactiveCompatPreview(others: others);
    }

    // 두 섹션 분리 — 로컬 history 기반.
    final lockedList = <FaceReadingReport>[];
    final unlockedList = <FaceReadingReport>[];
    final localIds = <String>{};
    for (final o in others) {
      // pair_key = 상대 supabaseId 단독. 내 사진을 바꿔도 같은 상대면 키가
      // 동일해 unlock 이 유지된다(재결제 없음). 점수는 현재 내 관상으로 재계산.
      final key = tryPairKey(myFace, o);
      if (o.supabaseId != null) localIds.add(o.supabaseId!);
      final isUnlocked = key != null && unlocked.contains(key);
      if (isUnlocked) {
        unlockedList.add(o);
      } else {
        lockedList.add(o);
      }
    }

    // 로컬에 없는 복원 파트너를 unlocked 에 추가 (gap fill).
    for (final r in reconstructed) {
      if (r.supabaseId != null && !localIds.contains(r.supabaseId)) {
        unlockedList.add(r);
      }
    }

    if (others.isEmpty && unlockedList.isEmpty) {
      return const EmptyStatePlaceholder(
        icon: FontAwesomeIcons.peoplePulling,
        title: '상대방의 관상을 등록하세요',
        detail: '카메라나 앨범으로 상대방의 관상을 추가하세요',
      );
    }

    // 미확인 — 시간 기준 정렬만.
    lockedList.sort(
      (a, b) => switch (_lockedSort) {
        _LockedSort.newest => b.timestamp.compareTo(a.timestamp),
        _LockedSort.oldest => a.timestamp.compareTo(b.timestamp),
      },
    );

    // 확인 — score 정렬 시에만 pipeline 호출 (시간 정렬은 timestamp 만 비교).
    final List<FaceReadingReport> unlockedSorted;
    if (_unlockedSort == _UnlockedSort.score) {
      final scored =
          unlockedList
              .map(
                (o) => (
                  report: o,
                  score: analyzeCompatibilityFromReports(
                    my: myFace,
                    album: o,
                  ).report.total,
                ),
              )
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      unlockedSorted = scored.map((e) => e.report).toList();
    } else {
      unlockedSorted = [...unlockedList]
        ..sort(
          (a, b) => switch (_unlockedSort) {
            _UnlockedSort.newest => b.timestamp.compareTo(a.timestamp),
            _UnlockedSort.oldest => a.timestamp.compareTo(b.timestamp),
            _UnlockedSort.score => 0,
          },
        );
    }

    // 방금 결제한 항목(받은 카드 CTA 경유)을 정렬과 무관하게 '확인' 맨 위로
    // 고정. 사용자가 정렬을 바꾸거나 카드를 누르면 해제(아래 콜백) → 일반 정렬.
    final focusId = ref.watch(recentUnlockFocusProvider);
    final unlockedPinned =
        (focusId != null && unlockedSorted.any((r) => r.supabaseId == focusId))
        ? <FaceReadingReport>[
            ...unlockedSorted.where((r) => r.supabaseId == focusId),
            ...unlockedSorted.where((r) => r.supabaseId != focusId),
          ]
        : unlockedSorted;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        if (lockedList.isNotEmpty) ...[
          _SectionHeader<_LockedSort>(
            title: '미확인',
            count: lockedList.length,
            value: _lockedSort,
            values: _LockedSort.values,
            labelOf: (v) => v.label,
            onChanged: (v) => setState(() => _lockedSort = v),
          ),
          const SizedBox(height: 8),
          ...lockedList.map(
            (other) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CompatLockedCard(
                album: other,
                onUnlockPressed: () =>
                    _handleUnlockPressed(context, ref, myFace, other),
              ),
            ),
          ),
        ],
        if (lockedList.isNotEmpty && unlockedPinned.isNotEmpty)
          const SizedBox(height: 20),
        if (unlockedPinned.isNotEmpty) ...[
          _SectionHeader<_UnlockedSort>(
            title: '확인',
            count: unlockedPinned.length,
            value: _unlockedSort,
            values: _UnlockedSort.values,
            labelOf: (v) => v.label,
            onChanged: (v) => setState(() {
              _unlockedSort = v;
              ref.read(recentUnlockFocusProvider.notifier).clear();
            }),
          ),
          const SizedBox(height: 8),
          ...unlockedPinned.map(
            (other) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CompatListCard(
                my: myFace,
                album: other,
                onTap: () {
                  ref.read(recentUnlockFocusProvider.notifier).clear();
                  AnalyticsService.instance.logClickCompat();
                  context.pushCompat(my: myFace, album: other);
                },
                onDelete: () =>
                    _confirmDeleteUnlock(context, ref, myFace, other),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 잠금 카드의 [궁합보기] → 공용 1코인 unlock 흐름(확인 다이얼로그 포함).
  /// 성공 시 compatUnlocksProvider 가 invalidate 돼 카드가 '확인' 섹션으로
  /// 자동 이동한다 (별도 네비게이션 없음).
  Future<void> _handleUnlockPressed(
    BuildContext context,
    WidgetRef ref,
    FaceReadingReport my,
    FaceReadingReport album,
  ) async {
    await runCompatUnlock(context, ref, my: my, album: album);
  }

  /// 확인 리스트 항목 삭제 — unlock 행 제거(서버). 파트너는 관상/북마크에 남고
  /// 미확인으로 복귀한다. 코인 환불 없음.
  Future<void> _confirmDeleteUnlock(
    BuildContext context,
    WidgetRef ref,
    FaceReadingReport my,
    FaceReadingReport album,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('궁합 삭제', style: AppText.modalTitle),
        content: Text(
          '이 궁합을 목록에서 삭제할까요?\n사용한 코인은 환불되지 않습니다.',
          style: AppText.body.copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소',
                style: AppText.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제',
                style: AppText.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // pair_key = 상대 supabaseId 단독.
    final keys = <String>[];
    final key = tryPairKey(my, album);
    if (key != null) keys.add(key);
    try {
      await CompatUnlockService().deleteUnlock(keys);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('삭제 중 오류: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }
    // unlock·복원 파트너 캐시 무효화 → 확인 리스트에서 사라지고, 로컬 파트너는
    // 미확인으로 복귀.
    ref.read(recentUnlockFocusProvider.notifier).clear();
    ref.invalidate(compatUnlocksProvider);
    ref.invalidate(unlockedPartnerBodiesProvider);
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('궁합 분석에 대하여', style: AppText.modalTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '두 사람의 얼굴이 만드는 네 갈래 신호를 종합해 얼마나 잘 어울릴 수 있는지를 등급으로 나눕니다.',
                style: AppText.body,
              ),
              const SizedBox(height: 18),
              // 등급 블록 — 4 갈래 breakdown 보다 먼저.
              const Text('등급', style: AppText.sectionTitle),
              const SizedBox(height: 10),
              const _LabelRow(label: CompatLabel.cheonjakjihap),
              const _LabelRow(label: CompatLabel.geumseulsanghwa),
              const _LabelRow(label: CompatLabel.mahapgaseong),
              const _LabelRow(label: CompatLabel.hyeonggeuknanjo),
              const SizedBox(height: 20),
              for (final kind in CompatSubKind.values)
                _InfoRow(
                  title: kind.displayLabel,
                  weight: kind.weightLabel,
                  body: kind.descriptionKo,
                ),
              const SizedBox(height: 18),
              const Text('비중이 다른 이유', style: AppText.sectionTitle),
              const SizedBox(height: 10),
              const Text(
                '정통 관상학에서 두 사람의 결을 볼 때는, 인생의 어느 자리에서 어떻게 부딪히는지를 따로따로 따져 무게를 둡니다. 네 차원의 비중도 그 가르침을 따른 것입니다.\n\n'
                '• 12 가지 생활 영역 40% — 십이궁(十二宮): 부부(夫妻)·재물(財帛)·자녀(子女)·관록(官祿)·질액(疾厄)·천이(遷移)·노복(奴僕)·전택(田宅)·복덕(福德)·부모(父母)·형제(兄弟)·명궁(命宮). 결혼·돈·자녀·일·건강·이동·인덕·부동산·복·부모·형제·운명 — 두 사람이 평생 부딪히는 실생활의 결이 이 12 자리에 모두 들어와 있어 가장 무거운 무게를 둡니다. 五行(가치관)이 큰 토대라면, 十二宮은 그 토대 위에서 매일·매년 마주하는 결.\n'
                '• 소통 스타일 25% — 오관(五官, 눈·코·입·귀·눈썹)이 만들어내는 표현 방식. 매시간 부딪히는 신호라 단기 호흡·갈등의 가장 빠른 1차 지표.\n'
                '• 가치관 20% — 오행(五行, 목·화·토·금·수)의 기운. 평생 변하지 않는 큰 결. 토대로서의 무게는 크되 십이궁만큼 세분화되지 않습니다.\n'
                '• 이성적 끌림 15% — 매력은 관계의 출발 색(色)이지 평생을 지탱하는 결이 아닙니다. 옛 관상학이 남녀의 운을 볼 때도, 단순한 미모보다 부부운·자식운·재물운처럼 실제 결혼생활의 조화를 더 중요하게 본 이유도 여기에 있습니다.\n\n'
                '이들 네 요소들이 인간관계에 미치는 영향력은 서로 다른 비중을 갖기 때문에, 각각의 요소의 중요도를 다른 비중으로 계산합니다. 이는 옛 관상서와 현대 데이터 모두가 공통적으로 보여주는 부분입니다.',
                style: AppText.body,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: AppText.subTitle),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Unlocked card — 기존 구조 그대로.
// ─────────────────────────────────────────────────────────────

class _CompatListCard extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _CompatListCard({
    required this.my,
    required this.album,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bundle = analyzeCompatibilityFromReports(my: my, album: album);
    final r = bundle.report;
    final labelColor = _labelColor(r.label);
    final alias = album.alias;
    // 관상 list 와 동일 포맷 — DESIGN.md §0.0.1 통일성.
    final demographic =
        '${album.ageGroup.labelKo} '
        '${album.gender.labelKo} '
        '${album.ethnicity.labelKo}';
    final subtitle = alias ?? album.faceShape.korean;

    return Stack(
      children: [
        Material(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 관상 list item 과 동일 사이즈·token (DESIGN.md §0.0.1).
                      _Thumb(
                        path: album.thumbnailPath,
                        thumbnailKey: album.thumbnailKey,
                        size: 42,
                        gender: album.gender,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              demographic,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.sectionTitle.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SourceBadge(source: album.source),
                                const SizedBox(width: AppSpacing.xs),
                                Flexible(
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.caption.copyWith(
                                      color: AppColors.textHint,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: labelColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _GradeStepper(label: r.label),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${r.label.korean} (${r.label.hanja})',
                                    style: AppText.caption.copyWith(
                                      color: labelColor,
                                      letterSpacing: 1,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.label.modernKo,
                              style: AppText.hint,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            r.total.toStringAsFixed(0),
                            // 데이터 numeral — 토큰 anchor + 명시적 크기 유지.
                            style: AppText.sectionTitle.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.w300,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '/ 100',
                            style: AppText.hint.copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: AppTheme.border),
                  const SizedBox(height: 12),
                  Text(
                    '${r.myElement.displayKorean} × ${r.albumElement.displayKorean}  ·  ${_relationKindKo(r.elementRelation.kind)}',
                    style: AppText.hint.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MiniBars(report: r),
                ],
              ),
            ),
          ),
        ),
        // 결제한 궁합 삭제 — 우상단 절대위치 3-dot (관상 카드와 동일 패턴).
        Positioned(
          top: 4,
          right: 4,
          child: PopupMenuButton<String>(
            tooltip: '메뉴',
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: const FaIcon(
              FontAwesomeIcons.ellipsisVertical,
              color: AppColors.textHint,
              size: 16,
            ),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            onSelected: (v) {
              if (v == 'delete') onDelete();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(
                  '삭제',
                  style: AppText.body.copyWith(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 등급별 SSOT 컬러 — accent bar · 등급명 텍스트 · stepper dot 셋 다 동일.
  /// Tailwind-600 패밀리 (한 셋, hue 들쭉날쭉 안 함, vivid 에 가까우면서도
  /// 본문 텍스트로 읽힘). 변경 시 _stepColor 와 동기화 — 두 함수는 반드시
  /// 같은 값을 반환해야 한다.
  static Color _labelColor(CompatLabel l) {
    switch (l) {
      case CompatLabel.cheonjakjihap:
        return const Color(0xFF16A34A); // green-600
      case CompatLabel.geumseulsanghwa:
        return const Color(0xFF2563EB); // blue-600
      case CompatLabel.mahapgaseong:
        return const Color(0xFFEA580C); // orange-600
      case CompatLabel.hyeonggeuknanjo:
        return const Color(0xFFDC2626); // red-600
    }
  }

  static String _relationKindKo(ElementRelationKind k) => k.modernKo;
}

// ─────────────────────────────────────────────────────────────
// Locked card — 기본 상태. 상대 프로필만 보여주고 해제 CTA.
// ─────────────────────────────────────────────────────────────

class _CompatLockedCard extends ConsumerWidget {
  final FaceReadingReport album;
  final VoidCallback? onUnlockPressed;

  /// 내 관상 미등록 상태에서 "이런 사람들과 궁합을 볼 수 있다"를 미리 보여주는
  /// 비활성 모드. 결제 버튼·안내를 떼어낸 simplified 카드 + 흐릿하게(dim).
  final bool inactive;
  const _CompatLockedCard({
    required this.album,
    this.onUnlockPressed,
    this.inactive = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isLoggedIn = auth != null;
    final alias = album.alias;
    // 관상 list 와 동일 포맷 (DESIGN.md §0.0.1 — 같은 정보 같은 포맷):
    //   "연령대 성별 인종" 공백 구분, 가운데점 X.
    final demographic =
        '${album.ageGroup.labelKo} '
        '${album.gender.labelKo} '
        '${album.ethnicity.labelKo}';
    final subtitle = alias ?? album.faceShape.korean;

    // 잔액(N코인 보유)은 AppBar 의 _CoinChip 이 single source of truth.
    // 카드마다 반복하지 않음 — 시각 노이즈 제거.
    final cta = isLoggedIn ? '1코인으로 풀이 보기' : '카카오 로그인하고 3 코인 받기';

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 관상 list item 과 동일 thumb 사이즈 (42) + 동일 title/subtitle
              // 토큰·간격 (DESIGN.md §0.0.1 통일성).
              _Thumb(
                path: album.thumbnailPath,
                thumbnailKey: album.thumbnailKey,
                size: 42,
                gender: album.gender,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      demographic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.sectionTitle.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SourceBadge(source: album.source),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const FaIcon(
                FontAwesomeIcons.lock,
                color: AppTheme.textHint,
                size: 18,
              ),
            ],
          ),
          // 비활성(미등록 프리뷰)에서는 결제 안내·버튼을 떼어낸 simplified 카드.
          if (!inactive) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: AppTheme.border),
            const SizedBox(height: 12),
            Text(
              isLoggedIn
                  ? '상세 풀이는 1코인 지불 후 확인가능합니다.'
                  : '최초 로그인하면 가입 보너스 3 코인을 지급해 드립니다.',
              style: AppText.hint.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            // 받은(북마크) 카드 포함 모든 미확인 카드는 단일 "궁합보기" 버튼으로
            // 통일. 상대 관상 열람은 관상 탭 > 북마크에서.
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: onUnlockPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  cta,
                  style: AppText.subTitle.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    // 비활성: 흐릿하게 + 터치 차단 — "지금은 못 보는 상태"임을 시각적으로 전달.
    if (inactive) {
      return IgnorePointer(child: Opacity(opacity: 0.45, child: card));
    }
    return card;
  }
}

/// 내 관상 미등록 + 저장된 상대가 있을 때의 궁합 탭 — 등록 유도 배너 위에,
/// "이런 분들과 볼 수 있다"는 비활성 프리뷰 리스트를 흐릿하게 보여준다.
class _InactiveCompatPreview extends StatelessWidget {
  final List<FaceReadingReport> others;
  const _InactiveCompatPreview({required this.others});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        const _RegisterMyFaceBanner(),
        const SizedBox(height: AppSpacing.sm),
        ...others.map(
          (o) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CompatLockedCard(album: o, inactive: true),
          ),
        ),
      ],
    );
  }
}

/// 내 관상 등록 안내 — 등록 pill + "등록 전까지 잠김"을 알리는 펄싱 안내 한 줄.
/// pill 탭 = 관상 등록 팝업(촬영 시트) 직행.
class _RegisterMyFaceBanner extends ConsumerStatefulWidget {
  const _RegisterMyFaceBanner();

  @override
  ConsumerState<_RegisterMyFaceBanner> createState() =>
      _RegisterMyFaceBannerState();
}

class _RegisterMyFaceBannerState extends ConsumerState<_RegisterMyFaceBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 흰색+1px border stadium pill — 본문 CTA 규칙 (검정 invert 는 오버레이
        // 전용). 설정 탭 [충전하기] 와 동일 레시피. 탭 = 관상 등록 팝업 직행.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Center(
            child: GestureDetector(
              onTap: () => startMyFaceCapture(context, ref),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border.all(color: AppColors.textPrimary),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '나의 관상을 등록하면 궁합을 볼 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const FaIcon(
                      FontAwesomeIcons.chevronRight,
                      size: 12,
                      color: AppColors.textPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Opacity(
            opacity: 0.45 + 0.55 * _c.value,
            child: Transform.translate(
              offset: Offset(0, 3 * _c.value),
              child: child,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              '나의 관상이 등록되기 전까지는 궁합이 잠겨있게 됩니다.',
              textAlign: TextAlign.center,
              // nudge 배너 caption("앨범 사진이나 …")과 동일 토큰.
              style: AppText.caption.copyWith(color: AppColors.textHint),
            ),
          ),
        ),
      ],
    );
  }
}

/// 4 단계 stepper — cheonjakjihap(녹) → geumseulsanghwa(파) → mahapgaseong(주) → hyeonggeuknanjo(빨).
/// 활성 dot 만 해당 등급 vivid 컬러 채움 (이모지 🟢🔵🟠🔴 톤). 비활성 dot 과 dash 는 border 톤.
class _GradeStepper extends StatelessWidget {
  static const _order = [
    CompatLabel.cheonjakjihap,
    CompatLabel.geumseulsanghwa,
    CompatLabel.mahapgaseong,
    CompatLabel.hyeonggeuknanjo,
  ];
  final CompatLabel label;

  const _GradeStepper({required this.label});

  @override
  Widget build(BuildContext context) {
    final activeIdx = _order.indexOf(label);
    final activeColor = _stepColor(label);
    final dots = <Widget>[];
    for (var i = 0; i < _order.length; i++) {
      final isActive = i == activeIdx;
      dots.add(
        Container(
          width: isActive ? 9 : 6,
          height: isActive ? 9 : 6,
          decoration: BoxDecoration(
            color: isActive ? activeColor : AppTheme.textHint,
            shape: BoxShape.circle,
          ),
        ),
      );
      if (i < _order.length - 1) {
        dots.add(Container(width: 6, height: 1.5, color: AppTheme.textHint));
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: dots,
    );
  }

  // accent bar · 등급명 텍스트 · stepper dot 모두 한 셋 (Tailwind-600).
  // _CompatListCard._labelColor 와 반드시 동일 값 — 변경 시 동시 수정.
  static Color _stepColor(CompatLabel l) => _CompatListCard._labelColor(l);
}

// ─────────────────────────────────────────────────────────────
// Info dialog helpers
// ─────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String title;
  final String weight;
  final String body;
  const _InfoRow({
    required this.title,
    required this.weight,
    required this.body,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(title, style: AppText.subTitle),
              ),
              Text(weight, style: AppText.hint),
            ],
          ),
          const SizedBox(height: 4),
          Text(body, style: AppText.caption),
        ],
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  final CompatLabel label;
  const _LabelRow({required this.label});
  @override
  Widget build(BuildContext context) {
    final pair = _tagline(label);
    final accent = _CompatListCard._labelColor(label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 56,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _GradeStepper(label: label),
                    const SizedBox(width: 8),
                    // 전통 한글 + 한자 — 근거로서의 자료 보존.
                    Flexible(
                      child: RichText(
                        text: TextSpan(
                          style: AppText.subTitle.copyWith(color: accent),
                          children: [
                            TextSpan(text: label.korean),
                            const TextSpan(text: '  '),
                            TextSpan(text: label.hanja, style: AppText.hint),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  pair.headline,
                  style: AppText.subTitle.copyWith(height: 1.5),
                ),
                const SizedBox(height: 2),
                Text(pair.detail, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static _TaglinePair _tagline(CompatLabel l) {
    switch (l) {
      case CompatLabel.cheonjakjihap:
        return const _TaglinePair(
          headline: '굳이 맞추지 않아도 흐름이 맞는 사이',
          detail: '얼굴이 보여주는 결이 너무나 잘 통합니다. 같이 있을수록 편해지고 다툼의 자리가 거의 생기지 않습니다.',
        );
      case CompatLabel.geumseulsanghwa:
        return const _TaglinePair(
          headline: '서로 결이 잘 맞아 화목한 사이',
          detail:
              '얼굴이 보여주는 결이 잘 어울립니다. 함께 있으면 편안하고, 작은 표현만 꾸준히 더하면 오래 화목하게 갑니다.',
        );
      case CompatLabel.mahapgaseong:
        return const _TaglinePair(
          headline: '시간을 들이면 좋은 짝이 되는 사이',
          detail: '처음엔 어색하고 박자가 어긋날 수 있습니다. 다만 서로 다듬어 가다 보면 단단한 관계가 됩니다.',
        );
      case CompatLabel.hyeonggeuknanjo:
        return const _TaglinePair(
          headline: '결이 달라 부딪힘이 잦은 사이',
          detail: '비슷한 점보다 다른 점이 먼저 보입니다. 한 번에 풀려고 하지 말고 천천히 거리감을 조절해야 합니다.',
        );
    }
  }
}

class _MiniBar extends StatelessWidget {
  final _MiniEntry entry;
  const _MiniBar({required this.entry});

  @override
  Widget build(BuildContext context) {
    final frac = (entry.value.clamp(0, 100) / 100.0).toDouble();
    final color = entry.muted ? AppTheme.textHint : AppTheme.accent;
    final labelColor = entry.muted ? AppTheme.textHint : AppTheme.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                entry.korean,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // 미니 차트 micro-label — 4열 폭 제약으로 크기 명시 유지.
                style: AppText.hint.copyWith(fontSize: 10, color: labelColor),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              entry.muted ? '—' : entry.value.toStringAsFixed(0),
              style: AppText.hint.copyWith(
                fontSize: 11,
                color: entry.muted ? AppColors.textHint : AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Stack(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            FractionallySizedBox(
              widthFactor: entry.muted ? 0 : frac,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniBars extends StatelessWidget {
  final CompatibilityReport report;
  const _MiniBars({required this.report});

  @override
  Widget build(BuildContext context) {
    final entries = <_MiniEntry>[
      _MiniEntry(
        CompatSubKind.element.modernKo,
        subScoreToDisplay(CompatSubKind.element, report.sub.elementScore)!,
        false,
      ),
      _MiniEntry(
        CompatSubKind.palace.modernKo,
        subScoreToDisplay(CompatSubKind.palace, report.sub.palaceScore)!,
        false,
      ),
      _MiniEntry(
        CompatSubKind.qi.modernKo,
        subScoreToDisplay(CompatSubKind.qi, report.sub.qiScore)!,
        false,
      ),
      _MiniEntry(
        CompatSubKind.intimacy.modernKo,
        subScoreToDisplay(CompatSubKind.intimacy, report.sub.intimacyScore)!,
        false,
      ),
    ];
    return Row(
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          Expanded(child: _MiniBar(entry: entries[i])),
          if (i < entries.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _MiniEntry {
  final String korean;
  final double value;
  final bool muted;
  const _MiniEntry(this.korean, this.value, this.muted);
}

class _TaglinePair {
  final String headline;
  final String detail;
  const _TaglinePair({required this.headline, required this.detail});
}

// ─────────────────────────────────────────────────────────────
// Thumb
// ─────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  final String? path;
  final String? thumbnailKey;
  final double size;
  final Gender? gender;
  const _Thumb({
    required this.path,
    required this.size,
    this.thumbnailKey,
    this.gender,
  });

  @override
  Widget build(BuildContext context) {
    final radius = size / 2;
    // 1순위 로컬 파일(thumbnailPath) → 2순위 CDN(thumbnailKey) → gender fallback.
    // 받은 카드·결제 궁합 복원 파트너는 thumbnailPath=null 이지만 thumbnailKey 는
    // 들고 있으므로 CDN 으로 실제 얼굴을 띄운다.
    final file = ThumbnailPaths.resolveFileSync(path);
    final cdn = ThumbnailPaths.cdnUrl(thumbnailKey);
    if (file != null) {
      return ClipOval(
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _networkOrFallback(radius, cdn),
        ),
      );
    }
    return _networkOrFallback(radius, cdn);
  }

  Widget _networkOrFallback(double radius, String? cdn) {
    if (cdn == null) return _genderFallback(radius);
    return ClipOval(
      child: Image.network(
        cdn,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _genderFallback(radius),
      ),
    );
  }

  /// thumbnail 없을 때 gender 기본 아바타. male/female 은 png 에셋,
  /// gender 미상이면 generic user 아이콘.
  Widget _genderFallback(double radius) {
    final asset = switch (gender) {
      Gender.male => 'assets/icons/male.png',
      Gender.female => 'assets/icons/female.png',
      _ => null,
    };
    if (asset == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.border,
        child: FaIcon(
          FontAwesomeIcons.user,
          color: AppTheme.textHint,
          size: radius * 0.85,
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.border,
      backgroundImage: AssetImage(asset),
    );
  }
}

enum _LockedSort {
  newest('최신순'),
  oldest('오래된순');

  final String label;
  const _LockedSort(this.label);
}

enum _UnlockedSort {
  score('점수순'),
  newest('최신순'),
  oldest('오래된순');

  final String label;
  const _UnlockedSort(this.label);
}

/// 섹션 헤더 — 타이틀(N) + 정렬 토글. 관상 탭의 sort selector 와 동일 패턴
/// (DESIGN.md §0.0.1 통일성). T 는 각 섹션의 enum 타입.
class _SectionHeader<T> extends StatelessWidget {
  final String title;
  final int count;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '$title ($count)',
          style: AppText.sectionTitle.copyWith(fontWeight: FontWeight.w700),
        ),
        PopupMenuButton<T>(
          tooltip: '정렬',
          initialValue: value,
          padding: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          onSelected: onChanged,
          itemBuilder: (ctx) => values
              .map(
                (o) => PopupMenuItem<T>(
                  value: o,
                  child: Text(labelOf(o), style: AppText.body),
                ),
              )
              .toList(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labelOf(value),
                style: AppText.caption.copyWith(color: AppColors.textHint),
              ),
              const SizedBox(width: AppSpacing.sm),
              const FaIcon(
                FontAwesomeIcons.chevronDown,
                size: 12,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 잔액 chip 은 공용 CoinChip (presentation/widgets/coin_chip.dart) — 궁합·교감 공유.
