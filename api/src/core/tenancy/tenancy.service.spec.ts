import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { TenancyService } from './tenancy.service';

describe('TenancyService', () => {
  const VALID = '11111111-1111-4111-8111-111111111111';

  function makeService(): { service: TenancyService; execRaw: jest.Mock; tx: unknown } {
    const execRaw = jest.fn().mockResolvedValue(1);
    const tx = { $executeRaw: execRaw } as unknown as Prisma.TransactionClient;
    const prisma = {
      $transaction: jest.fn((cb: (t: Prisma.TransactionClient) => unknown) => cb(tx)),
    } as unknown as PrismaService;
    return { service: new TenancyService(prisma), execRaw, tx };
  }

  it('rejette un cabinetId non-UUID (fail-fast, anti-injection)', async () => {
    const { service } = makeService();
    await expect(service.withTenant("'; DROP TABLE patient; --", async () => 1)).rejects.toThrow(
      /UUID attendu/,
    );
  });

  it('positionne app.current_cabinet_id puis exécute le callback dans la transaction', async () => {
    const { service, execRaw, tx } = makeService();
    const result = await service.withTenant(VALID, async (t) => {
      expect(t).toBe(tx);
      return 'ok';
    });
    expect(result).toBe('ok');
    // set_config appelé une fois, avec le cabinetId paramétré
    expect(execRaw).toHaveBeenCalledTimes(1);
    const values = execRaw.mock.calls[0].slice(1);
    expect(values).toContain(VALID);
  });

  it('propage l’erreur du callback (rollback transaction)', async () => {
    const { service } = makeService();
    await expect(
      service.withTenant(VALID, async () => {
        throw new Error('boom');
      }),
    ).rejects.toThrow('boom');
  });
});
