import { Link } from "react-router-dom";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  Cell,
  PieChart,
  Pie,
} from "recharts";
import {
  Users,
  Route,
  Siren,
  ShieldAlert,
  ArrowUpRight,
  TrendingUp,
  AlertTriangle,
} from "lucide-react";
import { useResource, date } from "../hooks";
import type { Stats, Charts, Page, Incident } from "../types";
import { Badge, Notice } from "../components/UI";

export default function Dashboard() {
  const stats = useResource<Stats>("/dashboard/stats", 15000);
  const charts = useResource<Charts>("/dashboard/charts", 30000);
  const incidents = useResource<Page<Incident>>("/incidents?limit=6", 15000);

  // Status chart colors
  const STATUS_COLORS: Record<string, string> = {
    open: "#EF4444",
    OPEN: "#EF4444",
    in_progress: "#F59E0B",
    IN_PROGRESS: "#F59E0B",
    resolved: "#10B981",
    RESOLVED: "#10B981",
    cancelled: "#94A3B8",
    CANCELLED: "#94A3B8",
  };

  // Process incident status data for Donut Chart
  const statusData = (charts.data?.incident_status ?? []).map((item) => ({
    name: item.name.replace("_", " ").toUpperCase(),
    rawName: item.name.toLowerCase(),
    value: item.count,
    color: STATUS_COLORS[item.name] || "#3B82F6",
  }));

  const totalIncidentsInChart = statusData.reduce((acc, cur) => acc + cur.value, 0);

  // Risk distribution colors (Low: Green, Medium: Yellow/Amber, High: Red)
  const RISK_COLORS: Record<string, string> = {
    SAFE: "#10B981",
    LOW: "#10B981",
    CAUTION: "#F59E0B",
    MEDIUM: "#F59E0B",
    "HIGH RISK": "#EF4444",
    HIGH: "#EF4444",
  };

  const riskData = (charts.data?.risk_buckets ?? []).map((item) => ({
    name: item.name === "HIGH RISK" ? "High" : item.name === "CAUTION" ? "Medium" : item.name === "SAFE" ? "Low" : item.name,
    count: item.count,
    color: RISK_COLORS[item.name] || "#087CF0",
  }));

  return (
    <div className="overview-container">
      <Notice error={stats.error || charts.error || incidents.error} />

      {/* 4 Metric Cards - Matching Image 2 */}
      <div className="metrics-grid">
        {/* 1. Registered Tourists */}
        <Link to="/users" className="stat-card stat-card-link">
          <div className="stat-card-icon stat-icon-green">
            <Users size={22} />
          </div>
          <div className="stat-card-body">
            <span className="stat-card-label">Registered Tourists</span>
            <strong className="stat-card-value">{stats.data?.total_users ?? "—"}</strong>
            <div className="stat-card-sub text-green">
              <TrendingUp size={13} />
              <span>+2 this week</span>
            </div>
          </div>
        </Link>

        {/* 2. Active Trips */}
        <Link to="/trips" className="stat-card stat-card-link">
          <div className="stat-card-icon stat-icon-blue">
            <Route size={22} />
          </div>
          <div className="stat-card-body">
            <span className="stat-card-label">Active Trips</span>
            <strong className="stat-card-value">{stats.data?.active_trips ?? "—"}</strong>
            <div className="stat-card-sub text-blue">
              <span className="live-dot-pulse" />
              <span>Live monitoring</span>
            </div>
          </div>
        </Link>

        {/* 3. Open SOS Incidents */}
        <Link to="/incidents" className="stat-card stat-card-link">
          <div className="stat-card-icon stat-icon-red">
            <Siren size={22} />
          </div>
          <div className="stat-card-body">
            <span className="stat-card-label">Open SOS Incidents</span>
            <strong className="stat-card-value text-red">{stats.data?.open_incidents ?? "—"}</strong>
            <div className="stat-card-sub text-red">
              <AlertTriangle size={13} />
              <span>{stats.data?.open_incidents ? `${stats.data.open_incidents} urgent` : "All clear"}</span>
            </div>
          </div>
        </Link>

        {/* 4. Active Hazard Zones */}
        <Link to="/hazards" className="stat-card stat-card-link">
          <div className="stat-card-icon stat-icon-amber">
            <ShieldAlert size={22} />
          </div>
          <div className="stat-card-body">
            <span className="stat-card-label">Active Hazard Zones</span>
            <strong className="stat-card-value">{stats.data?.active_hazards ?? "—"}</strong>
            <div className="stat-card-sub text-amber">
              <span>Across the region</span>
            </div>
          </div>
        </Link>
      </div>

      {/* Row 2: Charts and Incident Feed matching Image 2 */}
      <div className="dashboard-trio-grid">
        {/* Card 1: SOS Incident Status Donut Chart */}
        <section className="panel-card">
          <div className="panel-card-head">
            <h3>SOS Incident Status</h3>
            <span className="panel-badge">{totalIncidentsInChart} Total</span>
          </div>

          <div className="donut-chart-container">
            {statusData.length > 0 ? (
              <div className="donut-flex-layout">
                <div className="donut-wrapper">
                  <ResponsiveContainer width={170} height={170}>
                    <PieChart>
                      <Pie
                        data={statusData}
                        dataKey="value"
                        nameKey="name"
                        cx="50%"
                        cy="50%"
                        innerRadius={50}
                        outerRadius={75}
                        paddingAngle={3}
                        stroke="none"
                      >
                        {statusData.map((entry, index) => (
                          <Cell key={`cell-${index}`} fill={entry.color} />
                        ))}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                  <div className="donut-center-label">
                    <strong>{totalIncidentsInChart}</strong>
                    <small>Total</small>
                  </div>
                </div>

                <div className="donut-legend-list">
                  {statusData.map((item) => (
                    <div key={item.name} className="donut-legend-row">
                      <span
                        className="legend-bullet"
                        style={{ backgroundColor: item.color }}
                      />
                      <span className="legend-name">{item.name}</span>
                      <strong className="legend-value">{item.value}</strong>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div className="empty-chart">
                <p className="muted">No incident records to display.</p>
              </div>
            )}
          </div>
        </section>

        {/* Card 2: Risk Distribution Bar Chart */}
        <section className="panel-card">
          <div className="panel-card-head">
            <h3>Risk Distribution</h3>
            <span className="panel-hint">Route assessments</span>
          </div>

          <div className="bar-chart-container">
            {riskData.length > 0 ? (
              <ResponsiveContainer width="100%" height={180}>
                <BarChart data={riskData} margin={{ top: 15, right: 10, left: -25, bottom: 0 }}>
                  <XAxis dataKey="name" tick={{ fontSize: 11, fill: "#64748B" }} axisLine={false} tickLine={false} />
                  <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: "#64748B" }} axisLine={false} tickLine={false} />
                  <Tooltip />
                  <Bar dataKey="count" radius={[6, 6, 0, 0]} maxBarSize={45}>
                    {riskData.map((entry, index) => (
                      <Cell key={`bar-${index}`} fill={entry.color} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="empty-chart">
                <p className="muted">No route risk evaluations yet.</p>
              </div>
            )}
          </div>
        </section>

        {/* Card 3: Recent SOS Incidents */}
        <section className="panel-card">
          <div className="panel-card-head">
            <h3>Recent SOS Incidents</h3>
            <Link to="/incidents" className="panel-link">
              View all <ArrowUpRight size={14} />
            </Link>
          </div>

          <div className="recent-incidents-list">
            {(incidents.data?.items ?? []).slice(0, 5).map((item) => (
              <Link
                key={item.id}
                to={`/incidents/${item.id}`}
                className="recent-incident-row"
              >
                <div className="incident-id-badge">#{item.id}</div>
                <div className="incident-tourist-info">
                  <span className="incident-tourist-name">
                    {item.tourist.full_name || `User #${item.tourist_id}`}
                  </span>
                  <span className="incident-timestamp">{date(item.created_at)}</span>
                </div>
                <div className="incident-status-cell">
                  <Badge>{item.status}</Badge>
                </div>
              </Link>
            ))}

            {(!incidents.data?.items || incidents.data.items.length === 0) && (
              <div className="empty-chart">
                <p className="muted">No active SOS incidents.</p>
              </div>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}
