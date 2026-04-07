import { Body, Controller, Post } from '@nestjs/common';
import { AnalysisService } from './analysis.service';
import { FaceAnalysisRequestDto } from './dto/face-analysis.dto';
import { FaceReportResponseDto } from './dto/face-report.dto';

@Controller('analysis')
export class AnalysisController {
  constructor(private readonly analysisService: AnalysisService) {}

  @Post('report')
  async generateReport(
    @Body() dto: FaceAnalysisRequestDto,
  ): Promise<FaceReportResponseDto> {
    return this.analysisService.generateReport(dto);
  }
}
