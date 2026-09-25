import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';
import '../../services/complaint_service.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';

/// Admin-only route (separate from the Reports tab, which is for reporting
/// *other users*): every complaint filed through "Report an issue", grouped
/// by the person who filed it, with their contact email and a way to
/// resolve each one.
class ComplaintsPage extends StatefulWidget {
  const ComplaintsPage({super.key});

  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  String _statusFilter = 'open';
  bool _groupByUser = true;

  static const _statusOptions = [
    ComplaintService.statusOpen,
    ComplaintService.statusInProgress,
    ComplaintService.statusResolved,
    'all',
  ];

  String _statusLabel(String status) {
    switch (status) {
      case ComplaintService.statusOpen:
        return 'Open';
      case ComplaintService.statusInProgress:
        return 'In progress';
      case ComplaintService.statusResolved:
        return 'Resolved';
      default:
        return 'All';
    }
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case ComplaintService.statusResolved:
        return context.sw.success;
      case ComplaintService.statusInProgress:
        return context.sw.give;
      default:
        return context.sw.get;
    }
  }

  Future<void> _resolve(String id, {String status = ComplaintService.statusResolved}) async {
    final noteController = TextEditingController();
    if (status == ComplaintService.statusResolved) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resolve this complaint?'),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Resolution note (optional)',
              hintText: 'What was done about it?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Mark resolved'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final ok = await ComplaintService.instance.updateStatus(
      id,
      status,
      resolutionNote: noteController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Complaint updated.' : 'Could not update the complaint.'),
        backgroundColor: ok ? context.sw.give : Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.sw.bg,
      appBar: AppBar(
        title: const Text('Complaints'),
        backgroundColor: context.sw.bg,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _groupByUser ? 'Show as flat list' : 'Group by user',
            icon: Icon(_groupByUser ? Icons.view_list : Icons.people_alt_outlined),
            onPressed: () => setState(() => _groupByUser = !_groupByUser),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              children: _statusOptions.map((status) {
                final selected = _statusFilter == status;
                return ChoiceChip(
                  label: Text(_statusLabel(status)),
                  selected: selected,
                  onSelected: (_) => setState(() => _statusFilter = status),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: ComplaintService.instance.complaintsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                var docs = snapshot.data?.docs ?? const [];
                if (_statusFilter != 'all') {
                  docs = docs
                      .where((d) =>
                          ((d.data() as Map<String, dynamic>)['status'] ?? 'open') ==
                          _statusFilter)
                      .toList();
                }
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No ${_statusFilter == 'all' ? '' : _statusLabel(_statusFilter).toLowerCase() + ' '}complaints.',
                        style: TextStyle(color: context.sw.textMuted),
                      ),
                    ),
                  );
                }
                if (!_groupByUser) {
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: docs.length,
                    itemBuilder: (context, i) => _complaintCard(docs[i]),
                  );
                }

                final grouped = <String, List<QueryDocumentSnapshot>>{};
                for (final doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final key = (data['userEmail'] as String?)?.isNotEmpty == true
                      ? data['userEmail'] as String
                      : (data['userId'] ?? 'unknown').toString();
                  grouped.putIfAbsent(key, () => []).add(doc);
                }
                final keys = grouped.keys.toList()
                  ..sort((a, b) => grouped[b]!.length.compareTo(grouped[a]!.length));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: keys.length,
                  itemBuilder: (context, i) {
                    final key = keys[i];
                    final items = grouped[key]!;
                    final first = items.first.data() as Map<String, dynamic>;
                    return SurfaceCard(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: context.sw.give.withValues(alpha: 0.13),
                                  child: Icon(Icons.person, size: 18, color: context.sw.give),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text((first['userName'] ?? 'Unknown user').toString(),
                                          style: const TextStyle(fontWeight: FontWeight.bold)),
                                      if ((first['userEmail'] as String? ?? '').isNotEmpty)
                                        Row(
                                          children: [
                                            Icon(Icons.email_outlined,
                                                size: 12, color: context.sw.textMuted),
                                            const SizedBox(width: 4),
                                            Text(first['userEmail'] as String,
                                                style: TextStyle(
                                                    fontSize: 12, color: context.sw.textMuted)),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                TintTag('${items.length}', color: context.sw.get),
                              ],
                            ),
                            const Divider(height: 20),
                            ...items.map(_complaintTile),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _complaintCard(QueryDocumentSnapshot doc) {
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _complaintTile(doc),
      ),
    );
  }

  Widget _complaintTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final subject = (data['subject'] ?? 'No subject').toString();
    final description = (data['description'] ?? '').toString();
    final status = (data['status'] ?? 'open').toString();
    final userName = (data['userName'] ?? 'Unknown user').toString();
    final userEmail = (data['userEmail'] ?? '').toString();
    final createdAt = data['createdAt'] as Timestamp?;
    final resolutionNote = (data['resolutionNote'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(subject,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ),
              TintTag(_statusLabel(status), color: _statusColor(context, status)),
            ],
          ),
          if (!_groupByUser) ...[
            const SizedBox(height: 4),
            Text(
              userEmail.isNotEmpty ? '$userName · $userEmail' : userName,
              style: TextStyle(fontSize: 12, color: context.sw.textMuted),
            ),
          ],
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(fontSize: 13.5)),
          if (resolutionNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Resolution: $resolutionNote',
                style: TextStyle(
                    fontSize: 12.5, fontStyle: FontStyle.italic, color: context.sw.textMuted)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  createdAt != null ? DateFormat.yMMMd().add_jm().format(createdAt.toDate()) : '',
                  style: TextStyle(fontSize: 11, color: context.sw.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Wrap (not Row+Spacer) so the two buttons drop to a second
              // line instead of overflowing when the card is narrow - a
              // plain Row here overflowed by ~60px on-device (confirmed via
              // live QA) once both buttons and the date competed for space.
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (status != ComplaintService.statusInProgress &&
                      status != ComplaintService.statusResolved)
                    TextButton(
                      onPressed: () => _resolve(doc.id, status: ComplaintService.statusInProgress),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('In progress'),
                    ),
                  if (status != ComplaintService.statusResolved)
                    ElevatedButton(
                      onPressed: () => _resolve(doc.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.sw.give,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Resolve'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
