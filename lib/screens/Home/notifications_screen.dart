import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/models/notification_model.dart';
import 'package:intl/intl.dart';
import 'package:attendus/screens/Home/notification_settings_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/screens/Messaging/chat_screen.dart';
import 'package:attendus/screens/Groups/group_profile_screen_v2.dart';
import 'package:attendus/screens/Events/event_feedback_management_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseMessagingHelper _messagingHelper = FirebaseMessagingHelper();
  bool _isLoading = true;

  // Infinite scroll state
  final ScrollController _scrollController = ScrollController();
  final List<NotificationModel> _items = [];
  final Set<String> _ids = <String>{};
  DocumentSnapshot? _lastDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  StreamSubscription<QuerySnapshot>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(() {
      if (!_hasMore || _isLoadingMore) return;
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _items.clear();
      _ids.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    final page = await _messagingHelper.fetchUserNotificationsPage(
      pageSize: 20,
    );
    setState(() {
      _items.addAll(page.items);
      _ids.addAll(page.items.map((e) => e.id));
      _lastDoc = page.lastDoc;
      _hasMore = page.items.length >= 20;
      _isLoading = false;
    });
    _startRealtimeTopListener();
  }

  void _startRealtimeTopListener() {
    _realtimeSub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _realtimeSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final model = NotificationModel.fromFirestore(change.doc);
              if (!_ids.contains(model.id)) {
                setState(() {
                  _items.insert(0, model);
                  _ids.add(model.id);
                });
              }
            } else if (change.type == DocumentChangeType.modified) {
              final model = NotificationModel.fromFirestore(change.doc);
              final index = _items.indexWhere((n) => n.id == model.id);
              if (index != -1) {
                setState(() {
                  _items[index] = model;
                });
              }
            } else if (change.type == DocumentChangeType.removed) {
              final removedId = change.doc.id;
              final index = _items.indexWhere((n) => n.id == removedId);
              if (index != -1) {
                setState(() {
                  _items.removeAt(index);
                  _ids.remove(removedId);
                });
              }
            }
          }
        });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final page = await _messagingHelper.fetchUserNotificationsPage(
      startAfter: _lastDoc,
      pageSize: 20,
    );
    setState(() {
      for (final it in page.items) {
        if (_ids.add(it.id)) {
          _items.add(it);
        }
      }
      _lastDoc = page.lastDoc;
      _hasMore = page.items.length >= 20;
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all read',
            onPressed: () async {
              await _messagingHelper.markAllNotificationsAsRead();
              await _loadInitial();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear all',
            onPressed: () async {
              await _messagingHelper.clearAllNotifications();
              await _loadInitial();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsScreen(),
                ),
              );
            },
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInitial,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  if (_items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    ),
                  if (_items.isNotEmpty)
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _buildNotificationTile(_items[index]);
                      }, childCount: _items.length + (_hasMore ? 1 : 0)),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              color: Color(0xFF667EEA),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Recent',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'All caught up!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'re up to date with all your notifications',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const NotificationSettingsScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF667EEA).withAlpha(76),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.settings_outlined,
                          size: 16,
                          color: Color(0xFF667EEA),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Manage notifications',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF667EEA),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(NotificationModel notification) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (!notification.isRead) {
              _messagingHelper.markNotificationAsRead(notification.id);
            }
            _handleNotificationTap(notification);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getNotificationColor(
                      notification.type,
                    ).withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getNotificationIcon(notification.type),
                    color: _getNotificationColor(notification.type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontWeight: notification.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                fontSize: 16,
                                color: notification.isRead
                                    ? Colors.grey[600]
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          if (!notification.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF667EEA),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 14,
                          color: notification.isRead
                              ? Colors.grey[500]
                              : Colors.grey[700],
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'MMM dd, yyyy • HH:mm',
                            ).format(notification.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                          ),
                          const Spacer(),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: 16,
                              color: Colors.grey[400],
                            ),
                            onSelected: (value) {
                              if (value == 'mark_read') {
                                _messagingHelper.markNotificationAsRead(
                                  notification.id,
                                );
                              } else if (value == 'delete') {
                                _messagingHelper.deleteNotification(
                                  notification.id,
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              if (!notification.isRead)
                                const PopupMenuItem(
                                  value: 'mark_read',
                                  child: Row(
                                    children: [
                                      Icon(Icons.check, size: 18),
                                      SizedBox(width: 8),
                                      Text('Mark as read'),
                                    ],
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'event_reminder':
        return Colors.orange;
      case 'event_changes':
        return Colors.deepOrange;
      case 'geofence_checkin':
        return Colors.teal;
      case 'new_event':
        return Colors.green;
      case 'ticket_update':
        return Colors.blue;
      case 'message_mention':
        return Colors.purple;
      case 'org_update':
        return Colors.indigo;
      case 'organizer_feedback':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'event_reminder':
        return Icons.event;
      case 'event_changes':
        return Icons.event_repeat;
      case 'geofence_checkin':
        return Icons.my_location;
      case 'new_event':
        return Icons.add_circle;
      case 'ticket_update':
        return Icons.confirmation_number;
      case 'message_mention':
        return Icons.alternate_email;
      case 'org_update':
        return Icons.account_tree;
      case 'organizer_feedback':
        return Icons.feedback_outlined;
      default:
        return Icons.notifications;
    }
  }

  void _handleNotificationTap(NotificationModel notification) async {
    switch (notification.type) {
      case 'event_reminder':
      case 'event_changes':
      case 'geofence_checkin':
        await _openEvent(notification.eventId);
        break;
      case 'new_event':
        break;
      case 'ticket_update':
        break;
      case 'message_mention':
        final conversationId = notification.data?['conversationId'] as String?;
        if (conversationId != null && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(conversationId: conversationId),
            ),
          );
        }
        break;
      case 'org_update':
        final orgId = notification.data?['organizationId'] as String?;
        if (orgId != null && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupProfileScreenV2(organizationId: orgId),
            ),
          );
        }
        break;
      case 'organizer_feedback':
        await _openFeedbackManagement(notification.eventId);
        break;
      case 'event_feedback':
        break;
      default:
        break;
    }
  }

  Future<void> _openEvent(String? eventId) async {
    if (eventId == null) return;
    final doc = await FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .doc(eventId)
        .get();
    if (!doc.exists) return;
    final event = EventModel.fromJson(doc);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SingleEventScreen(eventModel: event)),
    );
  }

  Future<void> _openFeedbackManagement(String? eventId) async {
    if (eventId == null) return;
    final doc = await FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .doc(eventId)
        .get();
    if (!doc.exists) return;
    final event = EventModel.fromJson(doc);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventFeedbackManagementScreen(eventModel: event),
      ),
    );
  }
}
