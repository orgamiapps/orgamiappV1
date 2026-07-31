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
import 'package:attendus/widgets/attendus_design_system.dart';

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
    final entries = _buildNotificationEntries();
    return Scaffold(
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_outlined, size: 24),
            const SizedBox(width: 8),
            const Text('Notifications'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Notification settings',
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
      ),
      body: _isLoading
          ? const AttendUsLoadingState(label: 'Loading notifications...')
          : RefreshIndicator(
              onRefresh: _loadInitial,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: AttendUsPageSection(
                          title: 'Activity center',
                          subtitle:
                              'Messages, event updates, tickets, and group activity.',
                          icon: Icons.notifications_active_outlined,
                          actions: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const NotificationSettingsScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.tune_outlined),
                              label: const Text('Settings'),
                            ),
                          ],
                          child: const SizedBox.shrink(),
                        ),
                      ),
                      if (_items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(),
                        ),
                      if (_items.isNotEmpty)
                        SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            if (index >= entries.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final entry = entries[index];
                            if (entry is String) {
                              return _buildGroupHeader(entry);
                            }
                            return _buildNotificationTile(
                              entry as NotificationModel,
                            );
                          }, childCount: entries.length + (_hasMore ? 1 : 0)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return AttendUsEmptyState(
      icon: Icons.notifications_none_outlined,
      title: 'All caught up',
      message:
          'New messages, event updates, tickets, and group activity will appear here.',
      action: AttendUsButton.secondary(
        label: 'Notification settings',
        icon: Icons.tune_outlined,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NotificationSettingsScreen(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationTile(NotificationModel notification) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: AttendUsListTile(
        selected: !notification.isRead,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _getNotificationColor(
                  notification.type,
                ).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getNotificationIcon(notification.type),
                color: _getNotificationColor(notification.type),
                size: 22,
              ),
            ),
            if (!notification.isRead)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.surface),
                  ),
                ),
              ),
          ],
        ),
        title: notification.title,
        subtitle:
            '${notification.body} • ${DateFormat('MMM d, h:mm a').format(notification.createdAt)}',
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz),
          tooltip: 'Notification actions',
          onSelected: (value) {
            if (value == 'mark_read') {
              _messagingHelper.markNotificationAsRead(notification.id);
            } else if (value == 'delete') {
              _messagingHelper.deleteNotification(notification.id);
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
                  Icon(Icons.delete_outline, size: 18),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
        onTap: () {
          if (!notification.isRead) {
            _messagingHelper.markNotificationAsRead(notification.id);
          }
          _handleNotificationTap(notification);
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildNotificationTileLegacy(NotificationModel notification) {
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
                              'MMM dd, yyyy • h:mm a',
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

  Widget _buildGroupHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  List<Object> _buildNotificationEntries() {
    final entries = <Object>[];
    String? currentGroup;
    for (final notification in _items) {
      final group = _notificationGroupLabel(notification);
      if (group != currentGroup) {
        entries.add(group);
        currentGroup = group;
      }
      entries.add(notification);
    }
    return entries;
  }

  String _notificationGroupLabel(NotificationModel notification) {
    if (!notification.isRead) return 'Unread';
    final now = DateTime.now();
    final created = notification.createdAt;
    final today = DateTime(now.year, now.month, now.day);
    final createdDay = DateTime(created.year, created.month, created.day);
    if (createdDay == today) return 'Today';
    if (today.difference(createdDay).inDays <= 7) return 'This week';
    return 'Earlier';
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
        return const Color(0xFF667EEA);
      case 'group_event':
        return const Color(0xFF667EEA);
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
      case 'group_event':
        return Icons.group_add;
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
      case 'group_event':
        await _openEvent(notification.eventId);
        break;
      case 'new_event':
        await _openEvent(notification.eventId);
        break;
      case 'ticket_update':
        await _openEvent(notification.eventId);
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
