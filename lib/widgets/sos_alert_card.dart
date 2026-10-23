import 'package:flutter/material.dart';

class SosAlertCard extends StatelessWidget {
  final Map<String, dynamic> event;
  const SosAlertCard({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final workflow = event['workflow_status']?.toString().toUpperCase();
    final status = event['status']?.toString().toLowerCase();
    final label = workflow == 'CANCELLED' ? 'Cancelled'
        : workflow == 'RESOLVED' || status == 'resolved' ? 'Resolved'
        : workflow == 'IN_PROGRESS' || status == 'dispatched' ? 'In progress'
        : status == 'acknowledged' ? 'Acknowledged'
        : workflow == 'OPEN' || status == 'active' ? 'Open' : 'Status unavailable';
    final closed = label == 'Resolved' || label == 'Cancelled';
    final color = closed ? const Color(0xFF64748B) : const Color(0xFFDC2626);
    final timestamp = DateTime.tryParse(event['created_at']?.toString() ?? '')?.toLocal();
    final locale = MaterialLocalizations.of(context);
    final when = timestamp == null ? 'Time unavailable'
        : '${locale.formatMediumDate(timestamp)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(timestamp))}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: ExpansionTile(
        shape: const Border(), collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: .09), child: Icon(closed ? Icons.history : Icons.sos, color: color, size: 22)),
        title: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('SOS #${event['id']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
        subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text(when, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Divider(),
          Text('Recorded location: ${event['latitude']}, ${event['longitude']}'),
          const SizedBox(height: 4),
          Text('Tourist ID: ${event['tourist_id'] ?? 'Unavailable'}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
        ]))],
      ),
    );
  }
}
