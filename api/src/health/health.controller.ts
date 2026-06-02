import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { PrismaService } from '../core/prisma/prisma.service';

@Controller('health')
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async check(): Promise<{ status: string; db: string }> {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch {
      throw new ServiceUnavailableException({ error: 'db_unavailable' });
    }
    return { status: 'ok', db: 'up' };
  }
}
