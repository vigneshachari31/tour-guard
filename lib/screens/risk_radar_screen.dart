import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import '../services/current_location.dart';

class RiskRadarScreen extends StatefulWidget {
  final ApiService? api;
  final Future<Position> Function()? locate;
  final Stream<Position>? positions;
  const RiskRadarScreen({super.key, this.api, this.locate, this.positions});
  @override
  State<RiskRadarScreen> createState() => _RiskRadarScreenState();
}

class _RiskRadarScreenState extends State<RiskRadarScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false, _foreground = true;
  Timer? _timer;
  StreamSubscription<Position>? _locations;
  Position? _requestedPosition, _assessedPosition, _pendingPosition;
  bool _refreshRequested = false;

  void _watchLocation() {
    if (_locations != null || !_foreground) return;
    // Injected location providers stay isolated from device plugins in tests.
    if (widget.locate != null && widget.positions == null) return;
    final stream =
        widget.positions ??
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 50,
          ),
        );
    _locations = stream.listen(
      (position) {
        if (!mounted || !_foreground) return;
        final previous = _pendingPosition ?? _requestedPosition;
        if (previous == null ||
            Geolocator.distanceBetween(
                  previous.latitude,
                  previous.longitude,
                  position.latitude,
                  position.longitude,
                ) >=
                50) {
          _load(position: position);
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(
            () => _error =
                'Location tracking interrupted. Enable GPS and refresh.',
          );
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _load();
    } else {
      _locations?.cancel();
      _locations = null;
      _pendingPosition = null;
    }
  }

  Future<void> _load({Position? position}) async {
    if (!mounted || !_foreground) return;
    if (_busy) {
      if (position != null) _pendingPosition = position;
      if (position == null) _refreshRequested = true;
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = position ?? await (widget.locate ?? requireCurrentLocation)();
      if (!mounted || !_foreground) return;
      final age = DateTime.now().difference(p.timestamp);
      if (age > const Duration(minutes: 2) ||
          age < const Duration(seconds: -30)) {
        throw const ApiException(
          'GPS returned an old location. Enable precise location and retry.',
        );
      }
      _requestedPosition = p;
      _watchLocation();
      final data = await (widget.api ?? ApiService.instance).assessRisk(
        p.latitude,
        p.longitude,
      );
      if (mounted && _foreground && _pendingPosition == null) {
        setState(() {
          _data = data;
          _assessedPosition = p;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not refresh. Check location permission and connection.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        final pending = _pendingPosition;
        final refresh = _refreshRequested;
        _refreshRequested = false;
        _pendingPosition = null;
        if (_foreground && pending != null) {
          unawaited(_load(position: pending));
        } else if (_foreground && refresh) {
          unawaited(_load());
        }
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locations?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _timeLabel(BuildContext context, Object? value) {
    final time = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (time == null) return 'Time unavailable';
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatShortDate(time)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
  }

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE3EAF3)),
    ),
    child: child,
  );

  Widget _weatherMetric(
    IconData icon,
    String label,
    Object? value,
    String unit,
  ) {
    return SizedBox(
      width: 125,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF087CF0), size: 22),
          const SizedBox(height: 8),
          Text(
            value == null ? 'Unavailable' : '$value $unit',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final score = (_data?['score'] as num?)?.toInt() ?? 0;
    final level = _data?['risk_level'] as String? ?? '';
    final color = level == 'HIGH'
        ? Colors.red
        : level == 'MODERATE'
        ? Colors.amber
        : Colors.green;
    final weather = _data?['weather'] as Map<String, dynamic>?;
    final factors = _data?['factors'] as List? ?? [];
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F8FC),
        title: const Text(
          'AI Risk Radar',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh radar',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 720,
            child: RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  const Row(
                    children: [
                      Icon(Icons.radar_rounded, color: Color(0xFF087CF0)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Around you · 2 km',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF183153),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_assessedPosition != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Assessed location: ${_assessedPosition!.latitude.toStringAsFixed(5)}, ${_assessedPosition!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_busy) ...[
                    const LinearProgressIndicator(minHeight: 3),
                    const SizedBox(height: 8),
                    Text(
                      _data == null
                          ? 'Checking nearby conditions…'
                          : 'Updating location… Previous assessment shown.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null)
                    _panel(
                      Text(
                        _data == null
                            ? _error!
                            : '$_error Previous results may be out of date.',
                        style: const TextStyle(color: Color(0xFF9B5310)),
                      ),
                    ),
                  if (_data != null) ...[
                    _panel(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'NEARBY RISK INDEX',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              color: Colors.blueGrey,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Center(
                            child: SizedBox(
                              width: 140,
                              height: 140,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox.expand(
                                    child: CircularProgressIndicator(
                                      value: (score / 100).clamp(0.0, 1.0),
                                      strokeWidth: 10,
                                      color: color,
                                      backgroundColor: color.withValues(
                                        alpha: .12,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '$score%',
                                        style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF183153),
                                        ),
                                      ),
                                      Chip(
                                        key: const ValueKey(
                                          'radar-status-badge',
                                        ),
                                        backgroundColor: color.withValues(
                                          alpha: .12,
                                        ),
                                        side: BorderSide(color: color),
                                        label: Text(level),
                                        labelStyle: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Based on nearby reports and weather.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Rule-based score, not the chance of an incident.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                          const Text(
                            'What affects this score',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final factor in factors)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '• $factor',
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          if (factors.isEmpty)
                            const Text(
                              'No scoring thresholds triggered. Missing reports do not establish safety.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blueGrey,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _panel(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Local weather',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (weather == null)
                            const Text(
                              'Weather unavailable. No weather values were assumed.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blueGrey,
                              ),
                            )
                          else ...[
                            Wrap(
                              spacing: 16,
                              runSpacing: 18,
                              children: [
                                _weatherMetric(
                                  Icons.thermostat_rounded,
                                  'Temperature',
                                  weather['temperature_c'],
                                  '°C',
                                ),
                                _weatherMetric(
                                  Icons.air_rounded,
                                  'Wind',
                                  weather['wind_kmh'],
                                  'km/h',
                                ),
                                _weatherMetric(
                                  Icons.water_drop_outlined,
                                  'Forecast-hour rain',
                                  weather['rainfall_mm_h'],
                                  'mm',
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Forecast · ${_timeLabel(context, weather['at'])}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      'Updated · ${_timeLabel(context, _data!['checked_at'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Nearby conditions only—not a full-route assessment or a guarantee of safety.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                        height: 1.5,
                      ),
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'About this assessment',
                        style: TextStyle(fontSize: 13),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'This radar does not predict when a disaster will occur.${weather == null ? '' : '\nWeather source: ${weather['source'] ?? 'Not provided'}'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
