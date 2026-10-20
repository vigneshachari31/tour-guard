import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _map = MapController();
  int _tab = 0;
  bool _loading = true;
  String? _error;
  List<AdminSosEvent> _events = [];
  List<AdminHazard> _hazards = [];
  AdminSosEvent? _selected;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        ApiService.instance.getAdminSosEvents(),
        ApiService.instance.getAdminHazards(),
      ]);
      if (!mounted) return;
      setState(() {
        _events = result[0] as List<AdminSosEvent>;
        _hazards = result[1] as List<AdminHazard>;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _focus(AdminSosEvent event) {
    setState(() => _selected = event);
    _map.move(LatLng(event.latitude, event.longitude), 15);
  }

  Future<void> _setStatus(AdminSosEvent event, String status) async {
    try {
      final changed = await ApiService.instance.updateAdminSosStatus(
        event.id,
        status,
      );
      if (!mounted) return;
      setState(() {
        _events = _events
            .map((item) => item.id == changed.id ? changed : item)
            .toList();
        _selected = changed;
      });
    } on ApiException catch (error) {
      _snack(error.message, error: true);
    }
  }

  void _snack(String text, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? Colors.red : const Color(0xFF087CF0),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tour Guard - Rescue Command'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: _menu()),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 245,
              child: Material(
                color: const Color(0xFF132A4F),
                child: _menu(dark: true),
              ),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _menu({bool dark = false}) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(22),
          child: Text(
            'RESCUE COMMAND',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: dark ? Colors.white : const Color(0xFF132A4F),
            ),
          ),
        ),
        _tabButton(0, Icons.sos_rounded, 'Live SOS Desk', dark),
        _tabButton(1, Icons.layers_rounded, 'Hazard Zone Manager', dark),
        _tabButton(2, Icons.analytics_rounded, 'System Analytics', dark),
      ],
    ),
  );

  Widget _tabButton(int tab, IconData icon, String title, bool dark) =>
      ListTile(
        selected: _tab == tab,
        selectedTileColor: dark ? Colors.white24 : null,
        leading: Icon(
          icon,
          color: dark ? Colors.white : const Color(0xFF087CF0),
        ),
        title: Text(title, style: TextStyle(color: dark ? Colors.white : null)),
        onTap: () {
          setState(() => _tab = tab);
          Navigator.maybePop(context);
        },
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to load command portal: $_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: switch (_tab) {
        0 => _desk(),
        1 => _hazardsTable(),
        _ => _analytics(),
      },
    );
  }

  Widget _desk() => LayoutBuilder(
    builder: (context, box) {
      final feed = _feed();
      final map = _mapPanel();
      return box.maxWidth >= 850
          ? Row(
              children: [
                SizedBox(width: 370, child: feed),
                const SizedBox(width: 16),
                Expanded(child: map),
              ],
            )
          : Column(
              children: [
                Expanded(child: feed),
                const SizedBox(height: 16),
                Expanded(child: map),
              ],
            );
    },
  );

  Widget _feed() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('LIVE SOS DESK', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(
          children: _events.map((event) {
            final active = event.status == 'active';
            return Card(
              color: active ? const Color(0xFFFFECEC) : null,
              child: ListTile(
                onTap: () => _focus(event),
                leading: Icon(
                  Icons.sos_rounded,
                  color: active ? Colors.red : Colors.orange,
                ),
                title: Text(
                  event.fullName?.isNotEmpty == true
                      ? event.fullName!
                      : event.touristId,
                ),
                subtitle: Text(
                  '${event.status.toUpperCase()} - ${event.createdAt.toLocal()}',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          }).toList(),
        ),
      ),
    ],
  );

  Widget _mapPanel() => Card(
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: const MapOptions(
            initialCenter: LatLng(19.076, 72.8777),
            initialZoom: 10,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.travel_risk_app',
            ),
            PolygonLayer(
              polygons: _hazards
                  .where(
                    (hazard) =>
                        hazard.isPolygon &&
                        hazard.polygonCoordinates.isNotEmpty,
                  )
                  .map(
                    (hazard) => Polygon(
                      points: hazard.polygonCoordinates.first
                          .map((point) => LatLng(point[1], point[0]))
                          .toList(),
                      color: Colors.orange.withValues(alpha: .25),
                      borderColor: Colors.orange,
                      borderStrokeWidth: 2,
                    ),
                  )
                  .toList(),
            ),
            MarkerLayer(
              markers: [
                ..._events.map(
                  (event) => Marker(
                    point: LatLng(event.latitude, event.longitude),
                    width: 44,
                    height: 44,
                    child: IconButton(
                      onPressed: () => _focus(event),
                      icon: Icon(
                        Icons.location_on,
                        color: event.status == 'active'
                            ? Colors.red
                            : Colors.orange,
                        size: 36,
                      ),
                    ),
                  ),
                ),
                ..._hazards
                    .where(
                      (hazard) =>
                          hazard.isPoint && hazard.pointCoordinates != null,
                    )
                    .map(
                      (hazard) => Marker(
                        point: LatLng(
                          hazard.pointCoordinates![1],
                          hazard.pointCoordinates![0],
                        ),
                        width: 34,
                        height: 34,
                        child: Tooltip(
                          message: '${hazard.name} (${hazard.severity}/5)',
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.deepOrange,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ],
        ),
        if (_selected != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _details(_selected!),
          ),
      ],
    ),
  );

  Widget _details(AdminSosEvent event) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.fullName ?? event.touristId,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Phone: ${event.phoneNumber ?? 'Not supplied'} | Blood: ${event.bloodGroup ?? 'Not supplied'}',
          ),
          Text('Emergency: ${event.emergencyContact ?? 'Not supplied'}'),
          if (event.medicalNotes?.isNotEmpty == true)
            Text('Medical: ${event.medicalNotes}'),
          Row(
            children: [
              TextButton(
                onPressed: () => _setStatus(event, 'acknowledged'),
                child: const Text('ACKNOWLEDGE'),
              ),
              TextButton(
                onPressed: () => _setStatus(event, 'resolved'),
                child: const Text('MARK RESOLVED'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _hazardsTable() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            'HAZARD ZONE MANAGER',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _showHazardDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add official zone'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Severity')),
              DataColumn(label: Text('Source')),
              DataColumn(label: Text('Action')),
            ],
            rows: _hazards
                .map(
                  (hazard) => DataRow(
                    cells: [
                      DataCell(Text(hazard.name)),
                      DataCell(
                        Text('${hazard.hazardType} (${hazard.geometryType})'),
                      ),
                      DataCell(Text('${hazard.severity}/5')),
                      DataCell(Text(hazard.source)),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ApiService.instance.deactivateAdminHazard(
                              hazard.id,
                            );
                            _reload();
                          },
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    ],
  );

  Widget _analytics() {
    final open = _events.where((event) => event.status != 'resolved').length;
    return Center(
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _metric('Open SOS', '$open', Colors.red),
          _metric(
            'Resolved SOS',
            '${_events.where((event) => event.status == 'resolved').length}',
            Colors.green,
          ),
          _metric('Active official zones', '${_hazards.length}', Colors.orange),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Card(
    child: SizedBox(
      width: 210,
      height: 130,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );

  Future<void> _showHazardDialog() async {
    final name = TextEditingController();
    final type = TextEditingController();
    final source = TextEditingController();
    final coordinates = TextEditingController(
      text: '72.87,19.07;72.88,19.07;72.88,19.08;72.87,19.07',
    );
    var severity = 3;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add verified hazard polygon'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: type,
                  decoration: const InputDecoration(labelText: 'Hazard type'),
                ),
                TextField(
                  controller: source,
                  decoration: const InputDecoration(
                    labelText: 'Official source URL/name',
                  ),
                ),
                TextField(
                  controller: coordinates,
                  decoration: const InputDecoration(
                    labelText: 'longitude,latitude; ... (closed polygon)',
                  ),
                ),
                DropdownButton<int>(
                  value: severity,
                  items: List.generate(
                    5,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('Severity ${index + 1}'),
                    ),
                  ),
                  onChanged: (value) => setDialogState(() => severity = value!),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final points = coordinates.text
                    .split(';')
                    .map((entry) => entry.split(','))
                    .map(
                      (pair) => [
                        double.parse(pair[0].trim()),
                        double.parse(pair[1].trim()),
                      ],
                    )
                    .toList();
                await ApiService.instance.createAdminHazard(
                  name: name.text,
                  hazardType: type.text,
                  severity: severity,
                  source: source.text,
                  coordinates: [points],
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _reload();
              } catch (_) {
                _snack(
                  'Use a closed longitude,latitude polygon and complete all fields.',
                  error: true,
                );
              }
            },
            child: const Text('Save official zone'),
          ),
        ],
      ),
    );
  }
}
