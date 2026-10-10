import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/route_response.dart';

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
  const AuthSession(this.accessToken, this.touristId);
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final token = json['access_token'];
    if (token is! String || token.isEmpty || json['token_type'] != 'bearer') {
      throw const FormatException('Invalid authentication response');
    }
    return AuthSession(token, json['tourist_id'] as String?);
  }
  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'token_type': 'bearer',
    'tourist_id': touristId,
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

class ApiService {
  static final ApiService instance = ApiService();
  final http.Client _client;
  final SessionStore _store;
  final String baseUrl;
  final Duration timeout;

  static String get defaultBaseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
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
  Future<void> logout() => _store.clear();
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
  }) async {
    final json = await _post('/route/analyze', {
      'origin_lat': originLat,
      'origin_lng': originLng,
      'dest_lat': destLat,
      'dest_lng': destLng,
      if (weather != null) 'weather': weather.toJson(),
    });
    try {
      return RouteResponse.fromJson(json);
    } catch (_) {
      throw const ApiException(
        'The server returned an invalid route assessment.',
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

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    final token = authenticated ? await getToken() : null;
    if (authenticated && token == null) {
      throw const ApiException('Please sign in to continue.', statusCode: 401);
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
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
