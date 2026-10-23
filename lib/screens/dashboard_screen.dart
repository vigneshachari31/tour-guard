import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'profile_screen.dart';
import '../services/api_service.dart';
import '../services/current_location.dart';
import '../widgets/dashboard/dashboard_header.dart';
import '../widgets/dashboard/safety_services_grid.dart';
import '../widgets/dashboard/route_risk_card.dart';
import '../state/active_trip_state.dart';
import '../widgets/dashboard/search_destination_bar.dart';
import '../widgets/dashboard/smart_rescue_card.dart';
import 'map_screen.dart';
import 'sos_screen.dart';
import 'risk_radar_screen.dart';

// ==============================================================================
// 📱 MAIN DASHBOARD SCREEN (TOUR GUARD)
// Modular, clean, and composed of 5 dedicated safety components.
// ==============================================================================
class DashboardScreen extends StatefulWidget {
  final ActiveTripState? tripState;
  final ApiService? api;
  const DashboardScreen({super.key, this.tripState, this.api});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Current active tab index in the Bottom Navigation Bar
  int _currentTabIndex = 0;
  bool _endingTrip = false;
  Timer? _sosTimer;
  Map<String, dynamic>? _activeSos;
  bool _sosBusy = false;
  bool _sosOffline = false;
  Future<void> _refreshSos() async {
    if (_sosBusy) return;
    _sosBusy = true;
    try {
      final events = await ApiService.instance.getActiveSosEvents();
      final active = events.where((e) => ['OPEN', 'IN_PROGRESS'].contains(e['workflow_status']));
      if (mounted) setState(() {
        _activeSos = active.isEmpty ? null : active.first;
        _sosOffline = false;
      });
    } catch (_) {
      if (mounted) setState(() => _sosOffline = true);
    } finally { _sosBusy = false; }
  }
  final _destinationController = TextEditingController();
  ActiveTripState get _trips => widget.tripState ?? ActiveTripState.instance;

  @override
  void initState() {
    super.initState();
    _syncTrip();
    _trips.addListener(_tripChanged);
    if (widget.tripState == null) {
      _refreshSos();
      _sosTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refreshSos());
    }
  }

  void _syncTrip() {
    _destinationController.text = _trips.trip?.destinationName ?? '';
  }

  void _tripChanged() {
    if (mounted) setState(_syncTrip);
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _trips.removeListener(_tripChanged);
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _endTrip() async {
    if (_endingTrip) return;
    final trip = _trips.trip;
    setState(() => _endingTrip = true);
    try {
      if (trip?.route.tripId != null) {
        await (widget.api ?? ApiService.instance).endTrip(trip!.route.tripId!);
      }
      if (identical(_trips.trip, trip)) _trips.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Unable to end trip. Please retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _endingTrip = false);
    }
  }

  // Navigation helper to open the interactive map & routing screen
  Future<void> _navigateToMap([
    String? destination,
    bool trackGps = false,
  ]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(
          initialDestination: destination,
          trackGpsOnStart:
              trackGps ||
              (_trips.trip == null &&
                  destination != null &&
                  destination.isNotEmpty),
          tripState: _trips,
        ),
      ),
    );
    if (mounted) setState(_syncTrip);
  }

  // Navigation helper to open the Emergency SOS & Smart Rescue screen
  Future<void> _navigateToSos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SosScreen()),
    );
    if (mounted) await _refreshSos();
  }

  Future<void> _handleLiveSharing() async {
    try {
      final position = await requireCurrentLocation();
      final url =
          'https://maps.google.com/?q=${position.latitude},${position.longitude}';
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Live location link copied to clipboard: $url'),
          backgroundColor: const Color(0xFF1EAA55),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : 'Could not obtain GPS location. Enable device location services to share your position.',
          ),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  void _showReportHazardDialog() {
    String hazardType = 'landslide';
    int severity = 3;
    final nameController = TextEditingController();
    LatLng? location;
    bool isLocating = true;
    String? locationError;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (isLocating && location == null && locationError == null) {
              requireCurrentLocation()
                  .then((pos) {
                    if (ctx.mounted) {
                      setSheetState(() {
                        location = LatLng(pos.latitude, pos.longitude);
                        isLocating = false;
                      });
                    }
                  })
                  .catchError((err) {
                    if (ctx.mounted) {
                      setSheetState(() {
                        locationError = err is ApiException
                            ? err.message
                            : 'GPS unavailable';
                        isLocating = false;
                      });
                    }
                  });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFFF9800),
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Report Hazard to Safety Radar',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A2D4F),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isLocating)
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Pinpointing your GPS location...',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      )
                    else if (location != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F3FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.my_location,
                              size: 16,
                              color: Color(0xFF087CF0),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Location: ${location!.latitude.toStringAsFixed(4)}, ${location!.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF087CF0),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEAEA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Location error: $locationError',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Hazard Type',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: hazardType,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'landslide',
                          child: Text('Landslide / Rockfall'),
                        ),
                        DropdownMenuItem(
                          value: 'flood',
                          child: Text('Flash Flood / Waterlogging'),
                        ),
                        DropdownMenuItem(
                          value: 'road',
                          child: Text('Road Closure / Obstruction'),
                        ),
                        DropdownMenuItem(
                          value: 'weather',
                          child: Text('Severe Storm / Wind'),
                        ),
                        DropdownMenuItem(
                          value: 'fog',
                          child: Text('Dense Fog / Low Visibility'),
                        ),
                        DropdownMenuItem(
                          value: 'animal',
                          child: Text('Wildlife Hazard'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setSheetState(() => hazardType = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Severity (1 = Minor, 5 = Critical)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: severity.toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            label: 'Severity: $severity',
                            activeColor: severity >= 4
                                ? const Color(0xFFDC2626)
                                : const Color(0xFFFF9800),
                            onChanged: (val) =>
                                setSheetState(() => severity = val.round()),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: severity >= 4
                                ? const Color(0xFFFFEAEA)
                                : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Level $severity',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: severity >= 4
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Hazard Description',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Fallen tree blocking both lanes near hairpin 3',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF087CF0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: (isSubmitting || location == null)
                            ? null
                            : () async {
                                final desc = nameController.text.trim();
                                if (desc.length < 3) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please enter at least 3 characters for the description.',
                                      ),
                                      backgroundColor: Color(0xFFDC2626),
                                    ),
                                  );
                                  return;
                                }
                                setSheetState(() => isSubmitting = true);
                                try {
                                  final result = await ApiService.instance
                                      .reportTouristHazard(
                                        description: desc,
                                        hazardType: hazardType,
                                        severity: severity,
                                        latitude: location!.latitude,
                                        longitude: location!.longitude,
                                      );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Hazard "${result['name']}" reported successfully (ID: #${result['id']}).',
                                      ),
                                      backgroundColor: const Color(0xFF1EAA55),
                                    ),
                                  );
                                } catch (error) {
                                  setSheetState(() => isSubmitting = false);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        error is ApiException ? error.message : 'Failed to record hazard report. Please check your connection and retry.',
                                      ),
                                      backgroundColor: const Color(0xFFDC2626),
                                    ),
                                  );
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'SUBMIT HAZARD REPORT',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAlertsView() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardHeader(),
              const SizedBox(height: 16),
              const Text(
                'YOUR SOS RECORDS & ALERTS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: Color(0xFF1A2D4F),
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: ApiService.instance.getActiveSosEvents(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Card(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFDC2626),
                              size: 36,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              snapshot.error is ApiException
                                  ? (snapshot.error as ApiException).message
                                  : 'Could not retrieve rescue alerts. Verify connection.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => setState(() {}),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final events = snapshot.data ?? [];
                  if (events.isEmpty) {
                    return Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: Color(0xFF1EAA55),
                              size: 48,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No Active Emergency Beacons',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A2D4F),
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'You have no active SOS records. This does not indicate current travel conditions.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Color(0xFFB7791F),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Emergency records logged in rescue registry. Responder dispatch is unconfirmed unless direct integration is active.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF7C5A22),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final event in events)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFFFD4D4)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDC2626),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.emergency,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'ACTIVE SOS BEACON',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'ID: #${event['id']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Tourist: ${event['tourist_id'] ?? 'Unassigned'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Color(0xFF1A2D4F),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'GPS: ${event['latitude']?.toStringAsFixed(5)}, ${event['longitude']?.toStringAsFixed(5)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF087CF0),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Time: ${event['created_at']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC), // Modern off-white / slate
      // Main Scrollable Body
      body: _currentTabIndex == 4
          ? const ProfileScreen()
          : _currentTabIndex == 3
          ? _buildAlertsView()
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. App Title & Notifications Header
                    const DashboardHeader(),
                    if (_activeSos != null)
                      Card(
                        color: const Color(0xFFFFF1F0),
                        child: ListTile(
                          leading: const Icon(Icons.sos, color: Colors.red),
                          title: Text('Active SOS #${_activeSos!['id']}'),
                          subtitle: Text(_sosOffline
                            ? 'Updates unavailable. Last received status shown.'
                            : switch (_activeSos!['responder_stage']) {
                                'ASSIGNED' => 'Responder assigned. Awaiting acceptance.',
                                'ACCEPTED' => 'Responder acceptance confirmed.',
                                'DEPARTED' => 'Responder is on the way.',
                                'ARRIVED' => 'Responder arrival confirmed.',
                                _ => 'Received. Waiting for assignment.',
                              }),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _navigateToSos,
                        ),
                      ),
                    const SizedBox(height: 16),

                    // 2. AI Safety Status & Live Environmental Card (Compact)
                    RouteRiskCard(
                      trip: _trips.trip,
                      onEndTrip: _endingTrip ? null : _endTrip,
                      onOpenMap: () => _navigateToMap(),
                    ),
                    const SizedBox(height: 18),

                    // 3. Destination Search Bar
                    SearchDestinationBar(
                      controller: _destinationController,
                      onSubmitted: (query) => _navigateToMap(query),
                      onGpsTap: () => _navigateToMap(null, true),
                    ),
                    const SizedBox(height: 20),

                    // 4. 2x2 Core Safety Services Grid (AI Radar, Route, Sharing, Reports)
                    SafetyServicesGrid(
                      onRiskRadarTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RiskRadarScreen())),
                      onSafeRouteTap: () => _navigateToMap(),
                      onLiveSharingTap: _handleLiveSharing,
                      onReportHazardTap: _showReportHazardDialog,
                    ),
                    const SizedBox(height: 20),

                    // 5. Emergency SOS Beacon & Official Helplines (112, 1077)
                    SmartRescueCard(onTriggerSos: _navigateToSos),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),

      // 6. Bottom Navigation Bar (Home, Safe Route, SOS, Alerts, Profile)
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x0A0E4E91),
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: (int index) {
            if (index == 1) {
              _navigateToMap();
            } else if (index == 2) {
              _navigateToSos();
            } else {
              setState(() {
                _currentTabIndex = index;
              });
            }
          },
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE8F3FF),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF087CF0)),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.alt_route_outlined),
              selectedIcon: Icon(
                Icons.alt_route_rounded,
                color: Color(0xFF087CF0),
              ),
              label: 'Safe Route',
            ),
            NavigationDestination(
              icon: Icon(Icons.emergency_outlined),
              selectedIcon: Icon(
                Icons.emergency_rounded,
                color: Color(0xFFDC2626),
              ),
              label: 'SOS Rescue',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(
                Icons.notifications_rounded,
                color: Color(0xFF087CF0),
              ),
              label: 'Alerts',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(
                Icons.person_rounded,
                color: Color(0xFF087CF0),
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
