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
              '다만, 궁합·케미 그룹에서 어느 결과가 누구의 것인지 구분하기 위한 최소한의 정보로 '
              '극히 낮은 해상도 (200x200픽셀) 의 얼굴 썸네일 단 한장 뿐이며. 회원 탈퇴 시 삭제됩니다.',
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
