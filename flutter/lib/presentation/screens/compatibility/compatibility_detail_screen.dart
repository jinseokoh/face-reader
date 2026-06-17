import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:face_engine/data/constants/compat_hashtags.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_adapter.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:face_engine/domain/services/compat/compat_narrative.dart';
import 'package:face_engine/domain/services/compat/compat_pipeline.dart';
import 'package:face_engine/domain/services/compat/compat_sub_display.dart';
import 'package:face_engine/domain/services/compat/five_element.dart';
import 'package:face_engine/domain/services/compat/modern_vocab.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/domain/services/share/share_publisher.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

// ─────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────

String _relationKindKo(ElementRelationKind k) => k.modernKo;

/// 궁합 상세 — 한 쌍(나 × 앨범) 의 전체 해석.
/// 리스트 카드(`compatibility_screen.dart`) 에서 push 로 진입.
class CompatibilityDetailScreen extends ConsumerStatefulWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  const CompatibilityDetailScreen({
    super.key,
    required this.my,
    required this.album,
  });

  @override
  ConsumerState<CompatibilityDetailScreen> createState() =>
      _CompatibilityDetailScreenState();
}

class _CompatChipsBlock extends StatelessWidget {
  final CompatibilityReport report;
  const _CompatChipsBlock({required this.report});

  @override
  Widget build(BuildContext context) {
    final chips = chipsForCompat(report);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final c in chips) _ShareHashtag(chip: c)],
    );
  }
}

class _CompatibilityDetailScreenState
    extends ConsumerState<CompatibilityDetailScreen> {
  late final CompatibilityBundle _bundle =
      analyzeCompatibilityFromReports(my: widget.my, album: widget.album);

  /// RepaintBoundary key — off-screen 합성 카드 캡처용.
  final GlobalKey _shareCardKey = GlobalKey();
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        // deep link cold-start 진입 시 stack 이 없을 수 있어 명시 — stack 있으면
        // 뒤로(←), 없으면 닫기(X)→홈 으로 항상 탈출 가능하게.
        leading: IconButton(
          icon: Icon(
            Navigator.of(context).canPop() ? Icons.arrow_back : Icons.close,
          ),
          tooltip: Navigator.of(context).canPop() ? '뒤로' : '닫기',
          onPressed: () => Navigator.of(context).canPop()
              ? Navigator.of(context).pop()
              : context.go('/main'),
        ),
        title: Text(widget.album.alias ?? '궁합 분석'),
        actions: [
          IconButton(
            icon: _isSharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary,
                    ),
                  )
                : const FaIcon(FontAwesomeIcons.kakaoTalk, size: 20),
            tooltip: '카카오 공유',
            onPressed: _isSharing ? null : () => _shareViaKakao(context),
          ),
        ],
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _TotalHeader(
                my: widget.my,
                album: widget.album,
                report: _bundle.report,
              ),
              const SizedBox(height: 16),
              _SubScorePanel(report: _bundle.report),
              const SizedBox(height: 20),
              _NarrativeSections(narrative: _bundle.narrative),
            ],
          ),
          // 카카오 공유용 합성 카드 — 화면 밖 mount 후 RepaintBoundary 로 캡처.
          Positioned(
            left: -10000,
            top: 0,
            child: RepaintBoundary(
              key: _shareCardKey,
              child: _CompatShareCardComposite(
                my: widget.my,
                album: widget.album,
                report: _bundle.report,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 로그인 가드 — 비로그인이면 home_screen 의 "앨범에서 선택" 과 동일한
  /// login bottom sheet 띄움. true = 로그인 완료(또는 이미 로그인), false =
  /// 사용자가 취소.
  Future<bool> _ensureLoggedIn(BuildContext context) async {
    if (ref.read(authProvider.notifier).isLoggedIn) return true;
    final loggedIn = await showLoginBottomSheet(context, ref);
    if (!mounted) return false;
    return loggedIn;
  }

  Future<void> _shareViaKakao(BuildContext context) async {
    if (!await _ensureLoggedIn(context)) return;
    if (!await SharePublisher.instance.isKakaoTalkInstalled()) {
      if (!context.mounted) return;
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.error(
            message: '카카오톡이 설치되어 있지않아 공유할 수 없습니다'),
      );
      return;
    }
    setState(() => _isSharing = true);
    try {
      final pngBytes = await _captureShareCardBytes();
      final r = _bundle.report;
      final myAlias = widget.my.alias ?? '나';
      final albumAlias = widget.album.alias ?? '상대';
      final desc =
          '$myAlias × $albumAlias — ${r.label.korean} ${r.total.toStringAsFixed(0)}/100';
      await SharePublisher.instance.publishCompatViaKakao(
        my: widget.my,
        album: widget.album,
        title: '궁합도 과학이다',
        description: desc,
        compositeCardPng: pngBytes,
      );
    } catch (e, st) {
      debugPrint('[CompatKakaoShare] error: $e\n$st');
      if (context.mounted) {
        showTopSnackBar(
          Overlay.of(context),
          CompactSnackBar.error(message: '공유 중 문제가 발생했어요'),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<Uint8List> _captureShareCardBytes() async {
    final boundary = _shareCardKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('compat share card boundary not mounted');
    }
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('failed to encode compat share card png');
    }
    return byteData.buffer.asUint8List();
  }

}

// ─────────────────────────────────────────────────────────────
// Compat 한 장 공유 카드 (인스타·카톡)
// ─────────────────────────────────────────────────────────────

class _CompatPalette {
  static const darkBrown = Color(0xFF5C4033);
  static const warmBrown = Color(0xFF7B5B3A);
  static const sand = Color(0xFFBFA67A);

  // 강점/약점 칩 — 관상 hero `_Palette` 와 동일 (통일감).
  static const strengthBg = Color(0xFFE0EBDA);
  static const strengthFg = Color(0xFF2C5A36);
  static const strengthBorder = Color(0xFF6B9F70);
  static const weaknessBg = Color(0xFFF5DCD8);
  static const weaknessFg = Color(0xFF8C2E1F);
  static const weaknessBorder = Color(0xFFC97165);
}

class _CompatShareSide extends StatelessWidget {
  final FaceReadingReport report;
  final String alias;
  final String demographic;
  const _CompatShareSide({
    required this.report,
    required this.alias,
    required this.demographic,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Thumb(
            path: report.thumbnailPath,
            thumbnailKey: report.thumbnailKey,
            gender: report.gender,
            size: 56),
        const SizedBox(height: 8),
        Text(alias,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(demographic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: _CompatPalette.sand, fontSize: 10.5, height: 1.3)),
      ],
    );
  }
}

class _NarrativeCard extends StatelessWidget {
  final String title;
  final String body;
  const _NarrativeCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    // 관상 detail `_buildReadingSection` 과 동일 디자인 (warm beige 카드).
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.shell),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.darkBrown,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.md),
          Text(body,
              style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.darkBrown,
                  height: 1.7)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Narrative sections
// ─────────────────────────────────────────────────────────────

class _NarrativeSections extends StatelessWidget {
  final CompatNarrative narrative;

  const _NarrativeSections({required this.narrative});

  @override
  Widget build(BuildContext context) {
    final sections = <({String title, String body})>[
      (title: '한줄 요약', body: narrative.summary),
      (title: '핵심 궁합 3가지', body: narrative.corePoints),
      (title: '현실 갈등 시나리오', body: narrative.conflictScenarios),
      (title: '관계 운영 전략', body: narrative.strategy),
      (title: '이성적 끌림의 결', body: narrative.intimacyChapter),
      (title: '궁합 점수와 이유', body: narrative.scoreReason),
    ];
    return Column(
      children: [
        for (final s in sections)
          _NarrativeCard(title: s.title, body: s.body),
      ],
    );
  }
}

class _ShareHashtag extends StatelessWidget {
  final CompatChip chip;
  const _ShareHashtag({required this.chip});

  @override
  Widget build(BuildContext context) {
    final isWarm = chip.tone == CompatChipTone.warm;
    final bg = isWarm ? _CompatPalette.strengthBg : _CompatPalette.weaknessBg;
    final fg = isWarm ? _CompatPalette.strengthFg : _CompatPalette.weaknessFg;
    final border = isWarm
        ? _CompatPalette.strengthBorder
        : _CompatPalette.weaknessBorder;
    final prefix = isWarm ? '👍 ' : '👎 ';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text('$prefix${chip.label}',
          style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2)),
    );
  }
}

class _SubBar extends StatelessWidget {
  final _SubRow row;
  const _SubBar({required this.row});
  @override
  Widget build(BuildContext context) {
    final frac = (row.value.clamp(0, 100) / 100.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(row.label,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  row.value.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Text(
                  ' / 100',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubRow {
  final String label;
  final double value;
  _SubRow(this.label, this.value);
}

// ─────────────────────────────────────────────────────────────
// Sub score panel
// ─────────────────────────────────────────────────────────────

class _SubScorePanel extends StatelessWidget {
  final CompatibilityReport report;
  const _SubScorePanel({required this.report});

  @override
  Widget build(BuildContext context) {
    final rows = <_SubRow>[
      _SubRow(CompatSubKind.element.modernKo,
          subScoreToDisplay(CompatSubKind.element, report.sub.elementScore)!),
      _SubRow(CompatSubKind.palace.modernKo,
          subScoreToDisplay(CompatSubKind.palace, report.sub.palaceScore)!),
      _SubRow(CompatSubKind.qi.modernKo,
          subScoreToDisplay(CompatSubKind.qi, report.sub.qiScore)!),
      _SubRow(
        CompatSubKind.intimacy.modernKo,
        subScoreToDisplay(CompatSubKind.intimacy, report.sub.intimacyScore)!,
      ),
    ];
    return Column(
      children: [for (final r in rows) _SubBar(row: r)],
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? path;
  final String? thumbnailKey;
  final Gender gender;
  final double size;
  const _Thumb({
    required this.path,
    this.thumbnailKey,
    required this.gender,
    this.size = 44,
  });
  @override
  Widget build(BuildContext context) {
    // 로컬 thumbnailPath → CDN thumbnailKey → gender fallback(male/female png).
    final file = ThumbnailPaths.resolveFileSync(path);
    final hasFile = file != null && file.existsSync();
    final cdn = ThumbnailPaths.cdnUrl(thumbnailKey);
    final fallback = _genderFallback();
    final Widget child;
    if (hasFile) {
      child = Image.file(file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback);
    } else if (cdn != null) {
      child = Image.network(cdn,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback);
    } else {
      child = fallback;
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  /// thumbnail 없을 때 성별 기본 아바타 — 성별을 알고 있으므로 무성별 아이콘
  /// 대신 male/female png 를 쓴다.
  Widget _genderFallback() {
    final asset = switch (gender) {
      Gender.male => 'assets/icons/male.png',
      Gender.female => 'assets/icons/female.png',
    };
    return Image.asset(asset, width: size, height: size, fit: BoxFit.cover);
  }
}

// ─────────────────────────────────────────────────────────────
// Total header
// ─────────────────────────────────────────────────────────────

class _TotalHeader extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  final CompatibilityReport report;
  const _TotalHeader({
    required this.my,
    required this.album,
    required this.report,
  });
  @override
  Widget build(BuildContext context) {
    final label = report.label;
    final myAlias = my.alias ?? '나';
    final albumAlias = album.alias ?? '상대';
    final myDemographic =
        '${my.gender.labelKo} · ${my.ageGroup.labelKo} · ${my.faceShape.korean}';
    final albumDemographic =
        '${album.gender.labelKo} · ${album.ageGroup.labelKo} · ${album.faceShape.korean}';
    final relation =
        '${report.myElement.displayKorean} × ${report.albumElement.displayKorean}  ·  ${_relationKindKo(report.elementRelation.kind)}';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_CompatPalette.darkBrown, _CompatPalette.warmBrown],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('궁합도 과학이다',
                style: TextStyle(
                    color: _CompatPalette.sand,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label.korean,
                style: const TextStyle(
                  fontFamily: 'SongMyung',
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${label.hanja})',
                style: TextStyle(
                  fontFamily: 'SongMyung',
                  color: _CompatPalette.sand,
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_labelTagline(label),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _CompatPalette.sand,
                  fontSize: 13,
                  letterSpacing: 1)),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _CompatShareSide(
                      report: my,
                      alias: myAlias,
                      demographic: myDemographic)),
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('×',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w300)),
              ),
              Expanded(
                  child: _CompatShareSide(
                      report: album,
                      alias: albumAlias,
                      demographic: albumDemographic)),
            ],
          ),
          const SizedBox(height: 18),
          _CompatChipsBlock(report: report),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Text(relation,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1)),
          ),
        ],
      ),
    );
  }

  static String _labelTagline(CompatLabel l) => l.tagline;
}

// 카카오 link preview hero image — 800x800 (1:1) logical, pixelRatio 2.0 으로
// 캡처되어 1600x1600 PNG 로 Kakao CDN 에 업로드.
//
// **구성**: 상단 400px = assets/images/800x400.png banner (full-bleed),
// 하단 400px = my thumb × album thumb + 4-tier stepper + label + summary.
//
// share card 는 export medium 이라 in-app design token 과 별개의 inline
// TextStyle 을 허용 (font size 가 in-app 토큰보다 한참 크다).
class _CompatShareCardComposite extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  final CompatibilityReport report;

  const _CompatShareCardComposite({
    required this.my,
    required this.album,
    required this.report,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: Colors.white,
          child: SizedBox(
            width: 800,
            height: 800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 400,
                  child: Image.asset(
                    'assets/images/800x400.png',
                    width: 800,
                    height: 400,
                    fit: BoxFit.cover,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CompatThumb(
                                path: my.thumbnailPath,
                                thumbnailKey: my.thumbnailKey,
                                gender: my.gender),
                            const SizedBox(width: 24),
                            const Text(
                              '×',
                              style: TextStyle(
                                fontSize: 60,
                                fontWeight: FontWeight.w300,
                                color: Color(0xFF777777),
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 24),
                            _CompatThumb(
                                path: album.thumbnailPath,
                                thumbnailKey: album.thumbnailKey,
                                gender: album.gender),
                          ],
                        ),
                        const SizedBox(height: 28),
                        // 관계평 + 오행평 — 관상 share card 의 _IconLineRow
                        // (강점/약점) 와 동일한 icon + text 패턴으로 통일.
                        _CompatIconLineRow(
                          icon: _gradeFaceIcon(report.label),
                          text: report.label.tagline,
                        ),
                        const SizedBox(height: 12),
                        _CompatIconLineRow(
                          icon: FontAwesomeIcons.venusMars,
                          text: report.elementRelation.kind.modernKo,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 등급별 얼굴 아이콘 — 관계평(위) 줄에 사용. 등급이 좋을수록 더 환한 표정.
FaIconData _gradeFaceIcon(CompatLabel l) => switch (l) {
      CompatLabel.cheonjakjihap => FontAwesomeIcons.faceGrinBeam,
      CompatLabel.geumseulsanghwa => FontAwesomeIcons.faceSmileBeam,
      CompatLabel.mahapgaseong => FontAwesomeIcons.faceGrin,
      CompatLabel.hyeonggeuknanjo => FontAwesomeIcons.faceSmile,
    };

/// 궁합 share card 의 한줄평 row — 관상 카드 `_IconLineRow` 와 동일한
/// icon(40) + text(42·w500·#333) 패턴. 위 등급별 얼굴(관계평) · 아래 venus-mars(오행평).
class _CompatIconLineRow extends StatelessWidget {
  final FaIconData icon;
  final String text;
  const _CompatIconLineRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FaIcon(icon, color: const Color(0xFF333333), size: 40),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w500,
              color: Color(0xFF333333),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompatThumb extends StatelessWidget {
  final String? path;
  final String? thumbnailKey;
  final Gender gender;
  const _CompatThumb({
    required this.path,
    this.thumbnailKey,
    required this.gender,
  });

  @override
  Widget build(BuildContext context) {
    // 관상 share card (_ShareCardComposite) thumb 와 동일 크기·radius 로
    // 통일 — 카카오 link preview hero 의 통일감 보장.
    const size = 180.0;
    // 로컬 thumbnailPath → CDN thumbnailKey → gender fallback(male/female png).
    final file = ThumbnailPaths.resolveFileSync(path);
    final cdn = ThumbnailPaths.cdnUrl(thumbnailKey);
    final genderAsset = switch (gender) {
      Gender.male => 'assets/icons/male.png',
      Gender.female => 'assets/icons/female.png',
    };
    final placeholder = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Image.asset(genderAsset,
          width: size, height: size, fit: BoxFit.cover),
    );
    if (file != null && file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
      );
    }
    if (cdn != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(cdn,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder),
      );
    }
    return placeholder;
  }
}
