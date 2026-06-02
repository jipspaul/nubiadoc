import { Module } from '@nestjs/common';
import { PrismaModule } from './core/prisma/prisma.module';
import { TenancyModule } from './core/tenancy/tenancy.module';
import { StorageModule } from './core/drivers/storage/storage.module';
import { HealthModule } from './health/health.module';

@Module({
  imports: [PrismaModule, TenancyModule, StorageModule, HealthModule],
})
export class AppModule {}
