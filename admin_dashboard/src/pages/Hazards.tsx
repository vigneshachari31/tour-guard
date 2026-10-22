import { useState } from "react";
import type { FormEvent } from "react";
import { api } from "../api";
import { useResource, date } from "../hooks";
import type { Hazards, HazardProperties } from "../types";
import { Badge, Heading, Notice, Table } from "../components/UI";
import RescueMap from "../components/RescueMap";
type Point = [number, number];
const empty = {
  name: "",
  hazard_type: "flood",
  severity: 3,
  source: "",
  valid_from: "",
  valid_until: "",
};
export default function HazardsPage() {
  const data = useResource<Hazards>("/hazards?include_inactive=true", 15000);
  const [form, setForm] = useState(empty);
  const [editing, setEditing] = useState<number>();
  const [points, setPoints] = useState<Point[]>([]);
  const [drawing, setDrawing] = useState(false);
  const [geometry, setGeometry] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [deleting, setDeleting] = useState<number>();
  const [confirmedDeleted, setConfirmedDeleted] = useState<number[]>([]);
  const [deleteError, setDeleteError] = useState("");
  const [deleteMessage, setDeleteMessage] = useState("");
  const visibleHazards = data.data && {
    ...data.data,
    features: data.data.features.filter((f) => !confirmedDeleted.includes(f.properties.id)),
  };
  function draw(p: Point[]) {
    setPoints(p);
    if (p.length >= 3)
      setGeometry(
        JSON.stringify({
          type: "Polygon",
          coordinates: [[...p, p[0]].map((v) => [v[1], v[0]])],
        }),
      );
    else setGeometry("");
  }
  function reset() {
    setEditing(undefined);
    setForm(empty);
    setPoints([]);
    setGeometry("");
    setDrawing(false);
  }
  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (!geometry) throw new Error("Draw a polygon or enter its GeoJSON");
      const body = {
        ...form,
        severity: Number(form.severity),
        geometry: JSON.parse(geometry),
        valid_from: form.valid_from
          ? new Date(form.valid_from).toISOString()
          : null,
        valid_until: form.valid_until
          ? new Date(form.valid_until).toISOString()
          : null,
      };
      await api(editing ? `/hazards/${editing}` : "/hazards", {
        method: editing ? "PATCH" : "POST",
        body,
      });
      reset();
      data.refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  function edit(h: HazardProperties) {
    const feature = data.data?.features.find((f) => f.properties.id === h.id);
    if (!feature) return;
    setEditing(h.id);
    setForm({
      name: h.name,
      hazard_type: h.hazard_type,
      severity: h.severity,
      source: h.source || "",
      valid_from: local(h.valid_from),
      valid_until: local(h.valid_until),
    });
    setGeometry(JSON.stringify(feature.geometry));
    setPoints(
      feature.geometry.type === "Polygon"
        ? feature.geometry.coordinates[0].slice(0, -1).map((p) => [p[1], p[0]])
        : [],
    );
    setDrawing(false);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }
  async function remove(h: HazardProperties) {
    if (busy) return;
    if (!window.confirm(`Permanently delete "${h.name}"? It will be removed from tourist maps and alerts on their next refresh. This cannot be undone.`)) return;
    setBusy(true);
    setDeleting(h.id);
    setDeleteError("");
    setDeleteMessage("");
    try {
      await api(`/hazards/${h.id}`, { method: "DELETE", signal: AbortSignal.timeout(20000) });
      // Only remove after server confirmation; stale in-flight polls must not restore it.
      setConfirmedDeleted((ids) => [...ids, h.id]);
      setDeleteMessage(`Deleted "${h.name}". Tourist maps and alerts update on their next refresh.`);
      if (editing === h.id) reset();
      data.refresh();
    } catch (e) {
      setDeleteError(`Could not confirm deletion of "${h.name}". ${(e as Error).message} Check that the backend is running, then refresh and retry.`);
    } finally {
      setDeleting(undefined);
      setBusy(false);
    }
  }
  return (
    <>
      <Heading eyebrow="GEOGRAPHIC RISK DATA" title="Hazard zone manager" />
      <Notice error={error || data.error} />
      <div className="map-toolbar">
        <button onClick={() => setDrawing(!drawing)}>
          {drawing ? "Stop drawing" : "Draw / edit polygon"}
        </button>
        <button
          disabled={!points.length}
          onClick={() => draw(points.slice(0, -1))}
        >
          Undo vertex
        </button>
        <button onClick={() => draw([])}>Clear drawing</button>
        <span>Click to add vertices; drag numbered handles to edit.</span>
      </div>
      <RescueMap
        hazards={visibleHazards}
        draw={drawing ? points : undefined}
        onDraw={drawing ? draw : undefined}
      />
      <form className="panel form-grid" onSubmit={save}>
        <h2>{editing ? `Edit hazard #${editing}` : "Create hazard zone"}</h2>
        <label>
          Name
          <input
            required
            value={form.name}
            minLength={3}
            maxLength={200}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
          />
        </label>
        <label>
          Category
          <select
            value={form.hazard_type}
            onChange={(e) => setForm({ ...form, hazard_type: e.target.value })}
          >
            {!["flood", "landslide", "high_tide", "severe_weather"].includes(
              form.hazard_type,
            ) && (
              <option value={form.hazard_type}>
                {form.hazard_type} (choose a supported category)
              </option>
            )}
            {["flood", "landslide", "high_tide", "severe_weather"].map((c) => (
              <option key={c}>{c}</option>
            ))}
          </select>
        </label>
        <label>
          Severity (1–5)
          <input
            type="number"
            min={1}
            max={5}
            required
            value={form.severity}
            onChange={(e) =>
              setForm({ ...form, severity: Number(e.target.value) })
            }
          />
        </label>
        <label>
          Source / provenance
          <input
            required
            minLength={3}
            maxLength={500}
            value={form.source}
            onChange={(e) => setForm({ ...form, source: e.target.value })}
          />
        </label>
        <label>
          Valid from
          <input
            type="datetime-local"
            value={form.valid_from}
            onChange={(e) => setForm({ ...form, valid_from: e.target.value })}
          />
        </label>
        <label>
          Valid until
          <input
            type="datetime-local"
            value={form.valid_until}
            onChange={(e) => setForm({ ...form, valid_until: e.target.value })}
          />
        </label>
        <label className="full-width">
          GeoJSON polygon (longitude, latitude)
          <textarea
            required
            rows={3}
            value={geometry}
            onChange={(e) => {
              setGeometry(e.target.value);
              setDrawing(false);
            }}
          />
        </label>
        <div className="form-actions">
          <button className="primary" disabled={busy}>
            Save hazard
          </button>
          <button type="button" onClick={reset}>
            Reset form
          </button>
        </div>
      </form>
      <section className="panel">
        <Notice error={deleteError} />
        {deleteMessage && <p role="status">{deleteMessage}</p>}
        <Table
          loading={data.loading && !data.data}
          rows={visibleHazards?.features.map((f) => f.properties) ?? []}
          columns={[
            {
              title: "Zone",
              render: (h) => (
                <>
                  {h.name}
                  <small>{h.source}</small>
                </>
              ),
            },
            {
              title: "Category / severity",
              render: (h) => `${h.hazard_type} · ${h.severity}/5`,
            },
            {
              title: "Validity",
              render: (h) => (
                <>
                  {h.valid_from ? date(h.valid_from) : "No start limit"}
                  <small>
                    {h.valid_until ? date(h.valid_until) : "No expiry"}
                  </small>
                </>
              ),
            },
            {
              title: "Activation",
              render: (h) => (
                <Badge>{h.is_active ? "Enabled" : "Disabled"}</Badge>
              ),
            },
            {
              title: "Actions",
              render: (h) => (
                <div className="actions">
                  <button onClick={() => edit(h)}>Edit</button>
                  <button disabled={busy} onClick={() => remove(h)} style={{ color: "#b91c1c" }}>
                    {deleting === h.id ? "Deleting..." : "Delete"}
                  </button>
                </div>
              ),
            },
          ]}
        />
      </section>
    </>
  );
}
function local(value: string | null) {
  if (!value) return "";
  const d = new Date(value);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
}
