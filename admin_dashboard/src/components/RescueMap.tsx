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
        <Polygon positions={points} pathOptions={{ color: "#087CF0" }} />
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
        attribution='Tiles &copy; Esri &mdash; Source: Esri, DeLorme, NAVTEQ, USGS, Intermap, iPC, NRCAN, METI, TomTom'
        url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}"
        maxZoom={18}
      />
      {hazards && (
        <GeoJSON
          key={JSON.stringify(hazards)}
          data={hazards}
          style={{ color: "#E08700", weight: 2, fillOpacity: 0.17 }}
          pointToLayer={(_, p) =>
            L.circleMarker(p, { radius: 7, color: "#E08700" })
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
            fillColor: "#DC2626",
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
          pathOptions={{ color: "#087CF0", weight: 4 }}
        />
      )}
      {trip && <>
        <CircleMarker center={[trip.origin_lat, trip.origin_lng]} radius={9} pathOptions={{color: '#087CF0', fillOpacity: 1}}><Popup>Source: {trip.source_name}</Popup></CircleMarker>
        <Marker position={[trip.dest_lat, trip.dest_lng]} icon={L.divIcon({className: 'destination-flag', html: trip.status === 'completed' ? '<span style="color:green;font-size:30px">&#9873;</span>' : '<span style="color:red;font-size:30px">&#9873;</span>', iconSize: [32,32]})}>
          <Popup>{trip.status === 'completed' ? 'Destination Reached' : 'Destination'}: {trip.destination_name}</Popup>
        </Marker>
      </>}
      {trip?.status !== 'completed' && trip?.last_latitude != null && trip.last_longitude != null && (
        <CircleMarker
          center={[trip.last_latitude, trip.last_longitude]}
          radius={8}
          pathOptions={{ color: "#1EAA55", fillColor: "#1EAA55", fillOpacity: 0.9 }}
        >
          <Popup>{trip.tourist_name || trip.tourist_id}: last received GPS position</Popup>
        </CircleMarker>
      )}
      {draw && onDraw && <Draw points={draw} onChange={onDraw} />}
      <Fit points={points.length ? points : hazardPoints} />
    </MapContainer>
  );
}
