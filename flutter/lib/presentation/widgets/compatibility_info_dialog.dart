import 'package:face_reader/core/theme.dart';
import 'package:flutter/material.dart';

class CompatibilityInfoDialog extends StatefulWidget {
  final double maxHeight;
  const CompatibilityInfoDialog({super.key, required this.maxHeight});

  @override
  State<CompatibilityInfoDialog> createState() => _CompatibilityInfoDialogState();
}

class _CompatibilityInfoDialogState extends State<CompatibilityInfoDialog>
    with SingleTickerProviderStateMixin {
  static const _paragraphs = [
    '예로부터 관상학은 사람의 얼굴·기질·성향을 읽는 기술이며, '
        '연애·결혼운·배우자운 같은 주제는 상담 현장에서 자연스럽게 따라붙는 영역입니다. '
        '관상가가 두 사람의 성향 궁합까지 함께 살펴보는 것은 업계에서 오랜 전통입니다.',
    '여기서 말하는 궁합은 성격적 궁합, 기질 충돌 여부, 성향의 조화 등 '
        '심리적 성격·성향 중심의 궁합을 뜻합니다. '
        '두 사람의 얼굴 비율에서 드러나는 성격적 특성과 기질 패턴을 비교·분석하여 '
        '서로 간의 조화와 충돌 가능성을 해석합니다.',
    '한편, 궁합의 또 다른 갈래로 사주명리학의 영역이 있습니다. '
        '태어난 연·월·일·시의 음양오행 구조로 관계 운을 해석하는 것으로, '
        '두 사람의 운세 구조·인연 흐름·결혼운을 살피는 운명적 영역의 해석입니다. '
        '본 앱에서 제공하는 궁합은 이러한 사주 기반이 아닌, '
        '관상가의 시각에서 바라보는 성격·심리·성향 중심의 궁합입니다.',
    '궁합 결과 역시 관상학적 해석에 기반한 것이므로 '
        '재미와 참고의 영역으로 받아들여 주시기 바랍니다. '
        '두 사람의 관계는 관상만으로 결정되지 않으며, '
        '서로에 대한 이해와 노력이 어떤 궁합보다 중요합니다. '
        '-- 위험한 관상가, 오진석 드림',
  ];

  late final AnimationController _controller;
  final List<Animation<double>> _fadeAnims = [];
  final List<Animation<Offset>> _slideAnims = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('궁합 분석에 대하여',
          style: TextStyle(
              fontFamily: 'SongMyung',
              fontSize: 18,
              fontWeight: FontWeight.w600)),
      content: SizedBox(
        height: widget.maxHeight - 140,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(_paragraphs.length, (i) {
                return FadeTransition(
                  opacity: _fadeAnims[i],
                  child: SlideTransition(
                    position: _slideAnims[i],
                    child: Padding(
                      padding: EdgeInsets.only(
                          bottom: i < _paragraphs.length - 1 ? 20 : 0),
                      child: Text(
                        _paragraphs[i],
                        style: const TextStyle(
                          fontFamily: 'SongMyung',
                          fontSize: 15,
                          height: 1.8,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('닫기', style: TextStyle(color: AppTheme.textPrimary)),
        ),
      ],
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
      duration: Duration(milliseconds: 600 * _paragraphs.length),
    );

    for (int i = 0; i < _paragraphs.length; i++) {
      final start = i / _paragraphs.length;
      final end = (i + 0.6) / _paragraphs.length;
      final curve = CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end.clamp(0, 1), curve: Curves.easeOutCubic),
      );
      _fadeAnims.add(Tween<double>(begin: 0, end: 1).animate(curve));
      _slideAnims.add(
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
            .animate(curve),
      );
    }

    _controller.forward();
  }
}
