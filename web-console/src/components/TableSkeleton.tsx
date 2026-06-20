import type { FunctionComponent } from 'preact';

interface Props {
  cols?: number;
  rows?: number;
}

const TableSkeleton: FunctionComponent<Props> = ({ cols = 4, rows = 5 }) => (
  <>
    <style>{`
      @keyframes skel-pulse { 0%,100%{opacity:1} 50%{opacity:.35} }
      .skel-bar {
        display: block;
        width: 100%;
        height: 40px;
        border-radius: var(--radius-sm, 4px);
        background: var(--color-border, #e2e8f0);
        animation: skel-pulse 1.4s ease-in-out infinite;
      }
    `}</style>
    {Array.from({ length: rows }, (_, i) => (
      <tr key={i} aria-hidden="true">
        {Array.from({ length: cols }, (_, j) => (
          <td key={j} style={{ padding: 'var(--space-3) var(--space-4)', borderBottom: '1px solid var(--color-border)' }}>
            <span class="skel-bar" />
          </td>
        ))}
      </tr>
    ))}
  </>
);

export default TableSkeleton;
