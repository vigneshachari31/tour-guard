import { useEffect, useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import {
  LayoutDashboard,
  Siren,
  Route,
  ShieldAlert,
  Activity,
  Users,
  UserCheck,
  LogOut,
  Menu,
  Bell,
  Calendar,
} from "lucide-react";
import { useAuth } from "../auth";
import logoUrl from "../assets/tour_guard_logo.png";

const links = [
  ["", "Overview", LayoutDashboard],
  ["incidents", "SOS & Rescue", Siren],
  ["trips", "Trip Monitoring", Route],
  ["hazards", "Hazard Zones", ShieldAlert],
  ["reported-incidents", "Reported Incidents", Activity],
  ["risk", "Risk History", Activity],
  ["responders", "Responders", Users],
  ["users", "Tourist Accounts", UserCheck],
] as const;

const titles: Record<string, { title: string; subtitle: string }> = {
  "": {
    title: "Overview",
    subtitle: "Real-time summary of tourist safety and rescue operations",
  },
  incidents: {
    title: "SOS Incident Management",
    subtitle: "View and manage active tourist emergency incidents",
  },
  trips: {
    title: "Active Trip Monitoring",
    subtitle: "Real-time view of ongoing tourist journeys and GPS tracking",
  },
  hazards: {
    title: "Hazard Zone Manager",
    subtitle: "Manage and view geographical safety and risk zones",
  },
  "reported-incidents": {
    title: "Reported Incidents",
    subtitle: "Review and verify tourist reports independently of hazard zones",
  },
  risk: {
    title: "Risk Assessment History",
    subtitle: "Review AI route analysis and historical journey risk scores",
  },
  responders: {
    title: "Responder Management",
    subtitle: "Register and coordinate emergency rescue responders",
  },
  users: {
    title: "Tourist Accounts",
    subtitle: "Search, verify and manage registered tourist profiles",
  },
};

export default function Layout() {
  const { user, logout } = useAuth();
  const [open, setOpen] = useState(false);
  const [health, setHealth] = useState("Checking system");
  const location = useLocation();

  const pathKey = location.pathname.replace(/^\/admin\/?/, "").split("/")[0] || "";
  const headerInfo = titles[pathKey] || {
    title: "Tour Guard Admin",
    subtitle: "Command and rescue operations workspace",
  };

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
      {/* Sidebar matching Image 2 */}
      <aside className={open ? "sidebar open" : "sidebar"}>
        <div className="brand">
          <img src={logoUrl} alt="Tour Guard Logo" className="brand-logo" />
          <div className="brand-text">
            <span>TOUR GUARD</span>
            <small>Admin Panel</small>
          </div>
        </div>

        <nav className="sidebar-nav">
          {links.map(([path, label, Icon]) => (
            <NavLink
              key={label}
              to={`/${path}`}
              end={!path}
              onClick={() => setOpen(false)}
              className={({ isActive }) => (isActive ? "active" : "")}
            >
              <Icon size={19} className="nav-icon" />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>

        <div className="sidebar-foot">
          <button className="sidebar-logout-btn" onClick={logout} title="Sign out">
            <LogOut size={18} />
            <span>Logout</span>
          </button>
        </div>
      </aside>

      {/* Main workspace */}
      <div className="workspace">
        <header className="topbar">
          <div className="topbar-left">
            <button
              className="mobile-menu"
              aria-label="Toggle navigation"
              onClick={() => setOpen(!open)}
            >
              <Menu size={22} />
            </button>
            <div className="page-heading">
              <h1>{headerInfo.title}</h1>
              <p className="page-subtitle">{headerInfo.subtitle}</p>
            </div>
          </div>

          <div className="topbar-right">
            <div className="date-badge">
              <Calendar size={14} />
              <span>Real-time</span>
            </div>

            <div className="system-pill" title={health}>
              <span
                className={
                  health.includes("connected") ? "live-dot" : "warning-dot"
                }
              />
              <span className="system-status-text">
                {health.includes("connected") ? "Connected" : "Disconnected"}
              </span>
            </div>

            <button className="notification-btn" aria-label="Notifications">
              <Bell size={18} />
              <span className="notification-dot" />
            </button>

            <details className="account">
              <summary>
                <div className="account-avatar">
                  {user?.full_name?.charAt(0).toUpperCase() ||
                    user?.email?.charAt(0).toUpperCase() ||
                    "A"}
                </div>
                <div className="account-info">
                  <span className="account-name">
                    {user?.full_name || user?.email?.split("@")[0] || "admin"}
                  </span>
                  <small className="account-role">Administrator</small>
                </div>
              </summary>
              <div className="account-menu">
                <p className="account-email">{user?.email}</p>
                <button onClick={logout} className="signout-btn">
                  <LogOut size={15} /> Sign out
                </button>
              </div>
            </details>
          </div>
        </header>

        <main>
          <Outlet />
        </main>

        <footer>
          TOUR GUARD / Command &amp; Rescue Operations Center · Timestamps reflect verified server and GPS records.
        </footer>
      </div>
    </div>
  );
}
