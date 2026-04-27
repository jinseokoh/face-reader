import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/services/ad_service.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/providers/wallet_provider.dart';

/// 광고 시청 → 보상 화면.
///
/// 흐름:
///  1) 활성 광고 1건 fetch
///  2) video_player 로 mp4 재생 (controls 노출, seek 막음)
///  3) `onCompleted` 또는 position >= duration - 200ms 시점에 RPC 호출
///  4) 성공 시 잔액 갱신 + snackbar + 화면 닫음
class AdRewardScreen extends ConsumerStatefulWidget {
  const AdRewardScreen({super.key});

  @override
  ConsumerState<AdRewardScreen> createState() => _AdRewardScreenState();
}

class _AdRewardScreenState extends ConsumerState<AdRewardScreen> {
  Ad? _ad;
  VideoPlayerController? _controller;
  bool _claimed = false;
  String? _error;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final ad = await AdService().nextAd();
      if (ad == null) {
        setState(() => _error = '재생 가능한 광고가 없습니다.');
        return;
      }
      final c = VideoPlayerController.networkUrl(Uri.parse(ad.videoUrl));
      await c.initialize();
      c.addListener(_onTick);
      await c.play();
      if (!mounted) return;
      setState(() {
        _ad = ad;
        _controller = c;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '광고 로드 실패: $e');
    }
  }

  void _onTick() {
    final c = _controller;
    final ad = _ad;
    if (c == null || ad == null || _claimed) return;
    final pos = c.value.position;
    final dur = c.value.duration;
    if (dur == Duration.zero) return;
    if (pos >= dur - const Duration(milliseconds: 250)) {
      _claimed = true;
      _claim(ad.id);
    }
  }

  Future<void> _claim(String adId) async {
    setState(() => _claiming = true);
    try {
      final newBalance = await AdService().claim(adId);
      await ref.read(authProvider.notifier).refreshCoins();
      ref.invalidate(walletHistoryProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('보상 ${_ad?.rewardCoins ?? 1}코인 지급 완료. 잔액 $newBalance'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _error = '보상 지급 실패: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ad = _ad;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(ad?.title ?? '광고 보고 코인 받기'),
      ),
      body: Center(
        child: _error != null
            ? _ErrorView(message: _error!)
            : (c == null || !c.value.isInitialized)
                ? const CircularProgressIndicator(color: Colors.white)
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      ),
                      if (_claiming)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
      ),
      bottomNavigationBar: ad == null
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              color: Colors.black,
              child: Text(
                '끝까지 시청하면 ${ad.rewardCoins}코인이 지급됩니다.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: AppTheme.textHint, size: 48),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
