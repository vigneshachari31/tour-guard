import { useState } from "react";
import { api } from "../api";
import { useResource, date, downloadCsv } from "../hooks";
import type { Page, Audit } from "../types";
import { Heading, Notice, Table, Pager } from "../components/UI";
export default function AuditLogs() {
  const [offset, setOffset] = useState(0);
  const data = useResource<Page<Audit>>(`/audit-logs?offset=${offset}`, 30000);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function exportCsv() {
    setBusy(true);
    setError("");
    try {
      const rows: Audit[] = [];
      let total = 0;
      do {
        const p = await api<Page<Audit>>(
          `/audit-logs?limit=100&offset=${rows.length}`,
        );
        total = p.total;
        rows.push(...p.items);
        if (!p.items.length) break;
      } while (rows.length < total);
      downloadCsv("tour-guard-audit.csv", [
        ["ID", "Admin", "Action", "Entity", "Target", "Details", "Time"],
        ...rows.map((r) => [
          r.id,
          r.admin_email,
          r.action,
          r.resource_type,
          r.resource_id,
          r.details,
          r.created_at,
        ]),
      ]);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Heading eyebrow="ACCOUNTABILITY" title="Administrative audit trail">
        <button onClick={exportCsv} disabled={busy}>
          {busy ? "Exporting…" : "Export CSV"}
        </button>
      </Heading>
      <Notice error={error || data.error} />
      <section className="panel">
        <Table
          loading={data.loading && !data.data}
          rows={data.data?.items ?? []}
          columns={[
            { title: "Time", render: (r) => date(r.created_at) },
            { title: "Administrator", render: (r) => r.admin_email },
            { title: "Action", render: (r) => r.action },
            {
              title: "Target",
              render: (r) => `${r.resource_type} ${r.resource_id ?? ""}`,
            },
            { title: "Details", render: (r) => r.details || "—" },
          ]}
        />
        <Pager
          total={data.data?.total ?? 0}
          offset={offset}
          setOffset={setOffset}
        />
      </section>
    </>
  );
}
