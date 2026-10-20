import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { NestExpressApplication } from '@nestjs/platform-express';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AppModule } from './app.module';

/**
 * Login throttling keys on the client IP. Behind a reverse proxy, Express only
 * sees the proxy address unless TRUST_PROXY is explicitly configured, which is
 * why the default is off. Set TRUST_PROXY to the number of proxy hops (for
 * example `1`) when direct access to the app is blocked and the proxy sets
 * X-Forwarded-For. Never enable it when clients can reach the app directly.
 */
function configureTrustProxy(app: NestExpressApplication): void {
  const raw = process.env.TRUST_PROXY?.trim();
  if (!raw || raw === '0' || raw.toLowerCase() === 'false') return;

  if (raw.toLowerCase() === 'true') {
    app.set('trust proxy', 1);
    return;
  }

  if (/^\d+$/.test(raw)) {
    app.set('trust proxy', Number(raw));
    return;
  }

  app.set('trust proxy', raw);
}

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  configureTrustProxy(app);
  app.setGlobalPrefix('api', { exclude: ['/'] });

  app.enableCors({
    origin: process.env.CORS_ORIGIN || '*',
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );

  const config = new DocumentBuilder()
    .setTitle('PULSE API')
    .setDescription('Backend API proxy for PULSE — Academic Portal Integration')
    .setVersion('1.0.0')
    .addBearerAuth()
    .addServer(`http://localhost:${process.env.PORT || 3000}`, 'Local development')
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('docs', app, document);

  const port = process.env.PORT || 3000;
  await app.listen(port);
  console.log(`PULSE API running on http://localhost:${port}`);
  console.log(`Swagger docs at http://localhost:${port}/docs`);
}

bootstrap();
