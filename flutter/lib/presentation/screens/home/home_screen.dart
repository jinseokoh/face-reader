import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:facely/config/router.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/ad_image_service.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/presentation/providers/ad_image_provider.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'album_capture_page.dart';
import 'face_mesh_page.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    // 작은 iPhone (예: SE 1/2/3, safe-area 차감 후 ≤ 720px) 에선 image·gap
    // 축소. 키보드 미드-애니메이션 등으로 constraint 가 더 떨어지면
    // SingleChildScrollView 로 fallback scroll → 어떤 height 에도 overflow
    // 안 함. tall device 는 Spacer 가 정상 작동해 기존 디자인 유지.
    final compact = MediaQuery.of(context).size.height < 720;
    final imageHeight = compact ? 220.0 : 280.0;
    final topGap = compact ? AppSpacing.sm : AppSpacing.xxl;
    final afterImage = compact ? AppSpacing.lg : 28.0;
    final afterTitle = compact ? AppSpacing.xs : 10.0;
    final bottomGap = compact ? AppSpacing.lg : AppSpacing.huge;
    final titleFontSize = compact ? 30.0 : 36.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    SizedBox(height: topGap),
                    // 활성 광고주 배너(ad_images) rotation. 없으면 home.png fallback.
                    _HomeBanner(height: imageHeight),
                    SizedBox(height: afterImage),
                    Text(
                      '관상은 과학이다.',
                      style: AppText.display.copyWith(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: afterTitle),
                    Text(
                      '안면 계측 데이터 기반 인공지능 관상앱',
                      style: AppText.body.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxl),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.xl),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _HomeActionCard(
                                label: '카메라로 촬영',
                                icon: FontAwesomeIcons.camera,
                                onPressed: _openCamera,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _HomeActionCard(
                                label: '앨범에서 선택',
                                icon: FontAwesomeIcons.image,
                                onPressed: _openAlbum,
                                reverse: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: bottomGap),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 카메라 path — fullSize sheet 안에 FaceMeshPage 가 검정 AppBar
  /// "얼굴 정면" / "얼굴 측면" 으로 동작.
  Future<void> _openCamera() async {
    AnalyticsService.instance.logCameraOpen();
    final size = MediaQuery.of(context).size;
    final result = await showModalBottomSheet<CaptureResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints.tightFor(
        width: size.width,
        height: size.height,
      ),
      builder: (_) => const FaceMeshPage(),
    );
    if (!mounted || result == null) return;
    await _pushDemographicConfirm(result);
  }

  /// 앨범 path — 카메라와 동일한 fullSize sheet 에 AlbumCapturePage 를 띄움.
  /// AppBar 가 검정 + "얼굴 정면" / "얼굴 측면" 로 일관, 내부에서 picker 호출
  /// → preview → 측면 단계까지 wrapper 안에서 전부 처리.
  Future<void> _openAlbum() async {
    AnalyticsService.instance.logAlbumOpen();
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final loggedIn = await showLoginBottomSheet(context, ref);
      if (!loggedIn) return;
      if (!mounted) return;
    }
    final size = MediaQuery.of(context).size;
    final result = await showModalBottomSheet<CaptureResult>(
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
    if (!mounted || result == null) return;
    await _pushDemographicConfirm(result);
  }

  Future<void> _pushDemographicConfirm(CaptureResult result) async {
    await context.push(
      '/capture/confirm',
      extra: CaptureExtras(
        capture: result,
        metadataFuture: result.metadataFuture,
      ),
    );
  }
}

class _HomeActionCard extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool reverse;

  const _HomeActionCard({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.reverse = false,
  });

  @override
  State<_HomeActionCard> createState() => _HomeActionCardState();
}

class _HomeActionCardState extends State<_HomeActionCard>
    with SingleTickerProviderStateMixin {
  static const _swingAmplitude = 0.05; // ≈ 2.9°
  late final AnimationController _controller;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    final begin = widget.reverse ? _swingAmplitude : -_swingAmplitude;
    final end = widget.reverse ? -_swingAmplitude : _swingAmplitude;
    _rotation = Tween<double>(begin: begin, end: end)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: _rotation,
        builder: (_, child) => Transform.rotate(
          angle: _rotation.value,
          child: child,
        ),
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: AppColors.border, width: 1),
          ),
          child: InkWell(
            onTap: widget.onPressed,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(widget.icon, size: 28, color: AppColors.textPrimary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  widget.label,
                  style: AppText.subTitle.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 홈 상단 배너 — 활성 ad_images 를 sort_order 순으로 자동 rotation. 탭하면
/// link_url 로 외부 브라우저 이동. 활성 배너가 없거나 로드 실패 시 정적 home.png.
class _HomeBanner extends ConsumerStatefulWidget {
  final double height;
  const _HomeBanner({required this.height});

  @override
  ConsumerState<_HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends ConsumerState<_HomeBanner> {
  final PageController _pageController = PageController();
  Timer? _timer;
  int _count = 0;

  void _syncRotation(int count) {
    if (count == _count) return;
    _count = count;
    _timer?.cancel();
    if (count <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = ((_pageController.page ?? 0).round() + 1) % _count;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _open(String? url) async {
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _fallback() => Image.asset(
        'assets/images/home.png',
        height: widget.height,
        fit: BoxFit.contain,
      );

  @override
  Widget build(BuildContext context) {
    final banners =
        ref.watch(adImagesProvider).asData?.value ?? const <AdImageBanner>[];
    if (banners.isEmpty) {
      // 로딩/없음/실패 모두 정적 이미지로 자리 유지 (레이아웃 안정).
      _syncRotation(0);
      return SizedBox(height: widget.height, child: _fallback());
    }
    // 배너 수에 맞춰 rotation 타이머 동기화 (build 중 setState 없이 안전).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncRotation(banners.length);
    });
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _pageController,
        itemCount: banners.length,
        itemBuilder: (_, i) {
          final b = banners[i];
          return GestureDetector(
            onTap: () => _open(b.linkUrl),
            child: CachedNetworkImage(
              imageUrl: b.imageUrl,
              height: widget.height,
              fit: BoxFit.contain,
              placeholder: (_, _) => _fallback(),
              errorWidget: (_, _, _) => _fallback(),
            ),
          );
        },
      ),
    );
  }
}
