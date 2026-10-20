import { useEffect, useState } from "react";
import { NavLink, Outlet } from "react-router-dom";
import {
  ShieldCheck,
  LayoutDashboard,
  Siren,
  Users,
  Map,
  Route,
  Activity,
  FileText,
  LogOut,
  Menu,
} from "lucide-react";
import { useAuth } from "../auth";
const links = [
  ["", "Overview", LayoutDashboard],
  ["incidents", "SOS incidents", Siren],
  ["responders", "Responders", Users],
  ["hazards", "Hazard manager", Map],
  ["trips", "Trip tracker", Route],
  ["risk", "Risk history", Activity],
  ["users", "Tourist accounts", Users],
  ["audit", "Audit logs", FileText],
] as const;
export default function Layout() {
  const { user, logout } = useAuth();
  const [open, setOpen] = useState(false);
  const [health, setHealth] = useState("Checking system");
  useEffect(() => {
    const c = new AbortController();
    async function check() {
      try {
        const r = await fetch("/health/ready", { signal: c.signal });
        if (!c.signal.aborted)
          setHealth(
            r.ok ? "API & database connected" : "Service needs attention",
          );
      } catch {
        if (!c.signal.aborted) setHealth("Connection unavailable");
      }
    }
    void check();
    const id = setInterval(check, 30000);
    return () => {
      c.abort();
      clearInterval(id);
    };
  }, []);
  return (
    <div className="shell">
      <aside className={open ? "sidebar open" : "sidebar"}>
        <div className="brand">
          <ShieldCheck size={34} />
          <div>
            TOUR GUARD<small>RESCUE OPERATIONS</small>
          </div>
        </div>
        <p className="nav-label">COMMAND CENTER</p>
        <nav>
          {links.map(([path, label, Icon]) => (
            <NavLink
              key={label}
              to={`/${path}`}
              end={!path}
              onClick={() => setOpen(false)}
            >
              <Icon size={18} />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-foot">
          <span className="live-dot" /> Operational workspace
          <small>Authorized personnel only</small>
        </div>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <button
            className="mobile-menu"
            aria-label="Toggle navigation"
            onClick={() => setOpen(!open)}
          >
            <Menu />
          </button>
          <span className="system">
            <span
              className={
                health.includes("connected") ? "live-dot" : "warning-dot"
              }
            />
            {health}
          </span>
          <details className="account">
            <summary>
              {user?.full_name || user?.email} <BadgeAdmin />
            </summary>
            <div className="account-menu">
              <p>{user?.email}</p>
              <button onClick={logout}>
                <LogOut size={16} /> Sign out
              </button>
            </div>
          </details>
        </header>
        <main>
          <Outlet />
        </main>
        <footer>
          TOUR GUARD / Rescue coordination · GPS timestamps reflect received
          updates, not guaranteed live positions.
        </footer>
      </div>
    </div>
  );
}
function BadgeAdmin() {
  return <span className="admin-tag">ADMIN</span>;
}
