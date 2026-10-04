import 'package:cloud_firestore/cloud_firestore.dart';

class CheckInSession {
  static const firebaseKey = 'CheckInSessions';

  final String id;
  final String eventId;
  final String status;
  final DateTime opensAt;
  final DateTime closesAt;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? venueCode;
  final DateTime? venueCodeExpiresAt;
  final int tokenVersion;
  final String? passPublicKey;

  const CheckInSession({
    required this.id,
    required this.eventId,
    required this.status,
    required this.opensAt,
    required this.closesAt,
    required this.startedAt,
    this.endedAt,
    this.venueCode,
    this.venueCodeExpiresAt,
    this.tokenVersion = 1,
    this.passPublicKey,
  });

  bool get isActive => status == 'active';

  factory CheckInSession.fromJson(dynamic value) {
    final data = value is Map<String, dynamic>
        ? value
        : (value.data() as Map<String, dynamic>);
    DateTime date(dynamic raw) => raw is Timestamp
        ? raw.toDate()
        : DateTime.tryParse(raw?.toString() ?? '') ?? DateTime.now();

    return CheckInSession(
      id: data['id']?.toString() ?? '',
      eventId: data['eventId']?.toString() ?? '',
      status: data['status']?.toString() ?? 'closed',
      opensAt: date(data['opensAt']),
      closesAt: date(data['closesAt']),
      startedAt: date(data['startedAt']),
      endedAt: data['endedAt'] == null ? null : date(data['endedAt']),
      venueCode: data['venueCode']?.toString(),
      venueCodeExpiresAt: data['venueCodeExpiresAt'] == null
          ? null
          : date(data['venueCodeExpiresAt']),
      tokenVersion: (data['tokenVersion'] as num?)?.toInt() ?? 1,
      passPublicKey: data['passPublicKey']?.toString(),
    );
  }
}
