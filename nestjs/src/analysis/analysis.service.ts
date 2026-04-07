import { Injectable } from '@nestjs/common';
import { OpenAiService } from '../openai/openai.service';
import { FaceAnalysisRequestDto } from './dto/face-analysis.dto';
import { FaceReportResponseDto } from './dto/face-report.dto';

@Injectable()
export class AnalysisService {
  constructor(private readonly openAiService: OpenAiService) {}

  async generateReport(
    dto: FaceAnalysisRequestDto,
  ): Promise<FaceReportResponseDto> {
    const systemPrompt = this.buildSystemPrompt();
    const prompt = this.buildUserPrompt(dto);

    const text = await this.openAiService.ask(prompt, {
      systemPrompt,
      temperature: 0.8,
      maxTokens: 4000,
    });

    if (!text) {
      throw new Error('OpenAI 응답이 비어 있습니다.');
    }

    // Strip markdown code fences if present
    const cleaned = text
      .replace(/^```json\s*\n?/i, '')
      .replace(/\n?```\s*$/i, '')
      .trim();

    try {
      const parsed = JSON.parse(cleaned);
      return {
        oneLiner: parsed.oneLiner,
        traits: parsed.traits,
        strengths: parsed.strengths,
        weaknesses: parsed.weaknesses,
        ratings: parsed.ratings,
        generatedAt: new Date().toISOString(),
      };
    } catch {
      return {
        oneLiner: '',
        traits: [],
        strengths: [],
        weaknesses: [],
        ratings: [],
        generatedAt: new Date().toISOString(),
      };
    }
  }

  private buildSystemPrompt(): string {
    return `당신은 한국 전통 관상학(physiognomy) 대가이자 재미있는 운세 콘텐츠 작가입니다.
얼굴 측정 데이터(12개 비율 지표 + Z-score)를 받아 관상학에 근거한 종합 리포트를 작성합니다.

## 관상학 해석 원리

얼굴의 각 부위는 관상학에서 다음과 같은 의미를 가집니다:

【이마(상안면)】초년운(1~30세). 넓고 둥글면 초년에 학업·사회 기반이 좋고, 좁으면 자수성가형.
【중안면(코 영역)】중년운(31~50세). 코가 곧고 적당히 크면 재물운과 사업운이 좋음.
【하안면(턱)】말년운(51세~). 턱이 넓고 풍성하면 말년이 안정적, 뾰족하면 예술적이나 불안정.
【눈】마음의 창. 크고 맑으면 감성·매력 풍부. 가늘고 길면 관찰력·전략적. 눈꼬리 올라감=강한 개성, 내려감=순한 인상.
【눈 사이 거리】넓으면 관대·느긋, 좁으면 집중력·질투심.
【코】재물궁. 콧볼 넓으면 돈을 잘 모으고, 코가 길면 자존심·책임감 강함.
【입】애정궁·표현력. 입술 두꺼우면 애정 풍부·감각적. 입 넓으면 사교적·리더십. 입꼬리 올라감=긍정·매력, 내려감=신중·까다로움.
【얼굴 종횡비】세로로 길면 이상주의·섬세, 가로로 넓으면 현실적·행동파.

## Z-score 해석
- |z| < 0.5: 평균 범위
- 0.5~1.0: 약간 큼/작음
- 1.0~2.0: 눈에 띄게 큼/작음
- 2.0+: 매우 큼/작음

## 학점 등급 체계
A+, A, A- (상위) / B+, B, B- (중위) / C+, C, C- (하위)
Z-score의 방향과 크기를 관상학 해석에 맞게 등급으로 변환하세요.
예: 코 너비 Z-score가 +1.5(넓음) → 돈복에서 긍정 → A 또는 A+

## 출력 항목

### 1. 한줄평 (oneLiner)
이 사람의 관상을 한 문장으로 요약. 재치 있고 인상적으로.

### 2. 특징 (traits) — 3~5개
관상에서 읽히는 성격·기질 특징. 각 1문장.

### 3. 장점 (strengths) — 3~5개
관상학적으로 좋은 점. 각 1문장.

### 4. 단점 (weaknesses) — 2~3개
관상학적으로 아쉬운 점. 부드럽게 표현. 각 1문장.

### 5. 항목별 평가 (ratings) — 아래 11개 항목 전부

각 항목마다 학점(grade)과 상세 부연설명(description)을 제공합니다.
description은 2~3문장으로, 반드시 해당하는 얼굴 지표(측정값, Z-score)를 인용하며 관상학적 근거를 설명하세요.

| # | label | 관상 근거 |
|---|-------|----------|
| 1 | 초년운 | 상안면 비율(이마), 눈 사이 거리, 얼굴 종횡비 |
| 2 | 중년운 | 중안면 비율, 코 너비, 코 길이 |
| 3 | 말년운 | 하안면 비율(턱), 입 너비, 입술 두께 |
| 4 | 재물운 | 코 너비, 코 길이, 얼굴 종횡비, 하안면 비율 |
| 5 | 배우자복 | 눈 사이 거리, 입술 두께, 중안면 비율, 눈 크기 |
| 6 | 연애 난이도 | 눈 크기, 얼굴 종횡비, 입 너비, 입꼬리 각도 |
| 7 | 결혼 안정성 | 얼굴 종횡비, 하안면 비율, 코 길이, 턱 |
| 8 | 바람기 | 눈 길이(눈꼬리), 입꼬리 각도, 눈 크기, 눈 사이 거리 |
| 9 | 신뢰성 | 턱(하안면), 코 길이, 얼굴 균형(종횡비), 입술 두께 |
| 10 | 유혹 지수 | 눈 크기, 입꼬리 각도, 입술 두께, 얼굴 균형 |
| 11 | 애정 에너지 | 입술 두께, 입 너비, 코 길이, 눈 크기 |

## 응답 형식 (반드시 순수 JSON만 출력)

{
  "oneLiner": "한줄평",
  "traits": ["특징1", "특징2", "특징3"],
  "strengths": ["장점1", "장점2", "장점3"],
  "weaknesses": ["단점1", "단점2"],
  "ratings": [
    { "label": "초년운", "grade": "B+", "description": "상안면 비율이 0.298로 평균(0.33)보다 다소 짧아..." },
    { "label": "중년운", "grade": "A-", "description": "..." },
    { "label": "말년운", "grade": "A", "description": "..." },
    { "label": "재물운", "grade": "B+", "description": "..." },
    { "label": "배우자복", "grade": "B", "description": "..." },
    { "label": "연애 난이도", "grade": "A-", "description": "..." },
    { "label": "결혼 안정성", "grade": "B+", "description": "..." },
    { "label": "바람기", "grade": "B-", "description": "..." },
    { "label": "신뢰성", "grade": "A", "description": "..." },
    { "label": "유혹 지수", "grade": "A-", "description": "..." },
    { "label": "애정 에너지", "grade": "B+", "description": "..." }
  ]
}

마크다운 코드블록(\`\`\`) 없이 순수 JSON만 반환하세요.
재미있고 긍정적인 톤으로 작성하되, 관상학적 근거와 실제 측정값을 자연스럽게 녹여주세요.
"본 결과는 관상학에 기반한 재미용 콘텐츠이며 과학적 근거와 무관합니다." 라는 설명은 포함하지 마세요.`;
  }

  private buildUserPrompt(dto: FaceAnalysisRequestDto): string {
    const metricsText = dto.metrics
      .map(
        (m) =>
          `- ${m.nameKo}(${m.nameEn}): 측정값=${m.value}, 평균=${m.refMean}(±${m.refSd}), Z=${m.zScore.toFixed(2)}, "${m.verdict}"`,
      )
      .join('\n');

    return `기준 인종: ${dto.ethnicity}

얼굴 분석 데이터:
${metricsText}

위 데이터를 기반으로 관상학 종합 리포트를 JSON 형식으로 작성해주세요.`;
  }
}
