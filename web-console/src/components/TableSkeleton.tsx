interface Props {
  cols: number;
  rows?: number;
}

export default function TableSkeleton({ cols, rows = 5 }: Props) {
  return (
    <tbody aria-label="Chargement en cours">
      {Array.from({ length: rows }, (_, i) => (
        <tr key={i} aria-hidden="true">
          {Array.from({ length: cols }, (_, j) => (
            <td key={j}><span class="skel-cell" /></td>
          ))}
        </tr>
      ))}
    </tbody>
  );
}
