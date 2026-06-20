import TableSkeleton from './TableSkeleton';

export interface Column {
  key: string;
  label: string;
}

type CellValue = string | number | boolean | null | undefined;

interface Props {
  columns: Column[];
  rows: Record<string, CellValue>[];
  isLoading: boolean;
  caption?: string;
  emptyLabel?: string;
}

export default function DataTable({
  columns,
  rows,
  isLoading,
  caption,
  emptyLabel = 'Aucun résultat.',
}: Props) {
  return (
    <div class="dt-wrap" role="region" aria-label={caption} tabIndex={0}>
      <table class="dt" aria-busy={isLoading ? 'true' : 'false'}>
        {caption && <caption class="dt__caption">{caption}</caption>}
        <thead>
          <tr>
            {columns.map(col => (
              <th key={col.key} scope="col">{col.label}</th>
            ))}
          </tr>
        </thead>
        {isLoading ? (
          <TableSkeleton cols={columns.length} />
        ) : rows.length === 0 ? (
          <tbody>
            <tr>
              <td class="dt__empty" colSpan={columns.length}>{emptyLabel}</td>
            </tr>
          </tbody>
        ) : (
          <tbody>
            {rows.map((row, i) => (
              <tr key={i}>
                {columns.map(col => (
                  <td key={col.key}>{row[col.key] != null ? String(row[col.key]) : '—'}</td>
                ))}
              </tr>
            ))}
          </tbody>
        )}
      </table>
      <style>{`
        .dt-wrap {
          overflow-x: auto;
          border: 1px solid var(--color-border);
          border-radius: var(--radius-md);
        }
        .dt {
          width: 100%;
          border-collapse: collapse;
          font-size: var(--font-size-sm);
          color: var(--color-text);
        }
        .dt__caption {
          caption-side: top;
          text-align: left;
          padding: var(--space-3) var(--space-4);
          font-weight: 600;
          font-size: var(--font-size-sm);
          color: var(--color-muted);
          border-bottom: 1px solid var(--color-border);
        }
        .dt thead { background: var(--color-surface); }
        .dt th {
          padding: var(--space-3) var(--space-4);
          text-align: left;
          font-weight: 600;
          font-size: var(--font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.05em;
          color: var(--color-muted);
          border-bottom: 1px solid var(--color-border);
        }
        .dt td {
          padding: var(--space-3) var(--space-4);
          border-bottom: 1px solid var(--color-border);
          vertical-align: top;
        }
        .dt tbody tr:last-child td { border-bottom: none; }
        .dt tbody tr:hover { background: var(--color-border); }
        .dt__empty {
          color: var(--color-muted);
          text-align: center;
          padding: var(--space-6);
        }
        @keyframes skel-shimmer {
          0%   { background-position: -200% 0; }
          100% { background-position:  200% 0; }
        }
        .skel-cell {
          display: block;
          height: 40px;
          width: 100%;
          background: linear-gradient(
            90deg,
            var(--color-border) 25%,
            var(--color-surface) 50%,
            var(--color-border) 75%
          );
          background-size: 200% 100%;
          animation: skel-shimmer 1.5s ease-in-out infinite;
          border-radius: var(--radius-sm);
        }
      `}</style>
    </div>
  );
}
