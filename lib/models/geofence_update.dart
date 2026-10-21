class GeofenceHazard {
  final int id, severity;
  final String name, type;
  const GeofenceHazard(this.id, this.name, this.type, this.severity);
  factory GeofenceHazard.fromJson(Map<String, dynamic> json) => GeofenceHazard(
    json['hazard_id'] as int,
    json['name'] as String,
    json['hazard_type'] as String,
    json['severity'] as int,
  );
}

class GeofenceUpdate {
  final List<GeofenceHazard> currentHazards, alerts;
  const GeofenceUpdate(this.currentHazards, this.alerts);
  factory GeofenceUpdate.fromJson(Map<String, dynamic> json) {
    List<GeofenceHazard> parse(String key) => (json[key] as List)
        .map((item) => GeofenceHazard.fromJson(item as Map<String, dynamic>))
        .toList();
    return GeofenceUpdate(parse('current_hazards'), parse('alerts'));
  }
}
