import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  useRef,
} from "react";
import type { ReactNode } from "react";
import { api, setSession } from "./api";
import type { Admin } from "./types";
type Auth = {
  user: Admin | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
};
const Context = createContext<Auth | null>(null);
export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<Admin | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const logout = useCallback(() => {
    setSession(null);
    setUser(null);
    clearTimeout(timer.current);
  }, []);
  async function login(email: string, password: string) {
    const result = await api<{
      access_token: string;
      expires_in: number;
      user: Admin;
    }>("/auth/login", { method: "POST", body: { email, password } });
    if (result.user.role !== "admin")
      throw new Error("Administrator access required");
    clearTimeout(timer.current);
    setSession(result.access_token, logout);
    setUser(result.user);
    timer.current = setTimeout(logout, result.expires_in * 1000);
  }
  useEffect(
    () => () => {
      clearTimeout(timer.current);
      setSession(null);
    },
    [],
  );
  return (
    <Context.Provider value={{ user, login, logout }}>
      {children}
    </Context.Provider>
  );
}
export function useAuth() {
  const auth = useContext(Context);
  if (!auth) throw new Error("Missing auth provider");
  return auth;
}
