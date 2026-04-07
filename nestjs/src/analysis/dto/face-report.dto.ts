export class PhysiognomyRating {
  label: string; // e.g. '초년운'
  grade: string; // 'A+' | 'A' | 'A-' | 'B+' | 'B' | 'B-' | 'C+' | 'C' | 'C-'
  description: string; // 관상 근거를 포함한 상세 부연설명
}

export class FaceReportResponseDto {
  oneLiner: string; // 한줄평
  traits: string[]; // 특징 (3~5개)
  strengths: string[]; // 장점 (3~5개)
  weaknesses: string[]; // 단점 (2~3개)
  ratings: PhysiognomyRating[]; // 11개 항목별 학점 + 상세 설명
  generatedAt: string;
}
