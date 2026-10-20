import { useState } from "react";
import { useResource, date } from "../hooks";
import type { Page, Trip, Hazards } from "../types";
import { Badge, Heading, Notice, Table, Pager } from "../components/UI";
import RescueMap from "../components/RescueMap";
export default function Trips() {
  const [offset, setOffset] = useState(0);
  const [status, setStatus] = useState("");
  const [selected, setSelected] = useState<number>();
  const data = useResource<Page<Trip>>(
    `/trips?offset=${offset}${status ? "&status=" + status : ""}`,
    15000,
  );
  const hazards = useResource<Hazards>("/hazards", 30000);
  const trip = data.data?.items.find((t) => t.id === selected);
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
        </select>
      </Heading>
      <Notice error={data.error || hazards.error} />
      {trip && (
        <>
          <RescueMap trip={trip} hazards={hazards.data} />
          <p className="map-caption">
            {trip.source_name} → {trip.destination_name} · GPS updates older
            than 15 minutes are stale.
          </p>
        </>
      )}
      <section className="panel">
        <Table
          loading={data.loading && !data.data}
          rows={data.data?.items ?? []}
          columns={[
            {
              title: "Trip / tourist",
              render: (t) => (
                <>
                  #{t.id}
                  <small>{t.tourist_id}</small>
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
            { title: "Status", render: (t) => <Badge>{t.status}</Badge> },
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
        Updates every 15 seconds. A planned origin is never treated as the
        tourist’s live GPS position.
      </p>
    </>
  );
}
