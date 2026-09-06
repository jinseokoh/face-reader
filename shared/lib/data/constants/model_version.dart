/// 모델 버전 (APPLE.md §58·§59).
///
/// 결과마다 기록해 "이 카드는 어느 식으로 계산됐는가" 를 남긴다. 같은 입력 +
/// 같은 버전 = 같은 결과(엔진에 난수 없음). 화면의 백분위·첫인상은 저장된 z 에
/// 현재 분위표를 다시 적용하므로, 카드의 버전과 현재 버전이 다르면 리포트가
/// 그 사실을 알린다.
///
/// 올리는 기준
/// - geometry   : 계측·대칭 식, AAF reference(mean/sd), 계측·대칭·프로필 분위표
/// - impression : 1층 근거 · 2층 feature · 3층 식 · 축 분위표
/// - pair       : 닮은 정도 거리 식·상수, 유사도·조화·보완·케미 합, 사분위 경계
library;

const String kGeometryModelVersion = '1.1.0'; // §6 계측 4개 · 보정 위치 · 대칭
const String kImpressionModelVersion = '1.1.0'; // averageness 30 계측 · 분위표
const String kPairModelVersion = '1.1.0'; // 케미 등급 경계 재보정

/// 저장용 — 리포트 `modelVersion`, 케미 방 payload `modelVersion`.
Map<String, String> currentModelVersions() => const {
      'geometry': kGeometryModelVersion,
      'impression': kImpressionModelVersion,
      'pair': kPairModelVersion,
    };
