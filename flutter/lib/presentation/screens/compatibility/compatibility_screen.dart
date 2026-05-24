import 'dart:io';

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
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/data/services/compat_unlock_service.dart';
import 'package:facely/data/services/supabase_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/compat_unlock_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/screens/compatibility/compatibility_detail_screen.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:facely/presentation/widgets/purchase_sheet.dart';
import 'package:facely/presentation/widgets/source_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 궁합 탭 — 내 얼굴이 아닌 다른 인물 리스트. 기본 lock, 1 코인 해제.
class CompatibilityScreen extends ConsumerWidget {
  const CompatibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final myFace = history
        .where((r) => r.isMyFace)
        .cast<FaceReadingReport?>()
        .firstOrNull;
    final others =
        history.where((r) => !r.isMyFace).toList(growable: false);
    final unlocksAsync = ref.watch(compatUnlocksProvider);
    final unlocked = unlocksAsync.asData?.value ?? const <String>{};

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('궁합'),
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 20),
            tooltip: '궁합 분석에 대하여',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: _body(context, ref, myFace, others, unlocked),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    FaceReadingReport? myFace,
    List<FaceReadingReport> others,
    Set<String> unlocked,
  ) {
    if (myFace == null) {
      return _guide(
        '내 관상이 등록되지 않았습니다.',
        '궁합을 보려면 내 관상 등록이 필요합니다.',
      );
    }
    if (others.isEmpty) {
      return _guide(
        '상대방의 관상을 등록하세요.',
        '카메라나 앨범으로 상대방의 관상을 추가하세요.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: others.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final other = others[i];
        final key = tryPairKey(myFace, other);
        final isUnlocked = key != null && unlocked.contains(key);

        if (isUnlocked) {
          return _CompatListCard(
            my: myFace,
            album: other,
            onTap: () {
              AnalyticsService.instance.logClickCompat();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CompatibilityDetailScreen(my: myFace, album: other),
                ),
              );
            },
          );
        }
        return _CompatLockedCard(
          album: other,
          onUnlockPressed: () =>
              _handleUnlockPressed(context, ref, myFace, other),
        );
      },
    );
  }

  /// report.supabaseId 가 null 이면 saveMetrics 로 UUID 를 할당하고 Hive 에
  /// 써서 다음 실행에서도 같은 key 가 유지되도록 한다.
  Future<void> _ensureSupabaseId(
      WidgetRef ref, FaceReadingReport report) async {
    if (report.supabaseId != null) return;
    final uuid = await SupabaseService().saveMetrics(report);
    report.supabaseId = uuid;
    await ref.read(historyProvider.notifier).updateHive();
  }

  Widget _guide(String title, String detail) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FaIcon(FontAwesomeIcons.peoplePulling,
                  color: AppTheme.textHint, size: 56),
              const SizedBox(height: 20),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.5)),
            ],
          ),
        ),
      );

  Future<void> _handleUnlockPressed(
    BuildContext context,
    WidgetRef ref,
    FaceReadingReport my,
    FaceReadingReport album,
  ) async {
    AnalyticsService.instance.logClickCompat();
    // 1. 로그인 확인.
    final auth = ref.read(authProvider.notifier);
    if (!auth.isLoggedIn) {
      final ok = await showLoginBottomSheet(context, ref);
      if (!ok || !context.mounted) return;
    }

    // 2. supabaseId 보장 — 없으면 saveMetrics 로 생성 후 Hive 갱신.
    try {
      await _ensureSupabaseId(ref, my);
      await _ensureSupabaseId(ref, album);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 중 오류: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }

    final key = tryPairKey(my, album);
    if (key == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장된 ID 를 찾을 수 없습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
      return;
    }

    // 3. 잔액 확인.
    final balance = auth.coins;
    if (balance < 1) {
      if (!context.mounted) return;
      await PurchaseSheet.show(context, onPurchased: () async {
        if (!context.mounted) return;
        // 충전 성공 시 다시 시도.
        await _handleUnlockPressed(context, ref, my, album);
      });
      return;
    }

    // 4. 확인 다이얼로그 — 카메라 path 의 frontal/lateral instructional modal 과
    //    동일한 스타일 (compatibility.png + 타이틀 + 안내 + [취소] [궁합보기]).
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/compatibility.png',
                height: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              const Text(
                '궁합 보기',
                style: TextStyle(
                  color: Color(0xFF1F1F1F),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '궁합을 보려면 1코인이 필요합니다.\n궁합을 보시겠습니까?',
                style: TextStyle(
                  color: Color(0xFF555555),
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF555555),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '취소',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1F1F1F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '궁합보기',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true) return;

    // 5. RPC. unlock 직전에 분석을 실행해 total_score 를 함께 기록 — admin 콘솔
    // (refine) 에서 점수별 정렬·필터 가능하도록.
    final preBundle = analyzeCompatibilityFromReports(my: my, album: album);
    final int newBalance;
    try {
      newBalance = await CompatUnlockService().unlock(
        key,
        totalScore: preBundle.report.total,
      );
    } catch (e, st) {
      debugPrint('[CompatUnlock] unlock failed: $e\n$st');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('해제 중 오류: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    if (newBalance == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('코인이 부족합니다.')),
      );
      return;
    }

    // 6. 갱신.
    await auth.refreshCoins();
    ref.invalidate(compatUnlocksProvider);
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('궁합 분석에 대하여',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '두 사람의 얼굴이 만드는 네 갈래 신호를 종합해 얼마나 잘 어울릴 수 있는지를 등급으로 나눕니다.',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textSecondary,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 18),
              // 등급 블록 — 4 갈래 breakdown 보다 먼저.
              const Text('등급',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 10),
              const _LabelRow(label: CompatLabel.cheonjakjihap),
              const _LabelRow(label: CompatLabel.sangkyeongyeobin),
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
              const Text('비중이 다른 이유',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 10),
              const Text(
                '정통 관상학에서 두 사람의 결을 볼 때는, 인생의 어느 자리에서 어떻게 부딪히는지를 따로따로 따져 무게를 둡니다. 네 차원의 비중도 그 가르침을 따른 것입니다.\n\n'
                '• 12 가지 생활 영역 40% — 십이궁(十二宮): 부부(夫妻)·재물(財帛)·자녀(子女)·관록(官祿)·질액(疾厄)·천이(遷移)·노복(奴僕)·전택(田宅)·복덕(福德)·부모(父母)·형제(兄弟)·명궁(命宮). 결혼·돈·자녀·일·건강·이동·인덕·부동산·복·부모·형제·운명 — 두 사람이 평생 부딪히는 실생활의 결이 이 12 자리에 모두 들어와 있어 가장 무거운 무게를 둡니다. 五行(가치관)이 큰 토대라면, 十二宮은 그 토대 위에서 매일·매년 마주하는 결.\n'
                '• 소통 스타일 25% — 오관(五官, 눈·코·입·귀·눈썹)이 만들어내는 표현 방식. 매시간 부딪히는 신호라 단기 호흡·갈등의 가장 빠른 1차 지표.\n'
                '• 가치관 20% — 오행(五行, 목·화·토·금·수)의 기운. 평생 변하지 않는 큰 결. 토대로서의 무게는 크되 십이궁만큼 세분화되지 않습니다.\n'
                '• 이성적 끌림 15% — 매력은 관계의 출발 색(色)이지 평생을 지탱하는 결이 아닙니다. 옛 관상학이 남녀의 운을 볼 때도, 단순한 미모보다 부부운·자식운·재물운처럼 실제 결혼생활의 조화를 더 중요하게 본 이유도 여기에 있습니다.\n\n'
                '이들 네 요소들이 인간관계에 미치는 영향력은 서로 다른 비중을 갖기 때문에, 각각의 요소의 중요도를 다른 비중으로 계산합니다. 이는 옛 관상서와 현대 데이터 모두가 공통적으로 보여주는 부분입니다.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textSecondary,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
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
  const _CompatListCard({
    required this.my,
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bundle = analyzeCompatibilityFromReports(my: my, album: album);
    final r = bundle.report;
    final labelColor = _labelColor(r.label);
    final alias = album.alias;
    // 관상 list 와 동일 포맷 — DESIGN.md §0.0.1 통일성.
    final demographic = '${album.ageGroup.labelKo} '
        '${album.gender.labelKo} '
        '${album.ethnicity.labelKo}';
    final subtitle = alias ?? album.faceShape.korean;

    return Material(
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
                  _Thumb(path: album.thumbnailPath, size: 42),
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
                              horizontal: 10, vertical: 6),
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
                                style: TextStyle(
                                    fontSize: 13,
                                    color: labelColor,
                                    letterSpacing: 1,
                                    height: 1.2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.label.modernKo,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppTheme.textHint,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(r.total.toStringAsFixed(0),
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w300,
                              color: AppTheme.textPrimary,
                              height: 1)),
                      const SizedBox(height: 2),
                      const Text('/ 100',
                          style: TextStyle(
                              fontSize: 10, color: AppTheme.textHint)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: AppTheme.border),
              const SizedBox(height: 12),
              Text(
                '${r.myElement.primary.korean} × ${r.albumElement.primary.korean}  ·  ${_relationKindKo(r.elementRelation.kind)}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.accent,
                    letterSpacing: 1),
              ),
              const SizedBox(height: 10),
              _MiniBars(report: r),
            ],
          ),
        ),
      ),
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
      case CompatLabel.sangkyeongyeobin:
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
  final VoidCallback onUnlockPressed;
  const _CompatLockedCard({
    required this.album,
    required this.onUnlockPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isLoggedIn = auth != null;
    final coins = auth?.coins ?? 0;
    final alias = album.alias;
    // 관상 list 와 동일 포맷 (DESIGN.md §0.0.1 — 같은 정보 같은 포맷):
    //   "연령대 성별 인종" 공백 구분, 가운데점 X.
    final demographic = '${album.ageGroup.labelKo} '
        '${album.gender.labelKo} '
        '${album.ethnicity.labelKo}';
    final subtitle = alias ?? album.faceShape.korean;

    final cta = isLoggedIn
        ? '궁합 보기 ($coins코인 보유)'
        : '카카오 로그인하고 3 코인 받기';

    return Container(
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
              _Thumb(path: album.thumbnailPath, size: 42),
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
              const FaIcon(FontAwesomeIcons.lock,
                  color: AppTheme.textHint, size: 18),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppTheme.border),
          const SizedBox(height: 12),
          Text(
            isLoggedIn
                ? '궁합 결과는 1 코인 지불 후 열어볼 수 있습니다.'
                : '최초 로그인하면 가입 보너스 3 코인을 지급해 드립니다.',
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 12),
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
              child: Text(cta,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 4 단계 stepper — cheonjakjihap(녹) → sangkyeongyeobin(파) → mahapgaseong(주) → hyeonggeuknanjo(빨).
/// 활성 dot 만 해당 등급 vivid 컬러 채움 (이모지 🟢🔵🟠🔴 톤). 비활성 dot 과 dash 는 border 톤.
class _GradeStepper extends StatelessWidget {
  static const _order = [
    CompatLabel.cheonjakjihap,
    CompatLabel.sangkyeongyeobin,
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
      dots.add(Container(
        width: isActive ? 9 : 6,
        height: isActive ? 9 : 6,
        decoration: BoxDecoration(
          color: isActive ? activeColor : AppTheme.textHint,
          shape: BoxShape.circle,
        ),
      ));
      if (i < _order.length - 1) {
        dots.add(Container(
          width: 6,
          height: 1.5,
          color: AppTheme.textHint,
        ));
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
  static Color _stepColor(CompatLabel l) =>
      _CompatListCard._labelColor(l);
}

// ─────────────────────────────────────────────────────────────
// Info dialog helpers
// ─────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String title;
  final String weight;
  final String body;
  const _InfoRow(
      {required this.title, required this.weight, required this.body});
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
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
              ),
              Text(weight,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textHint)),
            ],
          ),
          const SizedBox(height: 4),
          Text(body,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textSecondary,
                  height: 1.6)),
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
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: accent),
                          children: [
                            TextSpan(text: label.korean),
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: label.hanja,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: AppTheme.textHint),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(pair.headline,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                        height: 1.5)),
                const SizedBox(height: 2),
                Text(pair.detail,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.textSecondary,
                        height: 1.6)),
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
            detail:
                '얼굴이 보여주는 결이 너무나 잘 통합니다. 같이 있을수록 편해지고 다툼의 자리가 거의 생기지 않습니다.');
      case CompatLabel.sangkyeongyeobin:
        return const _TaglinePair(
            headline: '서로의 거리를 지키며 오래 가는 사이',
            detail:
                '같은 방향을 보지만 너무 가까이 붙지 않을 때 가장 잘 됩니다. 예의를 지키는 만큼 깊어집니다.');
      case CompatLabel.mahapgaseong:
        return const _TaglinePair(
            headline: '시간을 들이면 좋은 짝이 되는 사이',
            detail:
                '처음엔 어색하고 박자가 어긋날 수 있습니다. 다만 서로 다듬어 가다 보면 단단한 관계가 됩니다.');
      case CompatLabel.hyeonggeuknanjo:
        return const _TaglinePair(
            headline: '결이 달라 부딪힘이 잦은 사이',
            detail:
                '비슷한 점보다 다른 점이 먼저 보입니다. 한 번에 풀려고 하지 말고 천천히 거리감을 조절해야 합니다.');
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
    final labelColor =
        entry.muted ? AppTheme.textHint : AppTheme.textSecondary;
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
                style: TextStyle(
                    fontSize: 10,
                    color: labelColor,
                    letterSpacing: 0),
              ),
            ),
            const SizedBox(width: 4),
            Text(entry.muted ? '—' : entry.value.toStringAsFixed(0),
                style: TextStyle(
                    fontSize: 11,
                    color: entry.muted
                        ? AppTheme.textHint
                        : AppTheme.textPrimary)),
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
      _MiniEntry(CompatSubKind.element.modernKo,
          subScoreToDisplay(CompatSubKind.element, report.sub.elementScore)!,
          false),
      _MiniEntry(CompatSubKind.palace.modernKo,
          subScoreToDisplay(CompatSubKind.palace, report.sub.palaceScore)!,
          false),
      _MiniEntry(CompatSubKind.qi.modernKo,
          subScoreToDisplay(CompatSubKind.qi, report.sub.qiScore)!, false),
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
  final double size;
  const _Thumb({required this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = size / 2;
    if (path == null || path!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.border,
        child: const FaIcon(FontAwesomeIcons.user, color: AppTheme.textHint, size: 22),
      );
    }
    final file = File(path!);
    return ClipOval(
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CircleAvatar(
          radius: radius,
          backgroundColor: AppTheme.border,
          child: const FaIcon(FontAwesomeIcons.fileImage,
              color: AppTheme.textHint, size: 18),
        ),
      ),
    );
  }
}

