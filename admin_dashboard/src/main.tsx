import { lazy, Suspense } from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider } from "./auth";
import ProtectedRoute from "./components/ProtectedRoute";
import Layout from "./components/Layout";
const Login = lazy(() => import("./pages/Login"));
const Dashboard = lazy(() => import("./pages/Dashboard"));
const Incidents = lazy(() => import("./pages/Incidents"));
const IncidentDetails = lazy(() => import("./pages/IncidentDetails"));
const Responders = lazy(() => import("./pages/Responders"));
const Hazards = lazy(() => import("./pages/Hazards"));
const Trips = lazy(() => import("./pages/Trips"));
const RiskHistory = lazy(() => import("./pages/RiskHistory"));
const Users = lazy(() => import("./pages/Users"));
import "./style.css";
ReactDOM.createRoot(document.getElementById("root")!).render(
  <BrowserRouter basename="/admin">
    <AuthProvider>
      <Suspense fallback={<p className="panel">Loading workspace...</p>}>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route element={<ProtectedRoute />}>
            <Route element={<Layout />}>
              <Route index element={<Dashboard />} />
              <Route path="incidents" element={<Incidents />} />
              <Route path="incidents/:id" element={<IncidentDetails />} />
              <Route path="responders" element={<Responders />} />
              <Route path="hazards" element={<Hazards />} />
              <Route path="trips" element={<Trips />} />
              <Route path="risk" element={<RiskHistory />} />
              <Route path="users" element={<Users />} />
            </Route>
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </AuthProvider>
  </BrowserRouter>,
);
