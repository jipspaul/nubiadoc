import { useState, useEffect } from 'preact/hooks';
import DataTable from './kit/DataTable.tsx';
import { proPatients } from '../lib/endpoints.ts';
import type { CabinetPatient } from '../lib/endpoints.ts';

interface Props {
  variant: 'practitioner' | 'secretary';
}

const HEADERS: Record<string, string[]> = {
  practitioner: ['Nom', 'Prénom', 'Date de naissance', 'Dernière visite', 'Actions'],
  secretary:    ['Nom', 'Prénom', 'Téléphone'],
};

export default function CabinetPatientsTable({ variant }: Props) {
  const [loading, setLoading] = useState(true);
  const [patients, setPatients] = useState<CabinetPatient[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const loginUrl = `/auth/login?next=${variant === 'practitioner' ? '/praticien/patients' : '/secretary/patients'}`;
    proPatients.list()
      .then(({ status, data }) => {
        if (status === 401) { window.location.href = loginUrl; return; }
        if (status === 403) { setError('Accès refusé (403).'); setLoading(false); return; }
        if (status !== 200) { setError(`Erreur serveur (HTTP ${status}).`); setLoading(false); return; }
        setPatients(data ?? []);
        setLoading(false);
      })
      .catch(err => {
        setError(`Erreur réseau : ${err instanceof Error ? err.message : String(err)}`);
        setLoading(false);
      });
  }, []);

  const headers = HEADERS[variant];
  const cols = headers.length;

  return (
    <>
      {error && <p role="status" class="cpt-error">{error}</p>}
      <table class="cpt-table" aria-label="Patients du cabinet">
        <thead>
          <tr>{headers.map(h => <th key={h} scope="col">{h}</th>)}</tr>
        </thead>
        <tbody>
          <DataTable isLoading={loading} cols={cols}>
            {patients.length === 0
              ? <tr><td colSpan={cols} class="cpt-empty">Aucun patient enregistré.</td></tr>
              : patients.map(p => (
                  <tr key={p.id}>
                    <td>{p.last_name ?? '—'}</td>
                    <td>{p.first_name ?? '—'}</td>
                    {variant === 'secretary'
                      ? <td>{(p as unknown as Record<string, unknown>)['phone'] as string ?? '—'}</td>
                      : <>
                          <td>{(p.birth_date ?? p.date_of_birth)
                            ? new Date((p.birth_date ?? p.date_of_birth) as string).toLocaleDateString('fr-FR')
                            : '—'}
                          </td>
                          <td>—</td>
                          <td><a class="cpt-link" href={`/praticien/patients/${p.id}`}>Dossier</a></td>
                        </>
                    }
                  </tr>
                ))
            }
          </DataTable>
        </tbody>
      </table>
      <style>{`
        .cpt-table { width: 100%; border-collapse: collapse; font-size: var(--font-size-sm); }
        .cpt-table th, .cpt-table td { padding: var(--space-2) var(--space-3); text-align: left; border-bottom: 1px solid var(--color-border); }
        .cpt-table th { font-weight: 600; color: var(--color-muted); background: var(--color-surface); }
        .cpt-table tbody tr:last-child td { border-bottom: none; }
        .cpt-table tbody tr:hover td { background: var(--color-surface); }
        .cpt-error { color: var(--color-error-fg, #dc2626); font-size: var(--font-size-sm); margin-bottom: var(--space-3); }
        .cpt-empty { color: var(--color-muted); padding: var(--space-4) 0; }
        .cpt-link { color: var(--color-accent); text-decoration: none; font-weight: 500; }
        .cpt-link:hover { text-decoration: underline; }
      `}</style>
    </>
  );
}
