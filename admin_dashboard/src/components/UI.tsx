import type { ReactNode } from "react";
export function Badge({ children }: { children: ReactNode }) {
  return (
    <span
      className={`badge badge-${String(children).toLowerCase().replaceAll(" ", "-")}`}
    >
      {children ?? "Unassessed"}
    </span>
  );
}
export function Notice({ error }: { error?: string }) {
  return error ? (
    <div role="alert" className="notice">
      {error}
    </div>
  ) : null;
}
export function Heading({
  eyebrow,
  title,
  children,
}: {
  eyebrow: string;
  title: string;
  children?: ReactNode;
}) {
  return (
    <div className="heading">
      <div>
        <p className="eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
      </div>
      {children}
    </div>
  );
}
export function Table<T extends { id: number }>({
  rows,
  columns,
  loading = false,
}: {
  rows: T[];
  loading?: boolean;
  columns: { title: string; render: (row: T) => ReactNode }[];
}) {
  return (
    <div className="table-wrap">
      <table aria-busy={loading}>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.title}>{c.title}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              {columns.map((c) => (
                <td key={c.title}>{c.render(row)}</td>
              ))}
            </tr>
          ))}
          {loading && (
            <tr>
              <td colSpan={columns.length} className="table-loading-cell">
                <div className="table-loader-box">
                  <div className="spinner-blue" />
                  <span>Loading records...</span>
                </div>
              </td>
            </tr>
          )}
          {!loading && rows.length === 0 && (
            <tr>
              <td colSpan={columns.length} className="empty">
                No records found.
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
export function Pager({
  total,
  offset,
  setOffset,
}: {
  total: number;
  offset: number;
  setOffset: (n: number) => void;
}) {
  return (
    <div className="pager">
      <span>
        {total} records · Page {Math.floor(offset / 25) + 1}
      </span>
      <button
        disabled={offset === 0}
        onClick={() => setOffset(Math.max(0, offset - 25))}
      >
        Previous
      </button>
      <button
        disabled={offset + 25 >= total}
        onClick={() => setOffset(offset + 25)}
      >
        Next
      </button>
    </div>
  );
}
