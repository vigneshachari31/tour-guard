import { useState } from "react";
import type { FormEvent } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { ShieldCheck, ArrowRight } from "lucide-react";
import { useAuth } from "../auth";
import { Notice } from "../components/UI";
export default function Login() {
  const { user, login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  if (user) return <Navigate to="/" replace />;
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await login(email, password);
      setPassword("");
      navigate("/");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="login-page">
      <section className="login-story">
        <ShieldCheck size={54} />
        <p className="eyebrow">TOUR GUARD / OPERATIONS</p>
        <h1>
          Every response
          <br />
          starts here.
        </h1>
        <p>
          One workspace for tourist safety, rescue coordination, and geographic
          risk monitoring.
        </p>
        <div className="login-rule" />
        <small>ADMIN & RESCUE MANAGEMENT</small>
      </section>
      <section className="login-form">
        <form onSubmit={submit}>
          <p className="eyebrow">AUTHORIZED ACCESS</p>
          <h2>Welcome back</h2>
          <p className="muted">Sign in with your administrator account.</p>
          <Notice error={error} />
          <label>
            Email address
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="username"
            />
          </label>
          <label>
            Password
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              maxLength={128}
            />
          </label>
          <button className="primary" disabled={busy}>
            {busy ? "Signing in…" : "Enter command center"}
            <ArrowRight size={18} />
          </button>
          <small>
            Session credentials stay in memory. Reloading this page requires
            signing in again.
          </small>
        </form>
      </section>
    </div>
  );
}
