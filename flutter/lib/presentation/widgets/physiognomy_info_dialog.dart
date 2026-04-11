import 'package:face_reader/core/theme.dart';
import 'package:flutter/material.dart';

class PhysiognomyInfoDialog extends StatefulWidget {
  final double maxHeight;
  const PhysiognomyInfoDialog({super.key, required this.maxHeight});

  @override
  State<PhysiognomyInfoDialog> createState() => _PhysiognomyInfoDialogState();
}

class _PhysiognomyInfoDialogState extends State<PhysiognomyInfoDialog>
    with SingleTickerProviderStateMixin {
  static const _paragraphs = [
    '본 앱은 MediaPipe Face Mesh(468개 랜드마크)를 활용하여 얼굴의 기하학적 비율을 정밀하게 측정합니다. '
        '측정된 15가지 안면 비율은 Leslie Farkas의 인체계측학 연구(1994), '
        'ICD 메타분석(PMC9029890, 22,638명), NIOSH 안면 데이터셋(3,997명) 등 '
        '학술 문헌에 기반한 인종·성별별 레퍼런스 데이터와 비교하여 Z-score로 산출됩니다.',
    '관상학은 동양에서 수천 년간 이어져 온 전통적 인상 해석 체계입니다. '
        '본 앱은 이러한 문화적 유산에 현대 컴퓨터 비전 기술과 통계학적 방법론을 접목하여, '
        '얼굴 비율이 인구 평균 대비 어떤 특성을 보이는지를 객관적 수치로 제시합니다. '
        '10가지 속성 점수와 원형(archetype) 분류는 전통 관상학의 해석 틀을 참고하되, '
        '성별·연령·인종에 따른 가중치 보정을 적용하여 보다 세밀한 분석을 제공합니다.',
    '다만, 관상학적 해석은 과학적으로 검증된 인과관계가 아니라 '
        '문화적·경험적 관찰에 기반한 것임을 분명히 합니다. '
        '얼굴 비율의 통계적 분석은 객관적이나, 이를 성격이나 운명과 연결짓는 해석은 '
        '전통 문화의 관점에서 제공되는 것이며, 개인을 판단하는 절대적 기준이 될 수 없습니다.',
    '아울러, 본 앱은 촬영하거나 선택한 사진을 외부 서버로 전송하거나 저장하지 않습니다. '
        '모든 얼굴 분석은 기기 내에서 수행되며, 저장되는 것은 오직 얼굴 비율의 수치 측정 결과뿐입니다. '
        '원본 사진은 분석 직후 메모리에서 해제되며, 앨범 사진의 경우 소형 썸네일만 기기 내부에 보관합니다. '
        '여러분의 사진이 어디론가 전송되는 일은 절대 없으니 안심하고 이용해 주십시오.',
    '본 앱의 결과는 과학적 측정과 전통 문화적 해석이 만나는 흥미로운 교차점으로서 '
        '즐겁게 참고하시되, 어디까지나 재미와 교양의 영역으로 받아들여 주시기 바랍니다. '
        '모든 사람의 얼굴에는 저마다의 아름다움과 고유한 이야기가 담겨 있습니다. '
        '보다 존중하는 시각으로 얼굴을 바라보는 계기가 되길 바랍니다. -- 위험한 관상가, 오진석 드림',
  ];

  late final AnimationController _controller;
  final List<Animation<double>> _fadeAnims = [];
  final List<Animation<Offset>> _slideAnims = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('관상 분석에 대하여',
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
