import 'edition.dart';

/// 에디션별 화면 문구 — [kMeasureEdition] 은 런타임(플랫폼) 판정이라 전부 getter 다.
///
/// measure 에디션(iOS v1)은 관상·궁합이라는 말을 화면 어디에도 쓰지 않는다.
/// 탭·앱바·빈 화면·버튼 문구가 한 단어를 쓰도록 여기 한 곳에 둔다
/// (APPLE.md §81.5). full 에디션(Android)은 지금 문구 그대로.
abstract final class EditionCopy {
  // ── 탭 · 앱바 ──
  static String get tabFace => kMeasureEdition ? '첫인상' : '관상';
  static String get tabPair => kMeasureEdition ? '비교' : '궁합';
  static String get faceTitle => kMeasureEdition ? '첫인상 분석' : '관상';
  static String get pairTitle => kMeasureEdition ? '두 얼굴 비교' : '궁합';

  // ── 촬영 pill ──
  static String get scanMine => kMeasureEdition ? '내 얼굴 측정' : '내 관상 보기';
  static String get scanOther => kMeasureEdition ? '얼굴 측정' : '관상 보기';

  // ── 첫인상(관상) 탭 빈 화면 ──
  static List<String> get faceCreditsIntro => kMeasureEdition
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
  static List<String> get faceCreditsCameraTail => kMeasureEdition
      ? ['카메라로 얼굴을 재면', '이곳에 저장됩니다.']
      : ['관상을 카메라로 등록하면', '이곳에 저장됩니다.'];
  static List<String> get faceCreditsAlbumTail => kMeasureEdition
      ? ['앨범 사진으로 얼굴을 재면', '이곳에 저장됩니다.']
      : ['관상을 앨범으로 등록하면', '이곳에 저장됩니다.'];
  static List<String> get faceCreditsBookmarkTail => kMeasureEdition
      ? ['공유받은 상대방의 측정 카드를', '북마크하면 이곳에 저장됩니다.']
      : ['공유받은 상대방의 관상 카드를', '북마크하면 이곳에 저장됩니다.'];
  static String get faceEmptyBefore =>
      kMeasureEdition ? '내 얼굴부터 재 보세요.' : '내 관상부터 확인해 보세요.';
  static String get faceEmptyAfter => kMeasureEdition
      ? '계속해서 다른 사람의 얼굴도 잴 수 있어요.'
      : '계속해서 다른 사람의 관상도 볼 수 있어요.';
  static String get faceCameraDesc => kMeasureEdition
      ? '카메라로 찍은 사진으로 잰 얼굴입니다.'
      : '카메라로 찍은 사진으로 본 관상입니다.';
  static String get faceAlbumDesc => kMeasureEdition
      ? '앨범 사진으로 잰 얼굴입니다.'
      : '앨범 사진으로 본 관상입니다.';
  static String get faceBookmarkDesc => kMeasureEdition
      ? '공유받아 북마크한 측정 카드입니다.'
      : '공유받아 북마크한 관상입니다.';

  // ── 비교(궁합) 탭 빈 화면 ──
  static List<String> get pairIntro => kMeasureEdition
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
  static List<String> get pairCreditsAfterTail => kMeasureEdition
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
  static List<String> get pairCreditsBeforeTail => kMeasureEdition
      ? ['우선 내 얼굴을 잰 후에만', '다른 사람과 비교할 수 있어요.']
      : ['우선 내 관상을 본 후에만', '다른 사람과의 궁합을 볼 수 있어요.'];
  static String get pairNeedMyFace => kMeasureEdition
      ? '비교하려면 내 얼굴 측정이 필요합니다.'
      : '궁합을 보려면 내 관상 등록이 필요합니다.';
  static String get pairDeleteTitle => kMeasureEdition ? '비교 삭제' : '궁합 삭제';
  static String get pairDoneMessage => kMeasureEdition
      ? '두 얼굴 비교가 완성되었습니다.'
      : '궁합 풀이가 완성되었습니다.';
  static String get pairNeedFaceFirst =>
      kMeasureEdition ? '우선 얼굴을 재야 합니다.' : '우선 관상을 보셔야 합니다.';
  static String get pairEmptyLocked =>
      kMeasureEdition ? '미확인 비교가 없습니다.' : '미확인 궁합이 없습니다.';
  static String get pairEmptyUnlocked =>
      kMeasureEdition ? '아직 확인한 비교가 없습니다.' : '아직 확인한 궁합이 없습니다.';
  static String get pairDetailTitle => kMeasureEdition ? '두 얼굴 비교' : '궁합 풀이';
  static String get pairShareTitle => kMeasureEdition ? '두 얼굴 비교' : '궁합도 과학이다';
  static String get pairInfoTooltip =>
      kMeasureEdition ? '두 얼굴 비교에 대하여' : '궁합 분석에 대하여';
  static String get pairDeleteBody => kMeasureEdition
      ? '이 비교를 목록에서 삭제할까요?\n사용한 코인은 환불되지 않습니다.'
      : '이 궁합을 목록에서 삭제할까요?\n사용한 코인은 환불되지 않습니다.';
  static String get pairLockedDesc => kMeasureEdition
      ? '아직 확인하지 않은 비교입니다.'
      : '아직 풀이를 확인하지 않은 궁합입니다.';
  static String get pairUnlockedDesc =>
      kMeasureEdition ? '확인한 비교입니다.' : '풀이를 확인한 궁합입니다.';
  static String get pairUnlockCta =>
      kMeasureEdition ? '1코인으로 비교 보기' : '1코인으로 궁합 보기';
  static String get pairUnlockTitle => kMeasureEdition ? '비교 보기' : '궁합 보기';
  static String get pairUnlockBody => kMeasureEdition
      ? '비교를 보려면 1코인이 필요합니다.\n비교를 보시겠습니까?'
      : '궁합을 보려면 1코인이 필요합니다.\n궁합을 보시겠습니까?';
  static String get pairUnlockButton => kMeasureEdition ? '비교 보기' : '궁합보기';
  static String get pairLockedNudge => kMeasureEdition
      ? '내 얼굴을 재면 비교할 수 있습니다.'
      : '나의 관상을 등록하면 궁합을 볼 수 있습니다.';
  static String get pairLockedUntil => kMeasureEdition
      ? '내 얼굴이 등록되기 전까지는 비교가 잠겨있게 됩니다.'
      : '나의 관상이 등록되기 전까지는 궁합이 잠겨있게 됩니다.';
  static String get ledgerCompatUnlock => kMeasureEdition ? '비교 보기' : '궁합 보기';

  // ── 내 얼굴(관상) 등록 상태 ──
  static String get myFaceNeeded =>
      kMeasureEdition ? '내 얼굴 측정이 필요합니다.' : '내 관상이 필요합니다.';
  static String get myFaceBadge => kMeasureEdition ? '내 얼굴' : '내 관상';
  static String get myFaceRegistered =>
      kMeasureEdition ? '얼굴 측정을 등록했습니다.' : '관상을 성공적으로 등록했습니다.';
  static String get myFaceServerFail => kMeasureEdition
      ? '내 얼굴 측정 서버 등록에 실패했습니다'
      : '내 관상 서버 등록에 실패했습니다';
  static String get noMyFaceError =>
      kMeasureEdition ? '내 얼굴 측정이 필요합니다' : '내 관상 등록이 필요합니다';
  static String get chatNeedsMyFace => kMeasureEdition
      ? '채팅에 참여하려면 내 얼굴을 재세요.'
      : '채팅에 참여하려면 내 관상을 보세요.';

  // ── 케미 ──
  static String get teamAgeGateBody => kMeasureEdition
      ? '케미 그룹 만들기는 20세 이상부터 사용할 수 있습니다. 내 얼굴 측정의 나이대가 10대로 확인되어 지금은 만들 수 없습니다.'
      : '케미 그룹 만들기는 20세 이상부터 사용할 수 있습니다. 내 관상 분석의 나이대가 10대로 확인되어 지금은 만들 수 없습니다.';
  static String get teamInfoBody => kMeasureEdition
      ? '6 ~ 12명 정원의 그룹을 만들어 온라인에서 만나는 다양한 사람들과의 첫인상 케미를 확인하는 기능입니다.\n\n'
          '케미 그룹은 누구나 만들 수 있고 그룹에 참여 정원이 다 차면 그 즉시 그룹내 참여자들간 얼굴 계측값과 첫인상 프로필로 계산한 케미 결과표가 자동으로 발표됩니다.\n\n'
          '해당 그룹내에서 최고의 케미를 보인 베스트 매칭 한 쌍에게는 1:1 채팅 기회가 주어집니다. 물론, 두 사람 모두 채팅을 원하는 경우에만 채팅방이 열리고, 한쪽이라도 거부하면 열리지 않습니다. 결과 발표이후 한 달이 지난 뒤에는 자동으로 삭제됩니다.\n\n'
          '공개 그룹은 언제든 참가할 수 있고, 그룹 만들기 기능을 통해 원하는 그룹을 직접 만들 수도 있습니다. 지인들끼리만 모이고 싶다면 그룹을 만들때 비밀번호를 설정하세요.\n\n'
          '공유하기 기능을 이용하면 카카오톡 등 원하는 채널을 통해 내가 만든 그룹에 초대할 수 있습니다.'
      : '6 ~ 12명 정원의 그룹을 만들어 온라인에서 만나는 다양한 사람들과의 서로 관상학적 케미가 좋은지 확인하는 기능입니다.\n\n'
          '케미 그룹은 누구나 만들 수 있고 그룹에 참여 정원이 다 차면 그 즉시 그룹내 참여자들간 관상으로 따져본 케미 결과표가 자동으로 발표됩니다.\n\n'
          '해당 그룹내에서 최고의 케미를 보인 베스트 매칭 한 쌍에게는 1:1 채팅 기회가 주어집니다. 물론, 두 사람 모두 채팅을 원하는 경우에만 채팅방이 열리고, 한쪽이라도 거부하면 열리지 않습니다. 결과 발표이후 한 달이 지난 뒤에는 자동으로 삭제됩니다.\n\n'
          '공개 그룹은 언제든 참가할 수 있고, 그룹 만들기 기능을 통해 원하는 그룹을 직접 만들 수도 있습니다. 지인들끼리만 모이고 싶다면 그룹을 만들때 비밀번호를 설정하세요.\n\n'
          '공유하기 기능을 이용하면 카카오톡 등 원하는 채널을 통해 내가 만든 그룹에 초대할 수 있습니다.';

  static String get myFaceRecapture =>
      kMeasureEdition ? '내 얼굴 다시 재기' : '내 관상 다시 찍기';
  static String get myFaceOpenRoomsBody => kMeasureEdition
      ? '내 얼굴 측정으로 연 모집 중인 방이 있습니다.\n'
      : '내 관상으로 연 모집 중인 방이 있습니다.\n';
  static String get bookmarkEmpty => kMeasureEdition
      ? '전달받은 비교는 이 곳에 북마크해 둘 수 있어요.'
      : '전달받은 궁합은 이 곳에 북마크해 둘 수 있어요.';
  static String get deleteItemFace =>
      kMeasureEdition ? '저장된 얼굴 측정 기록 전부 삭제' : '저장된 관상 기록 전부 삭제';
  static String get deleteItemPair =>
      kMeasureEdition ? '저장된 비교 기록 전부 삭제' : '저장된 궁합 기록 전부 삭제';

  // ── 스플래시 ──
  static String get splashTagline =>
      kMeasureEdition ? '얼굴을 재서 우리 그룹 케미를 봅니다' : '관상으로 풀어보는 친구 만들기';
}
