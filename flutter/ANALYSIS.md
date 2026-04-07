=== 얼굴 분석 리포트 ===
날짜: 2026.04.07 10:01
기준: 동아시아인

--- 얼굴 비율 ---
얼굴 종횡비 (Face Aspect Ratio)
측정값: 1.032 | 평균: 1.380 (±0.080)
Z-score: -4.36 → 매우 가로로 넓은 얼굴

상안면 비율 (Upper Face Ratio)
측정값: 0.298 | 평균: 0.330 (±0.030)
Z-score: -1.05 → 이마가 좁음

중안면 비율 (Mid Face Ratio)
측정값: 0.319 | 평균: 0.330 (±0.020)
Z-score: -0.56 → 약간 중안면이 짧음

하안면 비율 (Lower Face Ratio)
측정값: 0.383 | 평균: 0.340 (±0.030)
Z-score: 1.44 → 턱이 긺

--- 눈 ---
눈 사이 거리 (Intercanthal Distance)
측정값: 0.289 | 평균: 0.270 (±0.020)
Z-score: 0.94 → 약간 눈 사이가 넓음

눈 길이 (Eye Fissure Length)
측정값: 0.212 | 평균: 0.240 (±0.020)
Z-score: -1.42 → 눈이 짧음

눈 크기 (Eye Openness)
측정값: 0.233 | 평균: 0.350 (±0.050)
Z-score: -2.35 → 매우 눈이 작음

--- 코 ---
코 너비 (Nasal Width)
측정값: 1.020 | 평균: 1.050 (±0.100)
Z-score: -0.30 → 평균

코 길이 (Nasal Height)
측정값: 0.319 | 평균: 0.300 (±0.020)
Z-score: 0.94 → 약간 코가 긺

--- 입 ---
입 너비 (Mouth Width)
측정값: 0.403 | 평균: 0.380 (±0.030)
Z-score: 0.76 → 약간 입이 넓음

입술 두께 (Lip Fullness)
측정값: 0.109 | 평균: 0.100 (±0.020)
Z-score: 0.45 → 평균

입꼬리 각도 (Mouth Corner Angle)
측정값: 4.1° | 평균: 0.0° (±3.0°)
Z-score: 1.37 → 입꼬리가 올라감

---

## DTO (FaceAnalysisRequestDto)

위 분석 데이터를 API로 전달할 때 사용하는 JSON 형식:

```json
{
  "ethnicity": "동아시아인",
  "metrics": [
    {
      "id": "faceAspectRatio",
      "name": "얼굴 종횡비",
      "category": "face",
      "value": 1.032,
      "refMean": 1.38,
      "refSd": 0.08,
      "zScore": -4.36,
      "verdict": "매우 가로로 넓은 얼굴"
    },
    {
      "id": "upperFaceRatio",
      "name": "상안면 비율",
      "category": "face",
      "value": 0.298,
      "refMean": 0.33,
      "refSd": 0.03,
      "zScore": -1.05,
      "verdict": "이마가 좁음"
    },
    {
      "id": "midFaceRatio",
      "name": "중안면 비율",
      "category": "face",
      "value": 0.319,
      "refMean": 0.33,
      "refSd": 0.02,
      "zScore": -0.56,
      "verdict": "약간 중안면이 짧음"
    },
    {
      "id": "lowerFaceRatio",
      "name": "하안면 비율",
      "category": "face",
      "value": 0.383,
      "refMean": 0.34,
      "refSd": 0.03,
      "zScore": 1.44,
      "verdict": "턱이 긺"
    },
    {
      "id": "intercanthalRatio",
      "name": "눈 사이 거리",
      "category": "eyes",
      "value": 0.289,
      "refMean": 0.27,
      "refSd": 0.02,
      "zScore": 0.94,
      "verdict": "약간 눈 사이가 넓음"
    },
    {
      "id": "eyeFissureRatio",
      "name": "눈 길이",
      "category": "eyes",
      "value": 0.212,
      "refMean": 0.24,
      "refSd": 0.02,
      "zScore": -1.42,
      "verdict": "눈이 짧음"
    },
    {
      "id": "eyeOpenness",
      "name": "눈 크기",
      "category": "eyes",
      "value": 0.233,
      "refMean": 0.35,
      "refSd": 0.05,
      "zScore": -2.35,
      "verdict": "매우 눈이 작음"
    },
    {
      "id": "nasalWidthRatio",
      "name": "코 너비",
      "category": "nose",
      "value": 1.02,
      "refMean": 1.05,
      "refSd": 0.1,
      "zScore": -0.3,
      "verdict": "평균"
    },
    {
      "id": "nasalHeightRatio",
      "name": "코 길이",
      "category": "nose",
      "value": 0.319,
      "refMean": 0.3,
      "refSd": 0.02,
      "zScore": 0.94,
      "verdict": "약간 코가 긺"
    },
    {
      "id": "mouthWidthRatio",
      "name": "입 너비",
      "category": "mouth",
      "value": 0.403,
      "refMean": 0.38,
      "refSd": 0.03,
      "zScore": 0.76,
      "verdict": "약간 입이 넓음"
    },
    {
      "id": "lipFullnessRatio",
      "name": "입술 두께",
      "category": "mouth",
      "value": 0.109,
      "refMean": 0.1,
      "refSd": 0.02,
      "zScore": 0.45,
      "verdict": "평균"
    },
    {
      "id": "mouthCornerAngle",
      "name": "입꼬리 각도",
      "category": "mouth",
      "value": 4.1,
      "refMean": 0.0,
      "refSd": 3.0,
      "zScore": 1.37,
      "verdict": "입꼬리가 올라감"
    }
  ]
}
```

### API Endpoint

```
POST /analysis/report
Content-Type: application/json
Body: FaceAnalysisRequestDto (위 JSON)

Response: FaceReportResponseDto
{
  "report": "생성된 리포트 텍스트",
  "generatedAt": "2026-04-07T10:01:30.000Z"
}
```

### TypeScript DTO 정의

```typescript
// face-analysis.dto.ts
export class MetricAnalysisDto {
  id: string // metric key (e.g. 'faceAspectRatio')
  name: string // 한국어 이름
  category: string // 'face' | 'eyes' | 'nose' | 'mouth'
  value: number // 측정된 비율값
  refMean: number // 인종별 평균
  refSd: number // 표준편차
  zScore: number // (value - mean) / sd
  verdict: string // 판정 텍스트
}

export class FaceAnalysisRequestDto {
  ethnicity: string // 기준 인종 (e.g. '동아시아인')
  metrics: MetricAnalysisDto[]
}

// face-report.dto.ts
export class FaceReportResponseDto {
  report: string // 생성된 리포트
  generatedAt: string // ISO 8601
}
```
