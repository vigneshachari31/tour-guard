export type Page<T> = {
  items: T[];
  total: number;
  limit: number;
  offset: number;
};
export type Admin = {
  id: number;
  email: string;
  full_name: string | null;
  role: "admin";
};
export type Status = "OPEN" | "IN_PROGRESS" | "RESOLVED" | "CANCELLED";
export type Incident = {
  id: number;
  tourist_id: string;
  latitude: number;
  longitude: number;
  created_at: string;
  status: Status;
  responder_id: number | null;
  tourist: {
    full_name: string | null;
    email: string | null;
    phone: string | null;
  };
  last_location: { latitude: number; longitude: number; at: string };
};
export type History = {
  id: number;
  old_status: string;
  new_status: string;
  notes: string | null;
  created_at: string;
};
export type Assignment = {
  id: number;
  responder_id: number;
  sos_event_id: number;
  status: string;
  notes?: string;
  created_at: string;
};
export type IncidentDetail = Incident & {
  history: History[];
  assignments: Assignment[];
  trips: Trip[];
  emergency_profile: Record<string, string | null> | null;
};
export type Responder = {
  id: number;
  name: string;
  phone: string;
  email: string | null;
  role: string;
  status: string;
  assignments: Assignment[];
};
export type HazardProperties = {
  id: number;
  name: string;
  hazard_type: string;
  severity: number;
  source: string;
  is_active: boolean;
  valid_from: string | null;
  valid_until: string | null;
  updated_at: string;
};
export type Hazards = GeoJSON.FeatureCollection<
  GeoJSON.Geometry,
  HazardProperties
>;
export type Trip = {
  tourist_name?: string | null;
  lifecycle_status?: string;
  origin_lat: number;
  origin_lng: number;
  dest_lat: number;
  dest_lng: number;
  distance_remaining?: number | null;
  completed_at?: string | null;

  current_hazards?: { hazard_id: number; name: string; hazard_type: string; severity: number }[];
  recent_hazard_alerts?: { hazard_id: number; name: string; hazard_type: string; severity: number; detected_at: string }[];
  id: number;
  tourist_id: string;
  source_name: string;
  destination_name: string;
  status: string;
  started_at: string;
  ended_at: string | null;
  last_latitude: number | null;
  last_longitude: number | null;
  last_location_updated_at: string | null;
  stale_location: boolean;
  route_geometry: GeoJSON.LineString | null;
  risk_level: string | null;
};
export type Risk = {
  id: number;
  user_id: number;
  trip_id: number | null;
  risk_level: string;
  distance_meters: number;
  duration_seconds: number;
  hazards_count: number;
  weather_used: boolean;
  reasons: string[];
  limitations: string[];
  created_at: string;
};
export type Tourist = {
  id: number;
  email: string;
  full_name: string | null;
  tourist_id: string;
  phone_number: string | null;
  is_active: boolean;
};
export type Audit = {
  id: number;
  admin_email: string;
  action: string;
  resource_type: string;
  resource_id: string | null;
  details: string | null;
  created_at: string;
};
export type Stats = {
  total_users: number;
  active_trips: number;
  open_incidents: number;
  in_progress_incidents: number;
  resolved_incidents: number;
  active_hazards: number;
};
export type ChartPoint = { name: string; count: number };
export type Charts = {
  incidents_over_time: ChartPoint[];
  incident_status: ChartPoint[];
  hazard_categories: ChartPoint[];
  risk_buckets: ChartPoint[];
  risk_bucket_note: string;
};
