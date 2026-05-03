import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.useGlobalPipes(new ValidationPipe({ transform: true }));
  const env = process.env.NODE_ENV || 'development';
  const port = Number(process.env.PORT) || 3001;
  await app.listen(port, '0.0.0.0', () => {
    console.log(`🚀 Application's running on port ${port} in ${env} mode!`);
    console.log('TZ =', process.env.TZ);
    console.log('Now =', new Date().toString());
  });
}

bootstrap().catch((error) => {
  console.error('Failed to start application:', error);
  process.exit(1);
});
