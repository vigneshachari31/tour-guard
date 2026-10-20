import { useEffect } from "react";
import {
  MapContainer,
  TileLayer,
  GeoJSON,
  CircleMarker,
  Popup,
  Polyline,
  Polygon,
  Marker,
  useMap,
  useMapEvents,
} from "react-leaflet";
import L from "leaflet";
import type { Hazards, Incident, Trip } from "../types";
import { Link } from "react-router-dom";
import "leaflet/dist/leaflet.css";
type Point = [number, number];
function Fit({ points }: { points: Point[] }) {
  const map = useMap();
  const key = JSON.stringify(points);
  useEffect(() => {
    const p = JSON.parse(key) as Point[];
    if (p.length)
      map.fitBounds(L.latLngBounds(p), { padding: [35, 35], maxZoom: 14 });
  }, [key, map]);
  return null;
}
function Draw({
  points,
  onChange,
}: {
  points: Point[];
  onChange: (p: Point[]) => void;
}) {
  useMapEvents({
    click: (e) => onChange([...points, [e.latlng.lat, e.latlng.lng]]),
  });
  return (
    <>
      {points.length >= 3 && (
        <Polygon positions={points} pathOptions={{ color: "#087f78" }} />
      )}
      {points.map((point, i) => (
        <Marker
          key={i}
          position={point}
          draggable
          icon={L.divIcon({
            className: "vertex",
            html: String(i + 1),
            iconSize: [22, 22],
          })}
          eventHandlers={{
            dragend: (e) => {
              const p = (e.target as L.Marker).getLatLng();
              onChange(
                points.map((v, index) => (index === i ? [p.lat, p.lng] : v)),
              );
            },
          }}
        />
      ))}
    </>
  );
}
export default function RescueMap({
  incidents = [],
  hazards,
  trip,
  draw,
  onDraw,
}: {
  incidents?: Incident[];
  hazards?: Hazards;
  trip?: Trip;
  draw?: Point[];
  onDraw?: (p: Point[]) => void;
}) {
  const route: Point[] =
    trip?.route_geometry?.coordinates.map((p) => [p[1], p[0]]) ?? [];
  const points: Point[] = route.length
    ? route
    : incidents.map((i) => [i.latitude, i.longitude]);
  const hazardPoints: Point[] = [];
  hazards?.features.forEach((f) => {
    if (f.geometry.type === "Polygon")
      f.geometry.coordinates[0].forEach((p) => hazardPoints.push([p[1], p[0]]));
    else if (f.geometry.type === "Point")
      hazardPoints.push([f.geometry.coordinates[1], f.geometry.coordinates[0]]);
  });
  return (
    <MapContainer
      center={[20.59, 78.96]}
      zoom={5}
      className="rescue-map"
      scrollWheelZoom
    >
      <TileLayer
        attribution="&copy; OpenStreetMap contributors"
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {hazards && (
        <GeoJSON
          key={JSON.stringify(hazards)}
          data={hazards}
          style={{ color: "#d88b35", weight: 2, fillOpacity: 0.17 }}
          pointToLayer={(_, p) =>
            L.circleMarker(p, { radius: 7, color: "#d88b35" })
          }
          onEachFeature={(f, layer) => {
            const label = document.createElement("span");
            label.textContent = String(f.properties?.name ?? "Hazard");
            layer.bindTooltip(label);
          }}
        />
      )}
      {incidents.map((i) => (
        <CircleMarker
          key={i.id}
          center={[i.latitude, i.longitude]}
          radius={10}
          pathOptions={{
            color: "#fff",
            weight: 2,
            fillColor: "#e34c59",
            fillOpacity: 1,
          }}
        >
          <Popup>
            <strong>SOS #{i.id}</strong>
            <p>{i.tourist.full_name || i.tourist_id}</p>
            <Link to={`/incidents/${i.id}`}>Open incident</Link>
          </Popup>
        </CircleMarker>
      ))}
      {route.length > 0 && (
        <Polyline
          positions={route}
          pathOptions={{ color: "#15847b", weight: 4 }}
        />
      )}
      {trip?.last_latitude != null && trip.last_longitude != null && (
        <CircleMarker
          center={[trip.last_latitude, trip.last_longitude]}
          radius={8}
        >
          <Popup>Last received GPS position</Popup>
        </CircleMarker>
      )}
      {draw && onDraw && <Draw points={draw} onChange={onDraw} />}
      <Fit points={points.length ? points : hazardPoints} />
    </MapContainer>
  );
}
