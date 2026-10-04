import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/backend_service.dart';
import '../services/routing_service.dart';
import '../services/tourist_profile_store.dart';

// ==============================================================================
// 🚨 SMART RESCUE & EMERGENCY SOS SCREEN (TOUR GUARD)
// ------------------------------------------------------------------------------
// Key Features:
// 1. Interactive 3-Second Abort / Confirmation Timer (prevents accidental triggers).
// 2. Pulsing High-Visibility Emergency Siren Beacon Animation.
// 3. Live Telemetry: GPS Coordinates (Lat/Lng), Altitude, and Timestamp.
// 4. Tourist Medical Context: Blood Group, Emergency Contacts & Digital ID.
// 5. Emergency Hotline Quick-Dials: 112 (Police), 108 (Ambulance), 1077 (Disaster).
// 6. Backend SOS logging (demo acknowledgement; no emergency dispatch).
// ==============================================================================

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  // ─── Animation & Timer Controllers ──────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Timer? _countdownTimer;
  int _countdownSeconds = 3;
  bool _isCountingDown = false;
  bool _isSosDispatched = false;
  bool _isSosDispatching = false;
  bool _hasLiveLocation = false;
  String? _sosStatusMessage;

  // ─── Live Telemetry State ───────────────────────────────────────────────────
  LatLng _currentLocation = const LatLng(11.4102, 76.6950);
  double _altitudeMeters = 2240.0;
  String _localityName = 'Nilgiris District, Tamil Nadu';
  bool _isLoadingGps = true;

  // Profile values are stored locally until account-backed profiles exist.
  TouristProfile _touristProfile = const TouristProfile();

  @override
  void initState() {
    super.initState();

    // Setup pulsing glow animation for emergency beacon
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadTouristProfile();
    _fetchLiveTelemetry();
  }

  Future<void> _loadTouristProfile() async {
    try {
      final profile = await TouristProfile.load();
      if (mounted) setState(() => _touristProfile = profile);
    } catch (error) {
      debugPrint('Failed to load tourist profile for SOS: $error');
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── 1. FETCH LIVE GPS TELEMETRY ───────────────────────────────────────────
  Future<void> _fetchLiveTelemetry() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );

      final latLng = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _currentLocation = latLng;
          _altitudeMeters = position.altitude > 0 ? position.altitude : 2240.0;
          _isLoadingGps = false;
          _hasLiveLocation = true;
        });

        // Reverse geocode to get human-readable location name
        final placeName = await RoutingService.reverseGeocode(
          latLng.latitude,
          latLng.longitude,
        );
        if (placeName != null && mounted) {
          setState(() {
            _localityName = placeName;
          });
        }
      }
    } catch (_) {
      // Use fallback telemetry safely
      if (mounted) {
        setState(() => _isLoadingGps = false);
      }
    }
  }

  // ─── 2. TRIGGER 3-SECOND COUNTDOWN ─────────────────────────────────────────
  void _startCountdown() {
    setState(() {
      _isCountingDown = true;
      _countdownSeconds = 3;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() => _countdownSeconds--);
      } else {
        timer.cancel();
        _dispatchSosEmergency();
      }
    });
  }

  // ─── 3. CANCEL / ABORT SOS ──────────────────────────────────────────────────
  void _abortSos() {
    _countdownTimer?.cancel();
    setState(() {
      _isCountingDown = false;
      _countdownSeconds = 3;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('SOS Trigger Cancelled (False Alarm Aborted)'),
        backgroundColor: Color(0xFF53647F),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ─── 4. DISPATCH SOS PACKET ─────────────────────────────────────────────────
  Future<void> _dispatchSosEmergency() async {
    setState(() {
      _isCountingDown = false;
      _isSosDispatching = true;
    });

    if (!_hasLiveLocation) {
      const message =
          'SOS was not sent: live GPS is unavailable. Call emergency services directly.';
      setState(() {
        _isSosDispatching = false;
        _sosStatusMessage = message;
      });
      _showSosMessage(message, isError: true);
      return;
    }

    try {
      final result = await BackendService.dispatchSos(
        latitude: _currentLocation.latitude,
        longitude: _currentLocation.longitude,
        altitudeM: _altitudeMeters,
        userName: _touristProfile.name.trim().isEmpty
            ? 'Tourist'
            : _touristProfile.name.trim(),
        bloodGroup: _optionalProfileValue(_touristProfile.bloodGroup),
        medicalNotes: _optionalProfileValue(_touristProfile.medicalNotes),
        allergies: _optionalProfileValue(_touristProfile.allergies),
        emergencyContact: _optionalProfileValue(
          _touristProfile.emergencyContact,
        ),
        locationName: _localityName,
      );
      if (!mounted) return;
      setState(() {
        _isSosDispatching = false;
        _isSosDispatched = true;
        _sosStatusMessage =
            'Demo backend logged incident ${result.incidentId}. '
            'No rescue team or emergency service was contacted.';
      });
      _showSosMessage(_sosStatusMessage!, isError: false);
    } catch (error) {
      debugPrint('SOS backend request failed: $error');
      if (!mounted) return;
      setState(() {
        _isSosDispatching = false;
        _sosStatusMessage =
            'SOS request failed. Try again or call emergency services directly.';
      });
      _showSosMessage(_sosStatusMessage!, isError: true);
    }
  }

  void _showSosMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFDC2626)
            : const Color(0xFF1EAA55),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  // ─── 5. RESET RESCUE STATE ──────────────────────────────────────────────────
  void _resetSosState() {
    setState(() {
      _isSosDispatched = false;
      _isSosDispatching = false;
      _isCountingDown = false;
      _countdownSeconds = 3;
      _sosStatusMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFF0F172A,
      ), // High-contrast Emergency Dark Slate
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SMART RESCUE COMMAND',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ─── Top Live Beacon Status Banner ──────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _isSosDispatched
                      ? const Color(0xFFDC2626).withValues(alpha: 0.25)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isSosDispatched
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF334155),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: _isSosDispatched
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF22C55E),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isSosDispatched
                          ? '✅ INCIDENT LOGGED IN DEMO BACKEND'
                          : _isSosDispatching
                          ? '⏳ SENDING TO DEMO BACKEND'
                          : '⚡ SOS BACKEND READY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: _isSosDispatched
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ─── Central SOS Siren Button / Countdown Ring ──────────────────
              GestureDetector(
                onTap: () {
                  if (_isCountingDown) {
                    _abortSos();
                  } else if (!_isSosDispatched && !_isSosDispatching) {
                    _startCountdown();
                  }
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Pulsing Glow Ring
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          width:
                              220 *
                              (_isCountingDown ? 1.15 : _pulseAnimation.value),
                          height:
                              220 *
                              (_isCountingDown ? 1.15 : _pulseAnimation.value),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                (_isSosDispatched || _isCountingDown
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFFEF4444))
                                    .withValues(alpha: 0.15),
                          ),
                        );
                      },
                    ),

                    // Middle Solid Halo
                    Container(
                      width: 175,
                      height: 175,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                      ),
                    ),

                    // Core Button Container
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isSosDispatched
                              ? [
                                  const Color(0xFF991B1B),
                                  const Color(0xFF7F1D1D),
                                ]
                              : [
                                  const Color(0xFFEF4444),
                                  const Color(0xFFDC2626),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66DC2626),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isCountingDown
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$_countdownSeconds',
                                    style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const Text(
                                    'TAP TO ABORT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white70,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ],
                              )
                            : _isSosDispatched
                            ? const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.emergency_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'SOS',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Text(
                _isCountingDown
                    ? 'Transmitting distress packet in $_countdownSeconds seconds...'
                    : _isSosDispatched
                    ? 'Demo backend accepted the incident; no emergency services were contacted.'
                    : _isSosDispatching
                    ? 'Sending current GPS location to the backend...'
                    : 'Tap SOS to log a demo incident after a 3-second countdown',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _isCountingDown
                      ? const Color(0xFFEF4444)
                      : _isSosDispatched
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF94A3B8),
                ),
                textAlign: TextAlign.center,
              ),

              if (_sosStatusMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _sosStatusMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFCA5A5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              if (_isSosDispatched) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _resetSosState,
                  icon: const Icon(
                    Icons.cancel_outlined,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                  label: const Text(
                    'Cancel Active SOS Distress Mode',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ─── Telemetry Context Card ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.location_searching_rounded,
                          size: 16,
                          color: Color(0xFF38BDF8),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'LIVE RESCUE TELEMETRY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TelemetryRow(
                      label: 'GPS Coordinates',
                      value: _isLoadingGps
                          ? 'Acquiring high-accuracy fix...'
                          : '${_currentLocation.latitude.toStringAsFixed(5)}°N, ${_currentLocation.longitude.toStringAsFixed(5)}°E',
                    ),
                    _TelemetryRow(
                      label: 'Elevation',
                      value:
                          '${_altitudeMeters.toStringAsFixed(0)} m ASL (Highland)',
                    ),
                    _TelemetryRow(
                      label: 'Nearest Location',
                      value: _localityName,
                    ),
                    _TelemetryRow(
                      label: 'Timestamp',
                      value: DateTime.now().toLocal().toString().substring(
                        0,
                        19,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ─── Tourist Medical & Emergency Card ───────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.medical_information_rounded,
                          size: 16,
                          color: Color(0xFFF43F5E),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'TOURIST EMERGENCY CONTEXT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TelemetryRow(
                      label: 'Tourist Name',
                      value: _displayProfileValue(_touristProfile.name),
                    ),
                    _TelemetryRow(
                      label: 'Blood Group',
                      value: _displayProfileValue(_touristProfile.bloodGroup),
                      isHighlight: true,
                    ),
                    _TelemetryRow(
                      label: 'Emergency Contact',
                      value: _displayProfileValue(
                        _touristProfile.emergencyContact,
                      ),
                    ),
                    _TelemetryRow(
                      label: 'Phone',
                      value: _displayProfileValue(_touristProfile.phone),
                    ),
                    _TelemetryRow(
                      label: 'Medical Notes',
                      value: _displayProfileValue(_touristProfile.medicalNotes),
                    ),
                    _TelemetryRow(
                      label: 'Allergies',
                      value: _displayProfileValue(_touristProfile.allergies),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ─── Direct Emergency Quick-Dial Grid ───────────────────────────
              const Text(
                'EMERGENCY NUMBERS — CALL DIRECTLY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _HelplineCard(
                      title: 'Police Command',
                      number: '112',
                      icon: Icons.local_police_rounded,
                      color: const Color(0xFF3B82F6),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Use your phone to call Police: 112.',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HelplineCard(
                      title: 'Disaster Control',
                      number: '1077',
                      icon: Icons.support_agent_rounded,
                      color: const Color(0xFFF97316),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Use your phone to call Disaster Control: 1077.',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HelplineCard(
                      title: 'Ambulance',
                      number: '108',
                      icon: Icons.medical_services_rounded,
                      color: const Color(0xFF10B981),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Use your phone to call Ambulance: 108.',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

String _displayProfileValue(String value) =>
    value.trim().isEmpty ? 'Not provided' : value.trim();

String? _optionalProfileValue(String value) =>
    value.trim().isEmpty ? null : value.trim();

// ─── Telemetry Single Row Widget ─────────────────────────────────────────────
class _TelemetryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isHighlight;

  const _TelemetryRow({
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isHighlight ? const Color(0xFFF43F5E) : Colors.white,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpline Quick Action Card Widget ────────────────────────────────────────
class _HelplineCard extends StatelessWidget {
  final String title;
  final String number;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HelplineCard({
    required this.title,
    required this.number,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 6),
            Text(
              number,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
