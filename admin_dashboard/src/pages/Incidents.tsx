import { useState } from "react";
import { Link } from "react-router-dom";
import { useResource, date } from "../hooks";
import type { Page, Incident, Hazards } from "../types";
import { Badge, Heading, Notice, Table, Pager } from "../components/UI";
import RescueMap from "../components/RescueMap";
export default function Incidents() {
  const [status, setStatus] = useState("");
  const [offset, setOffset] = useState(0);
  const data = useResource<Page<Incident>>(
    `/incidents?limit=25&offset=${offset}${status ? "&status=" + status : ""}`,
    15000,
  );
  const hazards = useResource<Hazards>("/hazards", 30000);
  return (
    <>
      <Heading eyebrow="RESPONSE COORDINATION" title="SOS rescue desk">
        <select
          aria-label="Filter incident status"
          value={status}
          onChange={(e) => {
            setStatus(e.target.value);
            setOffset(0);
          }}
        >
          <option value="">All statuses</option>
          {["OPEN", "IN_PROGRESS", "RESOLVED", "CANCELLED"].map((s) => (
            <option key={s}>{s}</option>
          ))}
        </select>
      </Heading>
      <Notice error={data.error || hazards.error} />
      <RescueMap
        incidents={data.data?.items.filter((i) =>
          ["OPEN", "IN_PROGRESS"].includes(i.status),
        )}
        hazards={hazards.data}
      />
      <p className="map-caption">
        Red: open/in-progress incidents on this page · Amber: active hazards ·
        Map uses reported SOS coordinates.
      </p>
      <section className="panel">
        <Table
          loading={data.loading && !data.data}
          rows={data.data?.items ?? []}
          columns={[
            {
              title: "Incident",
              render: (i) => <Link to={`/incidents/${i.id}`}>SOS #{i.id}</Link>,
            },
            {
              title: "Tourist / contact",
              render: (i) => (
                <>
                  {i.tourist.full_name || i.tourist_id}
                  <small>{i.tourist.phone || "No phone saved"}</small>
                </>
              ),
            },
            { title: "Status", render: (i) => <Badge>{i.status}</Badge> },
            {
              title: "Coordinates",
              render: (i) =>
                `${i.latitude.toFixed(5)}, ${i.longitude.toFixed(5)}`,
            },
            { title: "Received", render: (i) => date(i.created_at) },
            {
              title: "Responder",
              render: (i) =>
                <Link to={`/incidents/${i.id}`}>
                  {i.responder_id ? `Manage responder #${i.responder_id}` : "Assign responder"}
                </Link>,
            },
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
