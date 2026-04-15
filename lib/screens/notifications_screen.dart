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

  // CUSTOM PROJECT COLOR
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  // ── Multi-select state ──────────────────────────────────────────────────────
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
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
        title: const Text('Clear All Notifications'),
        content:
            const Text('Are you sure you want to delete all notifications permanently?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('Delete All', style: TextStyle(color: customRed))),
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
              child: Text('Delete', style: TextStyle(color: customRed))),
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
          .snapshots(),
      builder: (context, snapshot) {
        final rawDocs = snapshot.data?.docs ?? [];
        final docs = List<QueryDocumentSnapshot>.from(rawDocs)
          ..sort((a, b) {
            final aTs = (a.data() as Map)['timestamp'] as Timestamp?;
            final bTs = (b.data() as Map)['timestamp'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });
        final allSelected =
            docs.isNotEmpty && _selectedIds.length == docs.length;

        return Scaffold(
          backgroundColor: Colors.white,
          // Conditionally show AppBar ONLY during Selection Mode
          appBar: _isSelectionMode
              ? _buildSelectionAppBar(docs, allSelected, context)
              : AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  leading: Navigator.of(context).canPop()
                      ? IconButton(
                          icon: Icon(Icons.arrow_back, color: customRed),
                          onPressed: () => Navigator.pop(context),
                        )
                      : null,
                  actions: [
                    IconButton(
                      icon: Icon(Icons.done_all_rounded, color: customRed),
                      tooltip: 'Mark all as read',
                      onPressed: () => _markAllAsRead(_userId!),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_sweep_outlined, color: customRed),
                      tooltip: 'Delete all',
                      onPressed: () => _confirmDeleteAll(context, _userId!),
                    ),
                  ],
                ),

          body: () {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return FullScreenError(
                message: 'Could not load notifications.',
                onRetry: () => setState(() {}),
              );
            }
            if (docs.isEmpty) {
              return const EmptyStateWidget(
                icon: Icons.notifications_off_outlined,
                title: 'Clean Slate!',
                subtitle: 'No new notifications right now.\nCheck back later for updates.',
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── HEADER ──────────────────────────
                if (!_isSelectionMode)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Recent Updates", 
                        style: TextStyle(color: Colors.grey, fontSize: 16)),
                      Text("Notice Board", 
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ],
                  ),
                ),

                if (!_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: customRed.withOpacity(0.6)),
                        const SizedBox(width: 6),
                        Text('Long-press to manage notifications',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),

                // ── List ────────────────────────────────────────────────────
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  // Selection AppBar (Only visible when items are selected)
  AppBar _buildSelectionAppBar(
      List<QueryDocumentSnapshot> docs, bool allSelected, BuildContext ctx) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: _exitSelectionMode,
      ),
      title: Text('${_selectedIds.length} Selected', style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: customRed,
      foregroundColor: Colors.white,
      elevation: 4,
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect_rounded : Icons.select_all_rounded),
          onPressed: allSelected ? _deselectAll : () => _selectAll(docs),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: _selectedIds.isEmpty ? null : () => _confirmDeleteSelected(ctx),
        ),
      ],
    );
  }

  Widget _buildNotificationTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final isRead = data['read'] ?? false;
    final isSelected = _selectedIds.contains(doc.id);
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final timeStr = timestamp != null
        ? DateFormat('MMM d, h:mm a').format(timestamp)
        : 'Just now';

    return Dismissible(
      key: Key(doc.id),
      direction: _isSelectionMode ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: customRed,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Notification'),
            content: const Text('Discard this update?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: customRed))),
            ],
          ),
        );
        return confirmed ?? false;
      },
      onDismissed: (_) => _deleteOne(doc.id),
      child: GestureDetector(
        onLongPress: () { if (!_isSelectionMode) _enterSelectionMode(doc.id); },
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(doc.id);
          } else if (!isRead) {
            FirebaseFirestore.instance.collection('notifications').doc(doc.id).update({'read': true});
            NotificationService().updateAppBadge();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? customRed.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? customRed : (isRead ? Colors.grey[100]! : customRed.withOpacity(0.1)),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isSelected ? 0.05 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _isSelectionMode
                ? Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? customRed : Colors.grey)
                : Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isRead ? Colors.grey[100] : customRed.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_getIconForType(data['type']),
                        color: isRead ? Colors.grey[500] : customRed, size: 22),
                  ),
            title: Text(
              data['title'] ?? 'Notification',
              style: TextStyle(
                fontWeight: isRead ? FontWeight.normal : FontWeight.bold, // Unread is bold
                fontSize: 16,
                color: isRead ? Colors.black45 : Colors.black87, // Read is dim black
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(data['body'] ?? '', 
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold, // Message also bold if unread
                      color: isRead ? Colors.black38 : Colors.black87, // Dimmer black for read body
                      height: 1.3,
                    )),
                const SizedBox(height: 8),
                Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500)),
              ],
            ),
            trailing: !_isSelectionMode && !isRead
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: customRed, shape: BoxShape.circle),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'payment_reminder': return Icons.priority_high_rounded;
      case 'payment_verified': return Icons.verified_rounded;
      case 'payment_rejected': return Icons.report_problem_rounded;
      case 'account_approved': return Icons.face_retouching_natural_rounded;
      case 'new_registration': return Icons.person_add_alt_1_rounded;
      case 'new_payment': return Icons.account_balance_wallet_rounded;
      default: return Icons.notifications_rounded;
    }
  }
}