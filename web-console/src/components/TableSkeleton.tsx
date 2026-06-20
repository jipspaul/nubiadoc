interface Props {
  cols: number;
}

export default function TableSkeleton({ cols }: Props) {
  return (
    <tbody aria-label="Chargement en cours">
      {Array.from({ length: 5 }, (_, i) => (
        <tr key={i} aria-hidden="true">
          {Array.from({ length: cols }, (_, j) => (
            <td key={j}><span class="skel-cell" /></td>
          ))}
        </tr>
      ))}
    </tbody>
  );
}
