import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Cœur du multi-tenant. Toute opération sur des données tenant DOIT passer ici.
 *
 * withTenant ouvre une transaction interactive et positionne
 * `app.current_cabinet_id` via set_config(..., is_local=true) : la valeur ne
 * vit que le temps de la transaction (compatible pooler en mode transaction).
 * Les policies RLS lisent current_setting('app.current_cabinet_id', true) ;
 * si le contexte est absent => NULL => 0 ligne (fail-closed).
 *
 * Le cabinetId provient TOUJOURS du JWT, jamais du corps de requête (cf. docs/04 §7).
 */
@Injectable()
export class TenancyService {
  constructor(private readonly prisma: PrismaService) {}

  async withTenant<T>(
    cabinetId: string,
    fn: (tx: Prisma.TransactionClient) => Promise<T>,
  ): Promise<T> {
    if (!UUID_RE.test(cabinetId)) {
      throw new Error('TenancyService.withTenant: cabinetId invalide (UUID attendu)');
    }

    return this.prisma.$transaction(async (tx) => {
      // is_local = true -> portée transaction. Paramétré -> pas d'injection.
      await tx.$executeRaw`SELECT set_config('app.current_cabinet_id', ${cabinetId}, true)`;
      return fn(tx);
    });
  }
}
