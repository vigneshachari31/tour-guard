import { useState } from "react";
import { api } from "../api";
import { useResource, date } from "../hooks";
import { Table, Notice, Badge } from "./UI";

type Report = {id: number; hazard_type: string; severity: number; description: string | null; latitude: number; longitude: number; status: string; created_at: string};
export default function HazardModeration() {
  const [status, setStatus] = useState("pending");
  const reports = useResource<Report[]>(`/hazards/reports${status ? "?status=" + status : ""}`, 15000);
  const [busy, setBusy] = useState<number>();
  const [error, setError] = useState("");
  async function moderate(id: number, next: string) {
    setBusy(id); setError("");
    try {
      await api(`/hazards/reports/${id}/status`, {method: "PATCH", body: {status: next}});
      reports.refresh();
    } catch (e) {setError((e as Error).message);}
    finally {setBusy(undefined);}
  }
  return <section className="panel">
    <h2>Tourist report moderation</h2>
    <label>Report status <select value={status} onChange={e => setStatus(e.target.value)}>
      <option value="pending">Pending</option><option value="verified">Verified</option>
      <option value="rejected">Rejected</option><option value="">All reports</option>
    </select></label>
    <Notice error={error || reports.error}/>
    <Table rows={reports.data ?? []} loading={reports.loading} columns={[
      {title: "Hazard", render: r => r.hazard_type},
      {title: "Severity", render: r => `${r.severity}/5`},
      {title: "Description", render: r => r.description || "—"},
      {title: "Coordinates", render: r => `${r.latitude.toFixed(6)}, ${r.longitude.toFixed(6)}`},
      {title: "Status", render: r => <Badge>{r.status}</Badge>},
      {title: "Reported", render: r => date(r.created_at)},
      {title: "Actions", render: r => <div className="actions">
        <button disabled={busy !== undefined || r.status === "verified"} onClick={() => moderate(r.id, "verified")}>Verify</button>
        <button disabled={busy !== undefined || r.status === "rejected"} onClick={() => moderate(r.id, "rejected")}>Reject</button>
      </div>},
    ]}/>
  </section>;
}
