import { PrismaService } from '../src/core/prisma/prisma.service';
import { TenancyService } from '../src/core/tenancy/tenancy.service';

/**
 * NUB-T1.2 — Test de sécurité CRITIQUE : isolation multi-tenant par RLS.
 *
 * ⚠️ Doit tourner avec un rôle Postgres NON-superuser et SANS BYPASSRLS
 * (sinon la RLS est contournée et le test passerait à tort).
 * En CI : le workflow crée le rôle `nubia_app` et DATABASE_URL pointe dessus.
 */
describe('RLS — isolation par cabinet (e2e, DB réelle)', () => {
  const prisma = new PrismaService();
  const tenancy = new TenancyService(prisma);

  let cabinetA: string;
  let cabinetB: string;

  beforeAll(async () => {
    await prisma.$connect();
    // cabinet n'a pas de RLS (racine du tenant) : insert direct OK.
    const a = await prisma.cabinet.create({ data: { raisonSociale: 'Cabinet A' } });
    const b = await prisma.cabinet.create({ data: { raisonSociale: 'Cabinet B' } });
    cabinetA = a.id;
    cabinetB = b.id;

    await tenancy.withTenant(cabinetA, (tx) =>
      tx.patient.create({ data: { cabinetId: cabinetA, firstName: 'Alice', lastName: 'A' } }),
    );
    await tenancy.withTenant(cabinetB, (tx) =>
      tx.patient.create({ data: { cabinetId: cabinetB, firstName: 'Bob', lastName: 'B' } }),
    );
  });

  afterAll(async () => {
    await prisma.patient.deleteMany({});
    await prisma.cabinet.deleteMany({ where: { id: { in: [cabinetA, cabinetB] } } });
    await prisma.$disconnect();
  });

  it('le cabinet A ne voit QUE ses patients', async () => {
    const patients = await tenancy.withTenant(cabinetA, (tx) => tx.patient.findMany());
    expect(patients).toHaveLength(1);
    expect(patients[0]?.firstName).toBe('Alice');
  });

  it('le cabinet B ne voit QUE ses patients', async () => {
    const patients = await tenancy.withTenant(cabinetB, (tx) => tx.patient.findMany());
    expect(patients).toHaveLength(1);
    expect(patients[0]?.firstName).toBe('Bob');
  });

  it('sans contexte tenant => 0 ligne (fail-closed)', async () => {
    const patients = await prisma.$transaction((tx) => tx.patient.findMany());
    expect(patients).toHaveLength(0);
  });

  it('écrire un patient avec le cabinet_id d’un AUTRE cabinet est refusé (WITH CHECK)', async () => {
    await expect(
      tenancy.withTenant(cabinetA, (tx) =>
        // contexte A mais on tente d'insérer pour B
        tx.patient.create({ data: { cabinetId: cabinetB, firstName: 'Mallory', lastName: 'M' } }),
      ),
    ).rejects.toThrow();
  });
});
