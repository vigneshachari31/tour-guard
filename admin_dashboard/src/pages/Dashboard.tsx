import { Link } from "react-router-dom";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  BarChart,
  Bar,
} from "recharts";
import { Users, Route, Siren, ShieldAlert, ArrowUpRight } from "lucide-react";
import { useResource, date } from "../hooks";
import type { Stats, Charts, Page, Incident } from "../types";
import { Badge, Heading, Notice, Table } from "../components/UI";
export default function Dashboard() {
  const stats = useResource<Stats>("/dashboard/stats", 15000);
  const charts = useResource<Charts>("/dashboard/charts", 30000);
  const incidents = useResource<Page<Incident>>("/incidents?limit=5", 15000);
  const metrics = [
    ["Registered users", stats.data?.total_users, Users],
    ["Active trips", stats.data?.active_trips, Route],
    ["Open SOS incidents", stats.data?.open_incidents, Siren],
    ["Active hazard zones", stats.data?.active_hazards, ShieldAlert],
  ] as const;
  return (
    <>
      <Heading eyebrow="SITUATIONAL AWARENESS" title="Operations overview">
        <span className="refresh-label">
          <span className="live-dot" /> Updates every 15s
        </span>
      </Heading>
      <Notice error={stats.error || charts.error || incidents.error} />
      <div className="metrics">
        {metrics.map(([label, value, Icon]) => (
          <section className="metric" key={label}>
            <div className="metric-top">
              <span>{label}</span>
              <Icon size={19} />
            </div>
            <strong>{value ?? "—"}</strong>
            <small>Current database total</small>
          </section>
        ))}
      </div>
      <div className="status-strip">
        <span>
          <b>{stats.data?.in_progress_incidents ?? "—"}</b> incidents in
          progress
        </span>
        <span>
          <b>{stats.data?.resolved_incidents ?? "—"}</b> incidents resolved
        </span>
        <Link to="/incidents">
          Go to rescue desk <ArrowUpRight size={16} />
        </Link>
      </div>
      <div className="chart-grid">
        <section className="panel">
          <h2>Incident activity</h2>
          <p className="muted">Recorded SOS events · last 30 days</p>
          <ResponsiveContainer width="100%" height={230}>
            <AreaChart data={charts.data?.incidents_over_time ?? []}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} />
              <XAxis dataKey="name" tick={{ fontSize: 11 }} />
              <YAxis allowDecimals={false} />
              <Tooltip />
              <Area dataKey="count" stroke="#148579" fill="#d2eeea" />
            </AreaChart>
          </ResponsiveContainer>
          {charts.data?.incidents_over_time.length === 0 && (
            <p className="muted">No incidents in this period.</p>
          )}
        </section>
        <section className="panel">
          <h2>Incident status</h2>
          <p className="muted">All recorded incidents</p>
          <ResponsiveContainer width="100%" height={230}>
            <BarChart data={charts.data?.incident_status ?? []}>
              <XAxis dataKey="name" tick={{ fontSize: 10 }} />
              <YAxis allowDecimals={false} />
              <Tooltip />
              <Bar dataKey="count" fill="#445c75" radius={[5, 5, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </section>
      </div>
      <div className="chart-grid">
        <section className="panel">
          <h2>Risk distribution</h2>
          <ResponsiveContainer width="100%" height={180}>
            <BarChart data={charts.data?.risk_buckets ?? []}>
              <XAxis dataKey="name" />
              <YAxis allowDecimals={false} />
              <Tooltip />
              <Bar dataKey="count" fill="#d8a04b" />
            </BarChart>
          </ResponsiveContainer>
          <small>{charts.data?.risk_bucket_note}</small>
        </section>
        <section className="panel">
          <h2>Active hazard categories</h2>
          <ResponsiveContainer width="100%" height={180}>
            <BarChart data={charts.data?.hazard_categories ?? []}>
              <XAxis dataKey="name" tick={{ fontSize: 10 }} />
              <YAxis allowDecimals={false} />
              <Tooltip />
              <Bar dataKey="count" fill="#148579" />
            </BarChart>
          </ResponsiveContainer>
        </section>
      </div>
      <section className="panel">
        <div className="section-head">
          <h2>Recent emergency feed</h2>
          <Link to="/incidents">View all incidents →</Link>
        </div>
        <Table
          loading={incidents.loading && !incidents.data}
          rows={incidents.data?.items ?? []}
          columns={[
            { title: "Incident", render: (i) => <strong>#{i.id}</strong> },
            {
              title: "Tourist",
              render: (i) => i.tourist.full_name || i.tourist_id,
            },
            { title: "Status", render: (i) => <Badge>{i.status}</Badge> },
            { title: "Received", render: (i) => date(i.created_at) },
            {
              title: "Action",
              render: (i) => (
                <Link to={`/incidents/${i.id}`}>View on map ↗</Link>
              ),
            },
          ]}
        />
      </section>
    </>
  );
}
