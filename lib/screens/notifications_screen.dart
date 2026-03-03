import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/ux_widgets.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final String? _userId;

  // ── Multi-select state ──────────────────────────────────────────────────────
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    // Clear system badge count when user opens the notifications screen
    NotificationService().clearAppBadge();
  }

  // ── Selection helpers ───────────────────────────────────────────────────────

  void _enterSelectionMode(String docId) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(docId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(docId);
      }
    });
  }

  void _selectAll(List<QueryDocumentSnapshot> docs) {
    setState(() {
      _selectedIds.addAll(docs.map((d) => d.id));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  // ── Firestore actions ───────────────────────────────────────────────────────

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    final batch = FirebaseFirestore.instance.batch();
    for (final id in ids) {
      batch.delete(
          FirebaseFirestore.instance.collection('notifications').doc(id));
    }
    await batch.commit();
    // update launcher badge
    NotificationService().updateAppBadge();
  }

  Future<void> _deleteOne(String docId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(docId)
        .delete();
    NotificationService().updateAppBadge();
  }

  Future<void> _markAllAsRead(String userId) async {
    final batch = FirebaseFirestore.instance.batch();
    final snapshot = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
    NotificationService().updateAppBadge();
  }

  Future<void> _deleteAllNotifications(String userId) async {
    final batch = FirebaseFirestore.instance.batch();
    final snapshot = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .get();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    NotificationService().updateAppBadge();
  }

  Future<void> _confirmDeleteAll(BuildContext context, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Notifications'),
        content:
            const Text('This will permanently delete all your notifications.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Delete All', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) await _deleteAllNotifications(userId);
  }

  Future<void> _confirmDeleteSelected(BuildContext context) async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected'),
        content: Text(
            'Delete $count selected notification${count > 1 ? 's' : ''}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) await _deleteSelected();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view notifications')),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: _userId)
          // No orderBy here — we sort client-side so null-timestamp docs
          // (e.g. fresh serverTimestamp() writes) are NOT silently excluded.
          .snapshots(),
      builder: (context, snapshot) {
        // Sort client-side: newest first, null timestamps go last
        final rawDocs = snapshot.data?.docs ?? [];
        final docs = List<QueryDocumentSnapshot>.from(rawDocs)
          ..sort((a, b) {
            final aTs = (a.data() as Map)['timestamp'] as Timestamp?;
            final bTs = (b.data() as Map)['timestamp'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs); // newest first
          });
        final allSelected =
            docs.isNotEmpty && _selectedIds.length == docs.length;

        return Scaffold(
          // ── AppBar ─────────────────────────────────────────────────────────
          appBar: _isSelectionMode
              ? _buildSelectionAppBar(docs, allSelected, context)
              : _buildNormalAppBar(context),

          // ── Body ───────────────────────────────────────────────────────────
          body: () {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return FullScreenError(
                message: 'Could not load notifications.\nCheck your connection and try again.',
                onRetry: () => setState(() {}),
              );
            }
            if (docs.isEmpty) {
              return const EmptyStateWidget(
                icon: Icons.notifications_none_rounded,
                title: 'No notifications yet',
                subtitle: 'You\'ll see payment updates\nand important announcements here.',
              );
            }

            return Column(
              children: [
                // ── Selection bar hint ──────────────────────────────────────
                if (!_isSelectionMode)
                  Container(
                    color: Colors.indigo[50],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.touch_app,
                            size: 16, color: Colors.indigo[300]),
                        const SizedBox(width: 6),
                        Text(
                          'Long-press to select & delete',
                          style: TextStyle(
                              fontSize: 12, color: Colors.indigo[400]),
                        ),
                      ],
                    ),
                  ),

                // ── List ────────────────────────────────────────────────────
                Expanded(
                  child: ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) =>
                        _buildNotificationTile(docs[index]),
                  ),
                ),
              ],
            );
          }(),
        );
      },
    );
  }

  // ── Normal AppBar ───────────────────────────────────────────────────────────
  AppBar _buildNormalAppBar(BuildContext context) {
    return AppBar(
      title: const Text('Notifications'),
      backgroundColor: Colors.indigo,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.done_all),
          tooltip: 'Mark all as read',
          onPressed: () => _markAllAsRead(_userId!),
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep_outlined),
          tooltip: 'Delete all',
          onPressed: () => _confirmDeleteAll(context, _userId!),
        ),
      ],
    );
  }

  // ── Selection AppBar ────────────────────────────────────────────────────────
  AppBar _buildSelectionAppBar(
      List<QueryDocumentSnapshot> docs, bool allSelected, BuildContext ctx) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
        tooltip: 'Cancel selection',
      ),
      title: Text('${_selectedIds.length} selected'),
      backgroundColor: Colors.indigo[800],
      foregroundColor: Colors.white,
      actions: [
        // Select All / Deselect All toggle
        IconButton(
          icon: Icon(
            allSelected ? Icons.deselect : Icons.select_all,
            color: Colors.white,
          ),
          tooltip: allSelected ? 'Deselect all' : 'Select all',
          onPressed: allSelected ? _deselectAll : () => _selectAll(docs),
        ),
        // Delete selected
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.redAccent),
          tooltip: 'Delete selected',
          onPressed: _selectedIds.isEmpty
              ? null
              : () => _confirmDeleteSelected(ctx),
        ),
      ],
    );
  }

  // ── Single notification tile ────────────────────────────────────────────────
  Widget _buildNotificationTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final isRead = data['read'] ?? false;
    final isSelected = _selectedIds.contains(doc.id);
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final timeStr = timestamp != null
        ? DateFormat('MMM d, h:mm a').format(timestamp)
        : '';

    return Dismissible(
      key: Key(doc.id),
      direction: _isSelectionMode
          ? DismissDirection.none // disable swipe in selection mode
          : DismissDirection.endToStart,
      background: Container(
        color: Colors.red[700],
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white),
            SizedBox(height: 4),
            Text('Delete',
                style: TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Notification'),
            content: const Text('Delete this notification?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete',
                      style: TextStyle(color: Colors.red))),
            ],
          ),
        );
        return confirmed ?? false;
      },
      onDismissed: (_) => _deleteOne(doc.id),
      child: GestureDetector(
        onLongPress: () {
          if (!_isSelectionMode) _enterSelectionMode(doc.id);
        },
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(doc.id);
          } else {
            // Mark as read on tap
            if (!isRead) {
              FirebaseFirestore.instance
                  .collection('notifications')
                  .doc(doc.id)
                  .update({'read': true});
              // badge should reflect new unread count
              NotificationService().updateAppBadge();
            }
          }
        },

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          color: isSelected
              ? Colors.indigo.withOpacity(0.12)
              : isRead
                  ? Colors.white
                  : Colors.blue[50],
          child: ListTile(
            // ── Leading: checkbox (select mode) or icon (normal) ──────────
            leading: _isSelectionMode
                ? AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      key: ValueKey(isSelected),
                      color: isSelected ? Colors.indigo : Colors.grey,
                      size: 26,
                    ),
                  )
                : CircleAvatar(
                    backgroundColor:
                        isRead ? Colors.grey[300] : Colors.indigo,
                    child: Icon(
                      _getIconForType(data['type']),
                      color: isRead ? Colors.grey[600] : Colors.white,
                    ),
                  ),

            title: Text(
              data['title'] ?? 'Notification',
              style: TextStyle(
                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(data['body'] ?? ''),
                const SizedBox(height: 4),
                Text(timeStr,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),

            // ── Trailing: unread dot (normal mode only) ───────────────────
            trailing: _isSelectionMode
                ? null
                : !isRead
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.indigo,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'payment_reminder':
        return Icons.payment;
      case 'payment_verified':
        return Icons.check_circle;
      case 'payment_rejected':
        return Icons.error;
      case 'account_approved':
        return Icons.verified_user;
      case 'new_registration':
        return Icons.person_add;
      case 'new_payment':
        return Icons.upload_file;
      default:
        return Icons.notifications;
    }
  }
}
