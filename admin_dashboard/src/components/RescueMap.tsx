import { useEffect } from "react";
import {
  MapContainer,
  TileLayer,
  GeoJSON,
  CircleMarker,
  Popup,
  Tooltip,
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

const tripIcons = {
  start: L.divIcon({className: 'trip-map-marker', html: '<span class="trip-pin trip-pin-start">A</span>', iconSize: [34,34], iconAnchor: [17,17]}),
  destination: L.divIcon({className: 'trip-map-marker', html: '<span class="trip-pin trip-pin-destination">B</span>', iconSize: [34,34], iconAnchor: [17,17]}),
  completed: L.divIcon({className: 'trip-map-marker', html: '<span class="trip-pin trip-pin-completed">&#10003;</span>', iconSize: [34,34], iconAnchor: [17,17]}),
  tourist: L.divIcon({className: 'trip-map-marker', html: '<span class="trip-pin trip-pin-tourist"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="8" r="3"/><path d="M5 21v-3a7 7 0 0 1 14 0v3"/></svg></span>', iconSize: [38,38], iconAnchor: [19,19]}),
};

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
    <div className="trip-map-frame">
    {trip && <div className="trip-map-legend" aria-label="Map legend">
      <span><b className="legend-start">A</b> Start</span>
      <span><b className={trip.status === 'completed' ? 'legend-completed' : 'legend-destination'}>{trip.status === 'completed' ? '✓' : 'B'}</b> {trip.status === 'completed' ? 'Arrived' : 'Destination'}</span>
      <span><b className="legend-tourist">•</b> Tourist GPS</span>
    </div>}
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
          pathOptions={{ color: "#087CF0", weight: 5, opacity: .85, lineCap: 'round' }}
        />
      )}
      {trip && <>
        <Marker position={[trip.origin_lat, trip.origin_lng]} icon={tripIcons.start} title="Trip start">
          <Tooltip>Start: {trip.source_name}</Tooltip>
          <Popup><strong>Trip start</strong><p>{trip.source_name}</p></Popup>
        </Marker>
        <Marker position={[trip.dest_lat, trip.dest_lng]} icon={trip.status === 'completed' ? tripIcons.completed : tripIcons.destination} title={trip.status === 'completed' ? 'Destination reached' : 'Destination'}>
          <Tooltip>{trip.status === 'completed' ? 'Arrived: ' : 'Destination: '}{trip.destination_name}</Tooltip>
          <Popup><strong>{trip.status === 'completed' ? 'Destination Reached' : 'Destination'}</strong><p>{trip.destination_name}</p></Popup>
        </Marker>
      </>}
      {trip?.status !== 'completed' && trip?.last_latitude != null && trip.last_longitude != null && (
        <Marker position={[trip.last_latitude, trip.last_longitude]} icon={tripIcons.tourist} zIndexOffset={1000} title="Tourist GPS position">
          <Tooltip>{trip.tourist_name || trip.tourist_id}: last received GPS</Tooltip>
          <Popup><strong>{trip.tourist_name || trip.tourist_id}</strong><p>Last received GPS position</p></Popup>
        </Marker>
      )}
      {draw && onDraw && <Draw points={draw} onChange={onDraw} />}
      <Fit points={points.length ? points : hazardPoints} />
    </MapContainer>
    </div>
  );
}
