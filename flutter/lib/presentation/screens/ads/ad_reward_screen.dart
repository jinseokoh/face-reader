import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:video_player/video_player.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/data/services/ad_service.dart';

/// custom video 광고 재생 화면 — 무료코인 3편 중 1편 슬롯.
///
/// 흐름:
///  1) 전달받은 [video] 를 video_player 로 재생 (seek 막음)
///  2) 끝까지 시청하면 `Navigator.pop(context, true)` 로 "시청 완료" 반환
///  3) 중간에 닫으면 false/null 반환 (호출부가 무료코인 카운트 안 함)
///
/// 코인 지급·진행도 기록은 호출부(PurchaseSheet)가 AdMob 과 동일하게
/// FreeCoinService.recordView() 로 처리한다 — 본 화면은 재생만 책임.
class AdRewardScreen extends StatefulWidget {
  final AdVideo video;
  const AdRewardScreen({super.key, required this.video});

  @override
  State<AdRewardScreen> createState() => _AdRewardScreenState();
}

class _AdRewardScreenState extends State<AdRewardScreen> {
  VideoPlayerController? _controller;
  bool _completed = false;
  String? _error;
  // forward seek 차단용 — 1초 이상 점프면 seek 으로 간주.
  Duration _lastPos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.video.videoUrl));
      await c.initialize();
      c.addListener(_onTick);
      await c.play();
      if (!mounted) return;
      setState(() => _controller = c);
    } catch (e) {
      if (mounted) setState(() => _error = '광고 로드 실패: $e');
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || _completed) return;
    final pos = c.value.position;
    final dur = c.value.duration;
    if (dur == Duration.zero) return;

    // forward seek 차단 — 1초 이상 앞으로 점프했으면 되돌림.
    if (pos - _lastPos > const Duration(seconds: 1)) {
      c.seekTo(_lastPos);
      return;
    }
    _lastPos = pos;

    if (pos >= dur - const Duration(milliseconds: 250)) {
      _completed = true;
      if (mounted) Navigator.of(context).pop(true);
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.video.title),
      ),
      body: Center(
        child: _error != null
            ? _ErrorView(message: _error!)
            : (c == null || !c.value.isInitialized)
                ? const CircularProgressIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        color: Colors.black,
        child: const Text(
          '끝까지 시청하면 광고 1편으로 카운트됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
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
          FaIcon(FontAwesomeIcons.circleExclamation,
              color: AppTheme.textHint, size: 40),
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
