interface Props {
  cols: number;
  rows?: number;
}

export function TableSkeleton({ cols, rows = 5 }: Props) {
  return (
    <>
      {Array.from({ length: rows }, (_, i) => (
        <tr key={i} aria-hidden="true">
          {Array.from({ length: cols }, (_, j) => (
            <td key={j}><span class="skel-cell" /></td>
          ))}
        </tr>
      ))}
      <style>{`
        .skel-cell {
          display: block;
          height: 0.875rem;
          border-radius: var(--radius-sm, 4px);
          background: linear-gradient(
            90deg,
            var(--color-border) 25%,
            var(--color-surface) 50%,
            var(--color-border) 75%
          );
          background-size: 200% 100%;
          animation: skel-shimmer 1.4s ease-in-out infinite;
        }
        @keyframes skel-shimmer {
          0%   { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }
      `}</style>
    </>
  );
}
