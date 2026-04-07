import {
  IsString,
  IsNumber,
  IsArray,
  ValidateNested,
  IsIn,
} from 'class-validator';
import { Type } from 'class-transformer';

export class MetricAnalysisDto {
  @IsString()
  id: string;

  @IsString()
  nameKo: string;

  @IsString()
  nameEn: string;

  @IsIn(['face', 'eyes', 'nose', 'mouth'])
  category: string;

  @IsNumber()
  value: number;

  @IsNumber()
  refMean: number;

  @IsNumber()
  refSd: number;

  @IsNumber()
  zScore: number;

  @IsString()
  verdict: string;
}

export class FaceAnalysisRequestDto {
  @IsString()
  ethnicity: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => MetricAnalysisDto)
  metrics: MetricAnalysisDto[];
}
