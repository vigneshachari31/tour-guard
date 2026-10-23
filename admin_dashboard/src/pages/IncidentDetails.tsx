import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api } from "../api";
import { useResource, date } from "../hooks";
import type {
  IncidentDetail,
  Page,
  Responder,
  Hazards,
  Status,
} from "../types";
import { Badge, Heading, Notice, Table } from "../components/UI";
import RescueMap from "../components/RescueMap";
export default function IncidentDetails() {
  const { id } = useParams();
  const data = useResource<IncidentDetail>(`/incidents/${id}`, 15000);
  const responders = useResource<Page<Responder>>(
    "/responders?limit=100",
    15000,
  );
  const hazards = useResource<Hazards>("/hazards", 30000);
  const [responder, setResponder] = useState("");
  const [note, setNote] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const incident = data.data;
  async function action(path: string, body: unknown, method = "POST") {
    setBusy(true);
    setError("");
    try {
      await api(path, { method, body });
      setNote("");
      setResponder("");
      data.refresh();
      responders.refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const transitions: Record<Status, Status[]> = {
    OPEN: ["IN_PROGRESS", "CANCELLED"],
    IN_PROGRESS: ["RESOLVED", "CANCELLED"],
    RESOLVED: [],
    CANCELLED: [],
  };
  return (
    <>
      <Link to="/incidents">← All incidents</Link>
      <Heading eyebrow="INCIDENT RESPONSE" title={`SOS incident #${id}`}>
        {incident && <Badge>{incident.status}</Badge>}
      </Heading>
      <Notice
        error={error || data.error || responders.error || hazards.error}
      />
      {incident ? (
        <>
          <div className="detail-grid">
            <section>
              <RescueMap incidents={[{...incident, latitude: incident.sos_location.latitude, longitude: incident.sos_location.longitude}]} hazards={hazards.data} />
              <div className="panel">
                <h3>SOS location</h3>
                <p>{incident.sos_location.stale ? "Location stale — last received position" : "Recent GPS position"} · {date(incident.sos_location.captured_at)}</p>
                <p>Accuracy: {incident.sos_location.accuracy == null ? "Not recorded" : `±${Math.round(incident.sos_location.accuracy)} m`}. Updates require the tourist app to be open.</p>
                <small>Original SOS: {incident.latitude}, {incident.longitude}</small>
              </div>
              <div className="panel">
                <h2>{incident.tourist.full_name || incident.tourist_id}</h2>
                <p>
                  {incident.tourist.email} ·{" "}
                  {incident.tourist.phone || "No phone saved"}
                </p>
                <small>
                  Last received location: {incident.last_location.latitude},{" "}
                  {incident.last_location.longitude} ·{" "}
                  {date(incident.last_location.at)}
                </small>
                <div className="profile-details">
                  {Object.entries(incident.emergency_profile ?? {}).map(
                    ([key, value]) => (
                      <div key={key}>
                        <small>{key.replaceAll("_", " ")}</small>
                        <strong>{value || "Not provided"}</strong>
                      </div>
                    ),
                  )}
                </div>
              </div>
            </section>
            <section className="panel response-panel">
              <h2>Coordinate response</h2>
              <p className="muted">
                Assignments record coordination here; they do not send an
                external dispatch message.
              </p>
              <label>
                Response / resolution note
                <textarea
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  maxLength={2000}
                  rows={4}
                  placeholder="Record the action and outcome"
                />
              </label>
              <label>
                Assign or reassign responder
                {responders.data && !responders.data.items.some((r) => r.status === "available") && (
                  <p>No available responders. <Link to="/responders">Register or update a responder</Link>, then return here to assign them.</p>
                )}
                <select
                  value={responder}
                  onChange={(e) => setResponder(e.target.value)}
                  disabled={busy || transitions[incident.status].length === 0}
                >
                  <option value="">Select an available responder</option>
                  {responders.data?.items
                    .filter((r) => r.status === "available")
                    .map((r) => (
                      <option key={r.id} value={r.id}>
                        {r.name} · {r.role}
                      </option>
                    ))}
                </select>
              </label>
              <button
                disabled={
                  busy ||
                  !responder ||
                  note.trim().length < 3 ||
                  transitions[incident.status].length === 0
                }
                onClick={() =>
                  action(`/incidents/${id}/assign`, {
                    responder_id: Number(responder),
                    note,
                  })
                }
              >
                Assign responder
              </button>
              <p>Choose an available responder and enter an action note (at least 3 characters) to assign them.</p>
              <hr />
              <h3>Update incident status</h3>
              {incident.responder && transitions[incident.status].length > 0 && <div>
                <p>{incident.responder.name} · {incident.responder.phone} · {incident.responder_stage}</p>
                <p>Record progress only after confirming with the responder.</p>
                {({"ASSIGNED": "ACCEPTED", "ACCEPTED": "DEPARTED", "DEPARTED": "ARRIVED"} as Record<string,string>)[incident.responder_stage] && <button
                  disabled={busy || note.trim().length < 3}
                  onClick={() => action(`/incidents/${id}/progress`, {
                    assignment_id: incident.responder!.assignment_id,
                    stage: ({"ASSIGNED": "ACCEPTED", "ACCEPTED": "DEPARTED", "DEPARTED": "ARRIVED"} as Record<string,string>)[incident.responder_stage],
                    note,
                  }, "PATCH")}>
                  Confirm {({"ASSIGNED": "acceptance", "ACCEPTED": "departure", "DEPARTED": "arrival"} as Record<string,string>)[incident.responder_stage]}
                </button>}
              </div>}
              {transitions[incident.status].map((status) => (
                <button
                  key={status}
                  className={status === "CANCELLED" ? "danger" : "primary"}
                  disabled={
                    busy ||
                    note.trim().length < 3 ||
                    (status === "IN_PROGRESS" && !incident.responder_id)
                  }
                  onClick={() =>
                    action(
                      `/incidents/${id}/status`,
                      { status, expected_status: incident.status, note },
                      "PATCH",
                    )
                  }
                >
                  {status === "IN_PROGRESS"
                    ? "Start response"
                    : status === "RESOLVED"
                      ? "Resolve incident"
                      : "Cancel incident"}
                </button>
              ))}
              {transitions[incident.status].length === 0 && (
                <p>This incident is closed. Its history is preserved.</p>
              )}
            </section>
          </div>
          <section className="panel">
            <h2>Status history</h2>
            <Table
              rows={incident.history}
              columns={[
                {
                  title: "Transition",
                  render: (h) => `${h.old_status} → ${h.new_status}`,
                },
                { title: "Note", render: (h) => {
                    if (h.new_status !== "RESPONDER_PROGRESS" || !h.notes) return h.notes;
                    try { const progress = JSON.parse(h.notes); return `${progress.stage}: ${progress.note}`; }
                    catch { return h.notes; }
                }},
                { title: "Time", render: (h) => date(h.created_at) },
              ]}
            />
          </section>
          <section className="panel">
            <h2>Assignment history</h2>
            <Table
              rows={incident.assignments}
              columns={[
                { title: "Responder", render: (a) => `#${a.responder_id}` },
                { title: "Status", render: (a) => a.status },
                { title: "Note", render: (a) => a.notes },
                { title: "Time", render: (a) => date(a.created_at) },
              ]}
            />
          </section>
          <section className="panel">
            <h2>Recent tourist trips</h2>
            <Table
              rows={incident.trips}
              columns={[
                {
                  title: "Route",
                  render: (t) => `${t.source_name} → ${t.destination_name}`,
                },
                { title: "Status", render: (t) => t.status },
                { title: "Risk", render: (t) => <Badge>{t.risk_level}</Badge> },
                { title: "Started", render: (t) => date(t.started_at) },
              ]}
            />
          </section>
        </>
      ) : (
        <div role="status">
          <p>{data.loading ? "Loading incident…" : "Unable to load this incident."}</p>
          {!data.loading && <button onClick={data.refresh}>Retry incident</button>}
        </div>
      )}
    </>
  );
}
