import type { ComponentChildren } from 'preact';
import { TableSkeleton } from './TableSkeleton.tsx';

interface Props {
  isLoading: boolean;
  cols: number;
  skeletonRows?: number;
  children?: ComponentChildren;
}

export default function DataTable({ isLoading, cols, skeletonRows = 5, children }: Props) {
  return isLoading
    ? <TableSkeleton cols={cols} rows={skeletonRows} />
    : <>{children}</>;
}
