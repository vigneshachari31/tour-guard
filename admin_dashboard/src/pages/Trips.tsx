import { useMemo, useState } from "react";
import { useResource, date } from "../hooks";
import type { Page, Trip, Hazards } from "../types";
import { Badge, Heading, Notice, Table, Pager } from "../components/UI";
import RescueMap from "../components/RescueMap";
import { useTripStream } from "../useTripStream";
export default function Trips() {
  const live = useTripStream();
  const [offset, setOffset] = useState(0);
  const [status, setStatus] = useState("");
  const [selected, setSelected] = useState<number>();
  const data = useResource<Page<Trip>>(
    `/trips?offset=${offset}${status ? "&status=" + status : ""}`,
    15000,
  );
  const hazards = useResource<Hazards>("/hazards", 30000);
  const rows = useMemo(() => {
    const merged = new Map((data.data?.items ?? []).map((t) => [t.id, t]));
    Object.values(live.trips).forEach((t) => {
      if (offset === 0 || merged.has(t.id)) merged.set(t.id, t);
    });
    return [...merged.values()].filter((t) => !status || t.status === status || (status === "active" && t.status === "completed" && !!live.trips[t.id]))
      .sort((a, b) => b.id - a.id);
  }, [data.data, live.trips, offset, status]);
  const trip = rows.find((t) => t.id === selected);
  return (
    <>
      <Heading eyebrow="JOURNEY MONITORING" title="Trip tracker">
        <select
          aria-label="Trip status"
          value={status}
          onChange={(e) => {
            setStatus(e.target.value);
            setOffset(0);
            setSelected(undefined);
          }}
        >
          <option value="">All trips</option>
          <option value="active">Active</option>
          <option value="completed">Completed</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </Heading>
      <Notice error={data.error || hazards.error} />
      <p role="status">{live.connected ? "Live tracking connected" : "Reconnecting live tracking; polling remains available"}</p>
      {live.notice && <p role="status" className="fresh">{live.notice}</p>}
      {trip && (
        <>
          <RescueMap trip={trip} hazards={hazards.data} />
          <section className="panel" aria-label="Hazard entry history">
            <h2>Recent hazard entries</h2>
            {(trip.recent_hazard_alerts ?? []).map((alert, index) => (
              <p key={`${alert.hazard_id}-${alert.detected_at}-${index}`}>
                {alert.name} · {alert.hazard_type} · Severity {alert.severity}/5 · {date(alert.detected_at)}
              </p>
            ))}
            {!trip.recent_hazard_alerts?.length && <p>No hazard entries recorded.</p>}
          </section>
          <p className="map-caption">
            {trip.source_name} → {trip.destination_name} · GPS updates older
            than 15 minutes are stale.
          </p>
        </>
      )}
      <section className="panel">
        <Table
          loading={data.loading && !data.data}
          rows={rows}
          onRowClick={(t) => setSelected(t.id)}
          columns={[
            {
              title: "Trip / tourist",
              render: (t) => (
                <>
                  #{t.id}
                  <small>{t.tourist_name || t.tourist_id}</small>
                </>
              ),
            },
            {
              title: "Journey",
              render: (t) => (
                <>
                  {t.source_name}
                  <small>→ {t.destination_name}</small>
                </>
              ),
            },
            { title: "Remaining (direct)", render: (t) => t.distance_remaining == null ? "Awaiting GPS" : `${(t.distance_remaining / 1000).toFixed(2)} km` },
            { title: "Status", render: (t) => <Badge>{t.lifecycle_status || t.status}</Badge> },
            { title: "Last GPS hazard check", render: (t) => (
              <>{(t.current_hazards ?? []).map((h) => (
                <small key={h.hazard_id}>{h.name} · {h.hazard_type} · {h.severity}/5</small>
              ))}{!t.current_hazards?.length && "No zones reported"}</>
            ) },
            {
              title: "Risk",
              render: (t) => <Badge>{t.risk_level || "Not assessed"}</Badge>,
            },
            {
              title: "Last GPS update",
              render: (t) => (
                <>
                  {date(t.last_location_updated_at)}
                  <small className={t.stale_location ? "stale" : "fresh"}>
                    {t.stale_location
                      ? "Stale / not received"
                      : "Recent GPS update"}
                  </small>
                </>
              ),
            },
            {
              title: "Map",
              render: (t) => (
                <button onClick={() => setSelected(t.id)}>View route</button>
              ),
            },
          ]}
        />
        <Pager
          total={data.data?.total ?? 0}
          offset={offset}
          setOffset={setOffset}
        />
      </section>
      <p className="muted">
        Live updates arrive automatically; a 15-second refresh provides a fallback. A planned origin is never treated as the
        tourist’s live GPS position.
      </p>
    </>
  );
}
