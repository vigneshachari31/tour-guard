import { useEffect, useState } from "react";
import { trackingToken } from "./api";
import type { Trip } from "./types";

export function useTripStream() {
  const [trips, setTrips] = useState<Record<number, Trip>>({});
  const [connected, setConnected] = useState(false);
  const [notice, setNotice] = useState("");
  useEffect(() => {
    let stopped = false;
    let socket: WebSocket | undefined;
    let timer: ReturnType<typeof setTimeout>;
    let attempt = 0;
    function connect() {
      const token = trackingToken();
      if (stopped || !token) return;
      socket = new WebSocket(`${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws/admin/active-trips`);
      socket.onopen = () => socket?.send(JSON.stringify({ token }));
      socket.onmessage = ({ data }) => {
        if (stopped) return;
        try {
          const event = JSON.parse(data);
          if (event.event === "SNAPSHOT") {
            setTrips(Object.fromEntries(event.items.map((t: Trip) => [t.id, t])));
            setConnected(true);
            attempt = 0;
          } else if (event.trip) {
            setTrips((previous) => ({ ...previous, [event.trip.id]: event.trip }));
            if (event.event === "TRIP_COMPLETED") setNotice(`Trip for ${event.trip.tourist_name || event.trip.tourist_id} has been completed successfully.`);
          }
        } catch { /* A reconnect snapshot repairs incomplete messages. */ }
      };
      socket.onclose = (event) => {
        if (stopped) return;
        setConnected(false);
        if (event.code !== 1008) timer = setTimeout(connect, Math.min(15000, 1000 * 2 ** attempt++));
      };
      socket.onerror = () => socket?.close();
    }
    connect();
    return () => { stopped = true; clearTimeout(timer); socket?.close(); };
  }, []);
  return { trips, connected, notice };
}
