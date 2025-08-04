import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String
  type; // 'event_reminder', 'new_event', 'ticket_update', 'event_feedback', 'general'
  final String? eventId;
  final String? eventTitle;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic>? data;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.eventId,
    this.eventTitle,
    required this.createdAt,
    this.isRead = false,
    this.data,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      type: data['type'] ?? 'general',
      eventId: data['eventId'],
      eventTitle: data['eventTitle'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isRead: data['isRead'] ?? false,
      data: data['data'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'body': body,
      'type': type,
      'eventId': eventId,
      'eventTitle': eventTitle,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
      'data': data,
    };
  }

  NotificationModel copyWith({
    String? id,
    String? title,
    String? body,
    String? type,
    String? eventId,
    String? eventTitle,
    DateTime? createdAt,
    bool? isRead,
    Map<String, dynamic>? data,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      eventId: eventId ?? this.eventId,
      eventTitle: eventTitle ?? this.eventTitle,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      data: data ?? this.data,
    );
  }
}

class UserNotificationSettings {
  final bool eventReminders;
  final bool newEvents;
  final bool ticketUpdates;
  final bool eventFeedback;
  final bool generalNotifications;
  final int reminderTime; // minutes before event
  final int newEventsDistance; // distance in kilometers for "your area"
  final bool soundEnabled;
  final bool vibrationEnabled;

  UserNotificationSettings({
    this.eventReminders = true,
    this.newEvents = true,
    this.ticketUpdates = true,
    this.eventFeedback = true,
    this.generalNotifications = true,
    this.reminderTime = 60, // 1 hour default
    this.newEventsDistance = 15, // 15 miles default for "your area"
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  factory UserNotificationSettings.fromMap(Map<String, dynamic> map) {
    return UserNotificationSettings(
      eventReminders: map['eventReminders'] ?? true,
      newEvents: map['newEvents'] ?? true,
      ticketUpdates: map['ticketUpdates'] ?? true,
      eventFeedback: map['eventFeedback'] ?? true,
      generalNotifications: map['generalNotifications'] ?? true,
      reminderTime: map['reminderTime'] ?? 60,
      newEventsDistance: map['newEventsDistance'] ?? 15,
      soundEnabled: map['soundEnabled'] ?? true,
      vibrationEnabled: map['vibrationEnabled'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventReminders': eventReminders,
      'newEvents': newEvents,
      'ticketUpdates': ticketUpdates,
      'eventFeedback': eventFeedback,
      'generalNotifications': generalNotifications,
      'reminderTime': reminderTime,
      'newEventsDistance': newEventsDistance,
      'soundEnabled': soundEnabled,
      'vibrationEnabled': vibrationEnabled,
    };
  }

  UserNotificationSettings copyWith({
    bool? eventReminders,
    bool? newEvents,
    bool? ticketUpdates,
    bool? eventFeedback,
    bool? generalNotifications,
    int? reminderTime,
    int? newEventsDistance,
    bool? soundEnabled,
    bool? vibrationEnabled,
  }) {
    return UserNotificationSettings(
      eventReminders: eventReminders ?? this.eventReminders,
      newEvents: newEvents ?? this.newEvents,
      ticketUpdates: ticketUpdates ?? this.ticketUpdates,
      eventFeedback: eventFeedback ?? this.eventFeedback,
      generalNotifications: generalNotifications ?? this.generalNotifications,
      reminderTime: reminderTime ?? this.reminderTime,
      newEventsDistance: newEventsDistance ?? this.newEventsDistance,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }
}
