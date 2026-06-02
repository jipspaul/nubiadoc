import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

/**
 * Client Prisma partagé. Ne PAS l'utiliser directement pour lire/écrire
 * des données tenant : passer par TenancyService.withTenant() afin que
 * la RLS (app.current_cabinet_id) soit positionnée dans la transaction.
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
