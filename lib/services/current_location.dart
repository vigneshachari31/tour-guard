import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'api_service.dart';

Future<Position> requireCurrentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const ApiException('Turn on device location and try again.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const ApiException(
      'Allow location access in device settings to continue.',
    );
  }
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  } on TimeoutException {
    throw const ApiException(
      'GPS timed out. Check your location signal and retry.',
    );
  }
}
