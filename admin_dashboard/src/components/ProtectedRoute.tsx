import { Navigate, Outlet } from "react-router-dom";
import { useAuth } from "../auth";
export default function ProtectedRoute() {
  const { user } = useAuth();
  return user?.role === "admin" ? <Outlet /> : <Navigate to="/login" replace />;
}
