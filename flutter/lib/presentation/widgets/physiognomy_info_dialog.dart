import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class PhysiognomyInfoDialog extends StatelessWidget {
  const PhysiognomyInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('관상 분석에 대하여', style: AppText.modalTitle),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '구글의 오픈소스 기술을 통해 얼굴의 468개 랜드마크를 추출 후 '
              '기하학적 비율을 실측하여, 합성곱 신경망을 통해 분류하고 AAF 공개 데이터셋 '
              '13,322장 얼굴 사진 데이터로 보정된 통계 엔진을 통해 '
              '전통 관상학의 해석을 과학적으로 풀어드립니다.',
              style: AppText.body,
            ),
            SizedBox(height: 18),
            Text('카메라', style: AppText.sectionTitle),
            SizedBox(height: 10),
            _QuoteBlock(
              child: Text(
                '관상 추가 버튼을 눌러 카메라로 촬영해 관상을 봤을 때 누적되는 탭입니다.',
                style: AppText.body,
              ),
            ),
            SizedBox(height: 18),
            Text('앨범', style: AppText.sectionTitle),
            SizedBox(height: 10),
            _QuoteBlock(
              child: Text.rich(
                TextSpan(
                  style: AppText.body,
                  children: [
                    TextSpan(text: '앨범 사진으로 관상을 봤을때 누적되는 탭입니다. 관상 추가 버튼을 누르면 나오는 카메라 화면의 촬영 버튼 아래에 `'),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: FaIcon(
                        FontAwesomeIcons.image,
                        size: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextSpan(text: ' 앨범에서 선택` 버튼이 있는데, 이 버튼을 누르면 앨범 사진을 선택할 수 있습니다.'),
                  ],
                ),
              ),
            ),
            SizedBox(height: 18),
            Text('북마크', style: AppText.sectionTitle),
            SizedBox(height: 10),
            _QuoteBlock(
              child: Text(
                '다른 사람이 facely.kr 주소로 공유한 관상을 열람하다가 '
                '북마크했을 때 누적되는 탭입니다.',
                style: AppText.body,
              ),
            ),
            SizedBox(height: 18),
            Divider(height: 1, thickness: 1, color: AppColors.border),
            SizedBox(height: 18),
            Text('사진 처리', style: AppText.sectionTitle),
            SizedBox(height: 10),
            Text(
              '얼굴 비율 측정은 전부 기기 안에서 수행됩니다. '
              '인종·성별·연령대 추론을 위한 별도의 파이프 라인에서도 자료는 보관되지 않습니다. '
              '다만, 궁합·케미 그룹에서 결과의 주인을 구분하기 위한 최소한의 정보인 200×200픽셀의 '
              '저해상도 얼굴 썸네일 1장을 안전하게 저장하며, 해당 이미지는 회원 탈퇴 시 즉시 삭제됩니다.',
              style: AppText.body,
            ),
            SizedBox(height: 18),
            Text('해석의 한계', style: AppText.sectionTitle),
            SizedBox(height: 10),
            Text(
              '관상학적 해석은 과학적으로 검증된 인과관계가 아니라 '
              '문화적·경험적 관찰에 기반합니다. '
              '재미와 교양의 영역으로 즐겁게 참고해 주시기 바랍니다.',
              style: AppText.body,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기', style: AppText.subTitle),
        ),
      ],
    );
  }
}

/// 카메라/앨범/북마크 탭 설명 전용 blockquote — 좌측 bar + 들여쓰기로
/// 기능 설명임을 본문과 구분.
class _QuoteBlock extends StatelessWidget {
  final Widget child;
  const _QuoteBlock({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.border, width: 3),
        ),
      ),
      child: child,
    );
  }
}

/// measure 에디션(iOS v1) 첫인상 탭 (i) 안내 — 관상 단어 없이 측정·첫인상만.
class MeasureFaceInfoDialog extends StatelessWidget {
  const MeasureFaceInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('첫인상 분석에 대하여', style: AppText.modalTitle),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '얼굴의 468개 점을 찾아 28개 계측값을 잽니다. 값마다 동아시아 얼굴 11,800장 '
              '실측 분포 안에서 어디쯤인지(상위 N%)를 보여줍니다.',
              style: AppText.body,
            ),
            SizedBox(height: 18),
            Text('첫인상 지표', style: AppText.sectionTitle),
            SizedBox(height: 10),
            Text(
              '신뢰감·친근함·주도성·매력 네 가지 인상 축입니다. 얼굴의 어떤 특징이 어떤 '
              '인상과 연결되는지에 관한 공개 학술연구를 근거로, 계측값에서 축 점수를 '
              '계산해 같은 실측 분포로 백분위를 냅니다. 원 논문의 모델을 재현한 것이 '
              '아니며, 한국인만을 대상으로 학습·검증된 모델이 아닙니다. 실제 '
              '성격·능력이 아니라 얼굴 형태의 상대 위치입니다.',
              style: AppText.body,
            ),
            SizedBox(height: 18),
            Text('얼굴 지도', style: AppText.sectionTitle),
            SizedBox(height: 10),
            Text(
              '내 얼굴의 468개 특징점에서 사진 속 위치·크기·기울기를 빼고 모양만 남겨 '
              '같은 성별의 평균 얼굴 위에 겹친 그림입니다. 겹치는 방법은 프로크루스테스 '
              '정렬(Procrustes analysis)로, 두 형태의 위치·크기·회전을 맞춘 뒤 남는 '
              '차이만 재는 형태 비교의 표준 방법입니다.',
              style: AppText.body,
            ),
            SizedBox(height: 18),
            Text('카메라 · 앨범 · 북마크', style: AppText.sectionTitle),
            SizedBox(height: 10),
            Text(
              '카메라로 찍거나 앨범 사진으로 잰 얼굴이 각 탭에 쌓입니다. 다른 사람이 '
              'facely.kr 주소로 공유한 카드를 북마크하면 북마크 탭에 쌓입니다.',
              style: AppText.body,
            ),
            SizedBox(height: 18),
            Text('사진 처리', style: AppText.sectionTitle),
            SizedBox(height: 10),
            Text(
              '얼굴 계측은 전부 기기 안에서 수행됩니다. 성별·연령대 추정을 위한 축소본은 '
              '분석 직후 삭제됩니다. 비교·케미 그룹에서 결과의 주인을 구분하기 위한 '
              '200×200픽셀 저해상도 얼굴 썸네일 1장만 저장하며, 회원 탈퇴 시 즉시 삭제됩니다.',
              style: AppText.body,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기', style: AppText.subTitle),
        ),
      ],
    );
  }
}
