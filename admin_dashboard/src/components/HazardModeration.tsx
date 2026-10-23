import { useState } from "react";
import { api } from "../api";
import { useResource, date } from "../hooks";
import { Table, Notice, Badge } from "./UI";
import RescueMap from "./RescueMap";

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
    <h2>Reported Incidents</h2>
    <p>Tourist-reported locations, not admin hazard zones. Only verified reports appear on tourist maps and influence route risk.</p>
    <label>Report status <select value={status} onChange={e => setStatus(e.target.value)}>
      <option value="pending">Pending</option><option value="verified">Verified</option>
      <option value="rejected">Rejected</option><option value="">All reports</option>
    </select></label>
    <Notice error={error || reports.error}/>
    <p>Circles show incidents matching the selected status filter.</p>
    <RescueMap hazards={{type: "FeatureCollection", features: (reports.data ?? []).map(r => ({
      type: "Feature" as const,
      geometry: {type: "Point" as const, coordinates: [r.longitude, r.latitude]},
      properties: {id: -r.id, name: `Incident #${r.id}: ${r.description || r.hazard_type} (${r.status})`,
        hazard_type: r.hazard_type, severity: r.severity, source: "Tourist incident report",
        is_active: r.status === "verified", valid_from: null, valid_until: null, updated_at: r.created_at},
    }))}} />
    <Table rows={reports.data ?? []} loading={reports.loading} columns={[
      {title: "Incident type", render: r => r.hazard_type},
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
