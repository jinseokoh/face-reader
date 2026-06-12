import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/config/router.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/ad_image_service.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/presentation/providers/ad_image_provider.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:facely/presentation/widgets/my_face_header.dart';
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

class _HomeActionCard extends StatefulWidget {
  final String label;
  final FaIconData icon;
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
}

/// 홈 상단 배너 — 활성 ad_images 를 sort_order 순으로 자동 rotation. 탭하면
/// link_url 로 외부 브라우저 이동. 활성 배너가 없거나 로드 실패 시 정적 banner.png.
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

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Widget _fallback() => Image.asset(
        'assets/images/banner.png',
        height: widget.height,
        fit: BoxFit.contain,
      );

  Future<void> _open(String? url) async {
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

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
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    // 작은 iPhone (예: SE 1/2/3, safe-area 차감 후 ≤ 720px) 에선 image·gap
    // 축소. 키보드 미드-애니메이션 등으로 constraint 가 더 떨어지면
    // SingleChildScrollView 로 fallback scroll → 어떤 height 에도 overflow
    // 안 함. tall device 는 Spacer 가 정상 작동해 기존 디자인 유지.
    final compact = MediaQuery.of(context).size.height < 720;
    final imageHeight = compact ? 200.0 : 260.0;
    final topGap = compact ? AppSpacing.sm : AppSpacing.xl;
    final bottomGap = compact ? AppSpacing.lg : AppSpacing.huge;

    final history = ref.watch(historyProvider);
    FaceReadingReport? myFace;
    for (final r in history) {
      if (r.isMyFace) {
        myFace = r;
        break;
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ① 내 관상 컴팩트 헤더 — DESIGN.md §3.7 chrome (관상 탭
                    // 헤더와 동일 공용 위젯). 미설정 시 탭 = 셀카 등록 플로우.
                    MyFaceHeader(
                      myFace: myFace,
                      unsetCaption: '탭하면 셀카 한 장으로 등록됩니다.',
                      onTap: () {
                        final mf = myFace;
                        if (mf == null) {
                          _createMyFace();
                          return;
                        }
                        context.push(
                          '/r/${mf.supabaseId ?? 'local'}',
                          extra: mf,
                        );
                      },
                    ),
                    SizedBox(height: topGap),
                    const Spacer(),
                    // ② 케미 방 카드 영역 자리 — P1 은 광고 배너(수묵화 fallback)
                    // 비주얼만. 방 카드 리스트 + 생성 CTA 는 P2 에서 활성화.
                    _HomeBanner(height: imageHeight),
                    const Spacer(),
                    // ④ 다른 사람 관상 보기 — 보조 영역 (현행 2버튼 유지).
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '다른 사람 관상 보기',
                              style: AppText.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
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

  /// [내 관상 만들기] — 전면 카메라 즉시 오픈 (PIVOT A5 ①). 카메라 좌하단
  /// 앨범 아이콘으로 보정해 둔 사진 등록 경로 제공, 선택 다이얼로그 없음.
  /// 분석 완료 시 InfoConfirm 이 isMyFace 로 등록하고 홈에 남는다.
  Future<void> _createMyFace() async {
    AnalyticsService.instance.logCameraOpen();
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
    if (!mounted || result == null) return;
    if (result is FaceMeshAlbumRequest) {
      // 앨범 경로는 기존 _openAlbum 과 동일하게 로그인 게이트 적용.
      if (!ref.read(authProvider.notifier).isLoggedIn) {
        final loggedIn = await showLoginBottomSheet(context, ref);
        if (!loggedIn) return;
        if (!mounted) return;
      }
      final albumResult = await _showAlbumSheet();
      if (!mounted || albumResult == null) return;
      await _pushDemographicConfirm(albumResult, asMyFace: true);
      return;
    }
    if (result is CaptureResult) {
      await _pushDemographicConfirm(result, asMyFace: true);
    }
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
    final result = await _showAlbumSheet();
    if (!mounted || result == null) return;
    await _pushDemographicConfirm(result);
  }

  Future<CaptureResult?> _showAlbumSheet() {
    final size = MediaQuery.of(context).size;
    return showModalBottomSheet<CaptureResult>(
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

  Future<void> _pushDemographicConfirm(
    CaptureResult result, {
    bool asMyFace = false,
  }) async {
    await context.push(
      '/capture/confirm',
      extra: CaptureExtras(
        capture: result,
        metadataFuture: result.metadataFuture,
        asMyFace: asMyFace,
      ),
    );
  }
}
