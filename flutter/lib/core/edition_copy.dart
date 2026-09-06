import 'edition.dart';

/// 에디션별 화면 문구 — 전부 `const` 라 쓰이지 않는 쪽은 빌드에서 빠진다.
///
/// measure 에디션(iOS v1)은 관상·궁합이라는 말을 화면 어디에도 쓰지 않는다.
/// 탭·앱바·빈 화면·버튼 문구가 한 단어를 쓰도록 여기 한 곳에 둔다
/// (APPLE.md §81.5). full 에디션(Android)은 지금 문구 그대로.
abstract final class EditionCopy {
  // ── 탭 · 앱바 ──
  static const String tabFace = kMeasureEdition ? '첫인상' : '관상';
  static const String tabPair = kMeasureEdition ? '비교' : '궁합';
  static const String faceTitle = kMeasureEdition ? '첫인상 분석' : '관상';
  static const String pairTitle = kMeasureEdition ? '두 얼굴 비교' : '궁합';

  // ── 촬영 pill ──
  static const String scanMine = kMeasureEdition ? '내 얼굴 측정' : '내 관상 보기';
  static const String scanOther = kMeasureEdition ? '얼굴 측정' : '관상 보기';

  // ── 첫인상(관상) 탭 빈 화면 ──
  static const List<String> faceCreditsIntro = kMeasureEdition
      ? [
          '얼굴의 468개 점을 재서',
          '28개 계측값과 평균 대비 위치를',
          '보여줍니다.',
          '그 계측값으로 첫인상 지표와',
          '두 얼굴 비교, 케미를 계산합니다.\n',
        ]
      : [
          '관상은 미래의 운명을',
          '단정짓는 점술이 아니라,',
          '내 삶의 모습을 살피고',
          '그 안에 비친 나 자신을',
          '돌아보게 하는 전통적',
          '오랜 지혜입니다.\n',
        ];
  static const List<String> faceCreditsCameraTail = kMeasureEdition
      ? ['카메라로 얼굴을 재면', '이곳에 저장됩니다.']
      : ['관상을 카메라로 등록하면', '이곳에 저장됩니다.'];
  static const List<String> faceCreditsAlbumTail = kMeasureEdition
      ? ['앨범 사진으로 얼굴을 재면', '이곳에 저장됩니다.']
      : ['관상을 앨범으로 등록하면', '이곳에 저장됩니다.'];
  static const List<String> faceCreditsBookmarkTail = kMeasureEdition
      ? ['공유받은 상대방의 측정 카드를', '북마크하면 이곳에 저장됩니다.']
      : ['공유받은 상대방의 관상 카드를', '북마크하면 이곳에 저장됩니다.'];
  static const String faceEmptyBefore =
      kMeasureEdition ? '내 얼굴부터 재 보세요.' : '내 관상부터 확인해 보세요.';
  static const String faceEmptyAfter = kMeasureEdition
      ? '계속해서 다른 사람의 얼굴도 잴 수 있어요.'
      : '계속해서 다른 사람의 관상도 볼 수 있어요.';
  static const String faceCameraDesc = kMeasureEdition
      ? '카메라로 찍은 사진으로 잰 얼굴입니다.'
      : '카메라로 찍은 사진으로 본 관상입니다.';
  static const String faceAlbumDesc = kMeasureEdition
      ? '앨범 사진으로 잰 얼굴입니다.'
      : '앨범 사진으로 본 관상입니다.';
  static const String faceBookmarkDesc = kMeasureEdition
      ? '공유받아 북마크한 측정 카드입니다.'
      : '공유받아 북마크한 관상입니다.';

  // ── 비교(궁합) 탭 빈 화면 ──
  static const List<String> pairIntro = kMeasureEdition
      ? [
          '두 얼굴의 계측값을 나란히 놓고',
          '닮은 정도와 첫인상 프로필의',
          '조화도·보완도를 계산합니다.\n',
        ]
      : [
          '관상학적 궁합은 두 사람간',
          '관상의 조화가 통계적으로',
          '얼마나 빈번히 관찰되는지를 살펴보고',
          '풀이하는 전통적인 해석법입니다.\n',
        ];
  static const List<String> pairCreditsAfterTail = kMeasureEdition
      ? [
          '얼굴 측정은 얼마든지 무료입니다.',
          '먼저 첫인상 탭에서 다른 사람의',
          '얼굴을 재야 그 사람과',
          '나를 비교할 수 있어요.',
        ]
      : [
          '관상은 얼마든지 무료로',
          '볼 수 있습니다. 먼저 관상탭에서',
          '다른 사람의 관상을 봐야지만',
          '그들과 나와의 궁합을 볼 수 있어요.',
        ];
  static const List<String> pairCreditsBeforeTail = kMeasureEdition
      ? ['우선 내 얼굴을 잰 후에만', '다른 사람과 비교할 수 있어요.']
      : ['우선 내 관상을 본 후에만', '다른 사람과의 궁합을 볼 수 있어요.'];
  static const String pairNeedMyFace = kMeasureEdition
      ? '비교하려면 내 얼굴 측정이 필요합니다.'
      : '궁합을 보려면 내 관상 등록이 필요합니다.';
  static const String pairDeleteTitle = kMeasureEdition ? '비교 삭제' : '궁합 삭제';
  static const String pairDoneMessage = kMeasureEdition
      ? '두 얼굴 비교가 완성되었습니다.'
      : '궁합 풀이가 완성되었습니다.';
  static const String pairNeedFaceFirst =
      kMeasureEdition ? '우선 얼굴을 재야 합니다.' : '우선 관상을 보셔야 합니다.';
  static const String pairEmptyLocked =
      kMeasureEdition ? '미확인 비교가 없습니다.' : '미확인 궁합이 없습니다.';
  static const String pairEmptyUnlocked =
      kMeasureEdition ? '아직 확인한 비교가 없습니다.' : '아직 확인한 궁합이 없습니다.';
  static const String pairDetailTitle = kMeasureEdition ? '두 얼굴 비교' : '궁합 풀이';
  static const String pairShareTitle = kMeasureEdition ? '두 얼굴 비교' : '궁합도 과학이다';
}
