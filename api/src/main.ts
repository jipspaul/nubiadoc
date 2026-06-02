import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/http-exception.filter';
import { loadEnv } from './core/config/env';

async function bootstrap(): Promise<void> {
  const env = loadEnv(); // fail-fast si une variable critique manque
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());

  await app.listen(env.port);
  Logger.log(`Nubia API (${env.mode}) démarrée sur :${env.port}`, 'Bootstrap');
}

void bootstrap();
