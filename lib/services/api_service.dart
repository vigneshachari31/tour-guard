import 'dart:async';
import 'dart:convert';

import '../models/geofence_update.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/route_response.dart';
import '../state/active_trip_state.dart';
import '../models/user_profile.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});
  bool get unauthorized => statusCode == 401;
  @override
  String toString() => message;
}

abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  final String key;
  final FlutterSecureStorage storage;
  const SecureSessionStore(
    this.key, {
    this.storage = const FlutterSecureStorage(),
  });
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}

class AuthSession {
  final String accessToken;
  final String? touristId;
  final String role;
  const AuthSession(this.accessToken, this.touristId, {this.role = 'tourist'});
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final token = json['access_token'];
    if (token is! String || token.isEmpty || json['token_type'] != 'bearer') {
      throw const FormatException('Invalid authentication response');
    }
    final role = json['role'];
    return AuthSession(
      token,
      json['tourist_id'] as String?,
      role: role == 'admin' ? 'admin' : 'tourist',
    );
  }
  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'token_type': 'bearer',
    'tourist_id': touristId,
    'role': role,
  };
}

class SosReceipt {
  final int id;
  final String status, message;
  const SosReceipt(this.id, this.status, this.message);
  factory SosReceipt.fromJson(Map<String, dynamic> json) => SosReceipt(
    json['id'] as int,
    json['status'] as String,
    json['message'] as String,
  );
}

class AdminSosEvent {
  final int id;
  final String touristId, status;
  final double latitude, longitude;
  final DateTime createdAt;
  final String? fullName,
      phoneNumber,
      bloodGroup,
      emergencyContact,
      medicalNotes;
  const AdminSosEvent({
    required this.id,
    required this.touristId,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.fullName,
    this.phoneNumber,
    this.bloodGroup,
    this.emergencyContact,
    this.medicalNotes,
  });
  factory AdminSosEvent.fromJson(Map<String, dynamic> json) => AdminSosEvent(
    id: json['id'] as int,
    touristId: json['tourist_id'] as String,
    status: json['status'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    createdAt: DateTime.parse(json['created_at'] as String),
    fullName: json['full_name'] as String?,
    phoneNumber: json['phone_number'] as String?,
    bloodGroup: json['blood_group'] as String?,
    emergencyContact: json['emergency_contact'] as String?,
    medicalNotes: json['medical_notes'] as String?,
  );
}

class AdminHazard {
  final int id, severity;
  final String name, hazardType, source;
  final bool isActive;
  final String geometryType;
  final List<List<List<double>>> polygonCoordinates;
  final List<double>? pointCoordinates;
  const AdminHazard({
    required this.id,
    required this.name,
    required this.hazardType,
    required this.severity,
    required this.source,
    required this.isActive,
    required this.geometryType,
    required this.polygonCoordinates,
    this.pointCoordinates,
  });
  bool get isPolygon => geometryType == 'Polygon';
  bool get isPoint => geometryType == 'Point';
  factory AdminHazard.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>? ?? json;
    final geometry =
        (json['geometry'] as Map<String, dynamic>?) ??
        (properties['geometry'] as Map<String, dynamic>?) ??
        const {};
    final geometryType = geometry['type'] as String? ?? 'Unknown';
    final rawCoordinates = geometry['coordinates'];
    return AdminHazard(
      id: (properties['id'] ?? json['id'] ?? 0) as int,
      name: (properties['name'] ?? json['name'] ?? 'Hazard Zone') as String,
      hazardType:
          (properties['hazard_type'] ?? json['hazard_type'] ?? 'general')
              as String,
      severity: (properties['severity'] ?? json['severity'] ?? 1) as int,
      source:
          (properties['source'] ?? json['source'] ?? 'Not recorded') as String,
      isActive: (properties['is_active'] ?? json['is_active'] ?? true) as bool,
      geometryType: geometryType,
      polygonCoordinates: geometryType == 'Polygon' && rawCoordinates is List
          ? rawCoordinates
                .map(
                  (ring) => (ring as List)
                      .map(
                        (point) => [
                          (point[0] as num).toDouble(),
                          (point[1] as num).toDouble(),
                        ],
                      )
                      .toList(),
                )
                .toList()
          : const [],
      pointCoordinates:
          geometryType == 'Point' &&
              rawCoordinates is List &&
              rawCoordinates.length >= 2
          ? [
              (rawCoordinates[0] as num).toDouble(),
              (rawCoordinates[1] as num).toDouble(),
            ]
          : null,
    );
  }
}

class ApiService {
  static final ApiService instance = ApiService();
  final http.Client _client;
  final SessionStore _store;
  final String baseUrl;
  final Duration timeout;

  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');

    if (configured.isNotEmpty) {
      return configured;
    }

    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000/api/v1'
        : 'http://127.0.0.1:8000/api/v1';
  }

  ApiService({
    http.Client? client,
    SessionStore? store,
    String? baseUrl,
    this.timeout = const Duration(seconds: 35),
  }) : baseUrl = (baseUrl ?? defaultBaseUrl).replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _store =
           store ??
           SecureSessionStore(
             'tour_guard_session_${baseUrl ?? defaultBaseUrl}',
           );

  Future<AuthSession?> getSession() async {
    try {
      final value = await _store.read();
      return value == null
          ? null
          : AuthSession.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } on PlatformException {
      throw const ApiException(
        'Unable to read secure login storage. Restart the app and try again.',
      );
    } on FormatException {
      await logout();
      return null;
    } on TypeError {
      await logout();
      return null;
    }
  }

  Future<String?> getToken() async => (await getSession())?.accessToken;
  Future<void> logout() async {
    ActiveTripState.instance.clear();
    await _store.clear();
  }

  void close() => _client.close();

  Future<AuthSession> login({
    required String email,
    required String password,
  }) => _authenticate('/auth/login', email, password);
  Future<AuthSession> register({
    required String email,
    required String password,
    String? fullName,
    String? emergencyContactPhone,
  }) => _authenticate(
    '/auth/register',
    email,
    password,
    extra: {
      if (fullName != null) 'full_name': fullName.trim(),
      if (emergencyContactPhone != null)
        'emergency_contact_phone': emergencyContactPhone.trim(),
    },
  );

  Future<AuthSession> _authenticate(
    String path,
    String email,
    String password, {
    Map<String, dynamic> extra = const {},
  }) async {
    final json = await _post(path, {
      'email': email.trim(),
      'password': password,
      ...extra,
    }, authenticated: false);
    try {
      final session = AuthSession.fromJson(json);
      await _store.write(jsonEncode(session.toJson()));
      ActiveTripState.instance.clear();
      return session;
    } on PlatformException {
      throw const ApiException(
        'Login succeeded but could not be saved securely. Please retry.',
      );
    } on FormatException {
      throw const ApiException(
        'The server returned an invalid login response.',
      );
    } on TypeError {
      throw const ApiException(
        'The server returned an invalid login response.',
      );
    }
  }

  Future<RouteResponse> analyzeRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    WeatherObservation? weather,
    String? originName,
    String? destinationName,
    bool startTrip = false,
  }) async {
    final json = await _post('/route/analyze', {
      'start_trip': startTrip,
      'origin_lat': originLat,
      'origin_lng': originLng,
      'dest_lat': destLat,
      'dest_lng': destLng,
      if (weather != null) 'weather': weather.toJson(),
      'origin_name': ?originName,
      'destination_name': ?destinationName,
    });
    try {
      return RouteResponse.fromJson(json);
    } catch (_) {
      throw const ApiException(
        'The server returned an invalid route assessment.',
      );
    }
  }

  Future<void> endTrip(int id) async {
    await _post('/trips/$id/end', {});
  }

  Future<GeofenceUpdate> recordTripLocation(
    int id,
    double latitude,
    double longitude,
  ) async {
    final response = await _post('/trips/$id/locations', {
      'latitude': latitude,
      'longitude': longitude,
    });
    try {
      return GeofenceUpdate.fromJson(response);
    } catch (_) {
      throw const ApiException(
        'Hazard monitoring response is invalid. Please update the backend.',
      );
    }
  }

  Future<SosReceipt> triggerSOS({
    required double latitude,
    required double longitude,
    String? touristId,
  }) async {
    final session = await getSession();
    if (session == null) {
      throw const ApiException('Please sign in again.', statusCode: 401);
    }
    final id = touristId ?? session.touristId;
    if (id == null || id.isEmpty) {
      throw const ApiException(
        'Your tourist ID is missing. Sign in again using the updated backend.',
      );
    }
    final json = await _post('/sos/trigger', {
      'tourist_id': id,
      'latitude': latitude,
      'longitude': longitude,
    });
    try {
      return SosReceipt.fromJson(json);
    } catch (_) {
      throw const ApiException(
        'SOS response was unreadable. Delivery is unconfirmed; check before retrying.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getActiveSosEvents() async {
    final response = await _post('/sos/events', {}, method: 'GET');
    final events = response['events'];
    if (events is List) {
      return events.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  Future<List<AdminSosEvent>> getAdminSosEvents() async {
    final result = await _post('/admin/sos-events', {}, method: 'GET');
    final events = result['items'] ?? result['events'] ?? result;
    if (events is! List) throw const ApiException('Invalid SOS desk response.');
    return events
        .map((event) => AdminSosEvent.fromJson(event as Map<String, dynamic>))
        .toList();
  }

  Future<AdminSosEvent> updateAdminSosStatus(int id, String status) async =>
      AdminSosEvent.fromJson(
        await _post('/admin/sos-events/$id/status', {
          'status': status,
        }, method: 'PATCH'),
      );

  Future<List<AdminHazard>> getActiveHazardZones() async {
    final result = await _post(
      '/hazards/active',
      {},
      authenticated: false,
      method: 'GET',
    );
    final items = result['features'] ?? result['items'] ?? result;
    if (items is! List) {
      throw const ApiException('Invalid hazard list response.');
    }
    return items
        .map((item) => AdminHazard.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<AdminHazard>> getAdminHazards({
    bool includeInactive = false,
  }) async {
    final result = await _post(
      '/admin/hazards?include_inactive=$includeInactive',
      {},
      method: 'GET',
    );
    final items = result['features'] ?? result['items'] ?? result;
    if (items is! List) {
      throw const ApiException('Invalid hazard-zone response.');
    }
    return items
        .map((item) => AdminHazard.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AdminHazard> createAdminHazard({
    required String name,
    required String hazardType,
    required int severity,
    required String source,
    required List<List<List<double>>> coordinates,
  }) async => AdminHazard.fromJson(
    await _post('/admin/hazards', {
      'name': name,
      'hazard_type': hazardType,
      'severity': severity,
      'source': source,
      'geometry': {'type': 'Polygon', 'coordinates': coordinates},
    }),
  );

  Future<void> deactivateAdminHazard(int id) async {
    await _post('/admin/hazards/$id', {'is_active': false}, method: 'PATCH');
  }

  Future<Map<String, dynamic>> reportTouristHazard({
    required double latitude,
    required double longitude,
    required String hazardType,
    required int severity,
    String? description,
  }) async {
    return await _post('/hazards/report', {
      'latitude': latitude,
      'longitude': longitude,
      'hazard_type': hazardType,
      'severity': severity,
      'description': description,
    });
  }

  Future<Map<String, dynamic>> reportHazard({
    required String name,
    required String hazardType,
    required int severity,
    required double latitude,
    required double longitude,
  }) async {
    return await reportTouristHazard(
      latitude: latitude,
      longitude: longitude,
      hazardType: hazardType,
      severity: severity,
      description: name,
    );
  }

  Future<UserProfile> getProfile() async =>
      UserProfile.fromJson(await _post('/profile/me', {}, method: 'GET'));

  Future<UserProfile> updateProfile(UserProfile profile) async =>
      UserProfile.fromJson(
        await _post('/profile/me', profile.toJson(), method: 'PUT'),
      );

  Future<UserProfile> uploadAvatar(Uint8List bytes) async {
    if (bytes.length > 2 * 1024 * 1024) {
      throw const ApiException('Choose an image smaller than 2 MB.');
    }
    return UserProfile.fromJson(
      await _post('/profile/upload-avatar', {
        'image_base64': base64Encode(bytes),
      }),
    );
  }

  Future<Uint8List> loadAvatar(String path) async {
    if (!RegExp(r'^/api/v1/profile/avatar/[a-f0-9]{32}$').hasMatch(path)) {
      throw const ApiException(
        'Invalid profile photo address. Please upload the photo again.',
      );
    }
    final result = await _post(
      path.substring('/api/v1'.length),
      {},
      method: 'GET',
      binary: true,
    );
    return result['bytes'] as Uint8List;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
    String method = 'POST',
    bool binary = false,
  }) async {
    final token = authenticated ? await getToken() : null;
    if (authenticated && token == null) {
      throw const ApiException('Please sign in to continue.', statusCode: 401);
    }
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });
      if (method != 'GET' && method != 'DELETE') {
        request.body = jsonEncode(body);
      }
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (response.statusCode == 401) {
        if (authenticated && await getToken() == token) await logout();
        throw ApiException(
          authenticated
              ? 'Your session expired. Please sign in again.'
              : 'Invalid email or password.',
          statusCode: 401,
        );
      }
      if (binary && response.statusCode >= 200 && response.statusCode < 300) {
        return {'bytes': response.bodyBytes};
      }
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        data = null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = data is Map ? data['detail'] : null;
        final message = detail is String
            ? detail
            : detail is List
            ? detail
                  .map(
                    (e) => e is Map
                        ? '${(e['loc'] as List?)?.last ?? 'Input'}: ${e['msg']}'
                        : 'Invalid input',
                  )
                  .join('\n')
            : 'Server request failed (${response.statusCode}). Please try again.';
        throw ApiException(message, statusCode: response.statusCode);
      }
      if (response.statusCode == 204) return const {};
      if (data is List) return {'items': data};
      if (data is! Map<String, dynamic>) {
        throw const ApiException('Invalid server response.');
      }
      return data;
    } on TimeoutException {
      throw ApiException(
        path == '/sos/trigger'
            ? 'SOS confirmation timed out. It may have been recorded; delivery is unconfirmed.'
            : 'The server took too long to respond. Please retry.',
      );
    } on http.ClientException {
      throw ApiException(
        path == '/sos/trigger'
            ? 'SOS connection failed. Delivery is unconfirmed; it may have been recorded.'
            : 'Cannot reach the backend. Check its address, your connection, and browser CORS settings.',
      );
    }
  }
}
