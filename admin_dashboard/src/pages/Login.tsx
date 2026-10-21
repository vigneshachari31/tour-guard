import { useState } from "react";
import type { FormEvent } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import {
  Mail,
  Lock,
  Eye,
  EyeOff,
  ArrowRight,
  Compass,
  ShieldAlert,
  Zap,
  ShieldCheck,
} from "lucide-react";
import { useAuth } from "../auth";
import { Notice } from "../components/UI";
import logoUrl from "../assets/tour_guard_logo.png";

export default function Login() {
  const { user, login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
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
      {/* Left Hero Story Panel */}
      <section className="login-story">
        <div className="login-story-brand">
          {/* Official Tour Guard Logo - 250px just like in Flutter */}
          <img
            src={logoUrl}
            alt="Tour Guard - Safer Journeys. Brighter Tomorrows."
            className="login-logo-hero"
          />

          <div className="login-accent-bar" />

          <p className="login-brand-desc">
            AI-Powered Travel Risk Prediction
            <br />
            &amp; Smart Rescue System
          </p>
        </div>

        <div className="login-features">
          <div className="login-feature-item">
            <span className="feature-icon-box">
              <Compass size={24} />
            </span>
            <div>
              <strong>Monitor journeys</strong>
              <small>Live GPS tracking &amp; trip route verification</small>
            </div>
          </div>
          <div className="login-feature-item">
            <span className="feature-icon-box">
              <ShieldAlert size={24} />
            </span>
            <div>
              <strong>Detect risks</strong>
              <small>Real-time terrain, weather &amp; hazard zone alerts</small>
            </div>
          </div>
          <div className="login-feature-item">
            <span className="feature-icon-box">
              <Zap size={24} />
            </span>
            <div>
              <strong>Faster rescue coordination</strong>
              <small>Instant SOS beacon triage &amp; responder dispatch</small>
            </div>
          </div>
        </div>

        <div className="login-story-foot">
          <small>COMMAND &amp; RESCUE OPERATIONS CENTER</small>
        </div>
      </section>

      {/* Right Login Form Panel */}
      <section className="login-form">
        <div className="login-card">
          <div className="login-card-header">
            <img
              src={logoUrl}
              alt="Tour Guard"
              className="login-card-logo"
            />
            <h2>Welcome back</h2>
            <p className="muted">Sign in to your admin account</p>
          </div>

          <Notice error={error} />

          <form onSubmit={submit}>
            <div className="input-group">
              <label htmlFor="email">Email Address</label>
              <div className="input-field-wrap">
                <Mail size={20} className="input-prefix-icon" />
                <input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="admin@gmail.com"
                  required
                  autoComplete="username"
                />
              </div>
            </div>

            <div className="input-group">
              <label htmlFor="password">Password</label>
              <div className="input-field-wrap">
                <Lock size={20} className="input-prefix-icon" />
                <input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Enter your password"
                  required
                  autoComplete="current-password"
                  maxLength={128}
                />
                <button
                  type="button"
                  className="input-suffix-btn"
                  onClick={() => setShowPassword(!showPassword)}
                  aria-label={showPassword ? "Hide password" : "Show password"}
                >
                  {showPassword ? <EyeOff size={20} /> : <Eye size={20} />}
                </button>
              </div>
            </div>

            <button type="submit" className="primary login-submit-btn" disabled={busy}>
              <span>{busy ? "Signing in…" : "Sign in"}</span>
              <ArrowRight size={20} />
            </button>

            <div className="login-security-tag">
              <ShieldCheck size={18} />
              <span>Authorized personnel only</span>
            </div>
          </form>
        </div>
      </section>
    </div>
  );
}
