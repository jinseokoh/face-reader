import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { OpenAiModule } from './openai/openai.module';
import { AnalysisModule } from './analysis/analysis.module';

@Module({
  imports: [OpenAiModule, AnalysisModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
