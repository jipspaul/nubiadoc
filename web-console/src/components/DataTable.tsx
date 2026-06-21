import type { FunctionComponent, ComponentChildren } from 'preact';
import TableSkeleton from './TableSkeleton';

interface Props {
  isLoading: boolean;
  columns: string[];
  caption?: string;
  children?: ComponentChildren;
}

const DataTable: FunctionComponent<Props> = ({ isLoading, columns, caption, children }) => (
  <div
    class="dt-wrap"
    role="region"
    aria-label={caption}
    aria-busy={isLoading}
  >
    <table class="dt-table">
      {caption && <caption class="dt-caption">{caption}</caption>}
      <thead>
        <tr>
          {columns.map((col) => (
            <th key={col} scope="col">{col}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {isLoading ? (
          <TableSkeleton cols={columns.length} />
        ) : (
          children
        )}
      </tbody>
    </table>
    <style>{`
      .dt-wrap { overflow-x: auto; border: 1px solid var(--color-border); border-radius: var(--radius-md); }
      .dt-table { width: 100%; border-collapse: collapse; font-size: var(--font-size-sm); color: var(--color-text); }
      .dt-caption { caption-side: top; text-align: left; padding: var(--space-3) var(--space-4); font-weight: 600; font-size: var(--font-size-sm); color: var(--color-muted); border-bottom: 1px solid var(--color-border); }
      .dt-table thead { background: var(--color-surface); }
      .dt-table th { padding: var(--space-3) var(--space-4); text-align: left; font-weight: 600; font-size: var(--font-size-xs); text-transform: uppercase; letter-spacing: .05em; color: var(--color-muted); border-bottom: 1px solid var(--color-border); }
      .dt-table td { padding: var(--space-3) var(--space-4); border-bottom: 1px solid var(--color-border); vertical-align: top; }
      .dt-table tbody tr:last-child td { border-bottom: none; }
      .dt-table tbody tr:hover { background: var(--color-border); }
    `}</style>
  </div>
);

export default DataTable;
