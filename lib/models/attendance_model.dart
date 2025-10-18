import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceModel {
  static String firebaseKey = 'Attendance';
  static String registerFirebaseKey = 'RegisterAttendance';

  String id, userName, eventId, customerUid;
  String? realName;

  DateTime attendanceDateTime;
  List<String> answers;
  bool isAnonymous;

  // Dwell time tracking fields
  DateTime? entryTimestamp;
  DateTime? exitTimestamp;
  Duration? dwellTime;
  String?
  dwellStatus; // 'active', 'completed', 'auto-stopped', 'manual-stopped'
  String? dwellNotes; // For notes like 'Auto-stopped', 'Manual check-out', etc.

  // Sign-in method tracking
  String?
  signInMethod; // 'facial_recognition', 'qr_code', 'manual_code', 'geofence'

  AttendanceModel({
    required this.id,
    required this.userName,
    required this.eventId,
    required this.customerUid,
    required this.attendanceDateTime,
    required this.answers,
    this.isAnonymous = false,
    this.realName,
    this.entryTimestamp,
    this.exitTimestamp,
    this.dwellTime,
    this.dwellStatus,
    this.dwellNotes,
    this.signInMethod,
  });

  factory AttendanceModel.fromJson(dynamic parsedJson) {
    // Support both DocumentSnapshot and Map
    final data = parsedJson is Map
        ? parsedJson
        : (parsedJson.data() as Map<String, dynamic>);

    return AttendanceModel(
      id: data['id'],
      userName: data['userName'],
      eventId: data['eventId'],
      customerUid: data['customerUid'],
      attendanceDateTime: (data['attendanceDateTime'] as Timestamp).toDate(),
      answers: List<String>.from(data['answers']),
      isAnonymous: data['isAnonymous'] ?? false,
      realName: data['realName'],
      entryTimestamp: data['entryTimestamp'] != null
          ? (data['entryTimestamp'] as Timestamp).toDate()
          : null,
      exitTimestamp: data['exitTimestamp'] != null
          ? (data['exitTimestamp'] as Timestamp).toDate()
          : null,
      dwellTime: data['dwellTime'] != null
          ? Duration(milliseconds: data['dwellTime'])
          : null,
      dwellStatus: data['dwellStatus'],
      dwellNotes: data['dwellNotes'],
      signInMethod: data['signInMethod'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};

    data['id'] = id;
    data['userName'] = userName;
    data['eventId'] = eventId;
    data['customerUid'] = customerUid;
    data['attendanceDateTime'] = Timestamp.fromDate(attendanceDateTime);
    data['answers'] = answers;
    data['isAnonymous'] = isAnonymous;
    if (realName != null) data['realName'] = realName;

    // Dwell time fields
    if (entryTimestamp != null) {
      data['entryTimestamp'] = Timestamp.fromDate(entryTimestamp!);
    }
    if (exitTimestamp != null) {
      data['exitTimestamp'] = Timestamp.fromDate(exitTimestamp!);
    }
    if (dwellTime != null) data['dwellTime'] = dwellTime!.inMilliseconds;
    if (dwellStatus != null) data['dwellStatus'] = dwellStatus;
    if (dwellNotes != null) data['dwellNotes'] = dwellNotes;
    if (signInMethod != null) data['signInMethod'] = signInMethod;

    return data;
  }

  /// Returns formatted dwell time string (e.g., "2h 30m")
  String get formattedDwellTime {
    if (dwellTime == null) return '';

    final hours = dwellTime!.inHours;
    final minutes = dwellTime!.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Returns true if dwell tracking is active
  bool get isDwellActive => dwellStatus == 'active';

  /// Returns true if dwell tracking is completed
  bool get isDwellCompleted =>
      dwellStatus == 'completed' ||
      dwellStatus == 'auto-stopped' ||
      dwellStatus == 'manual-stopped';

  /// Returns the tracking state for visual indicators
  /// 'active' = green circle (actively tracking)
  /// 'completed' = red circle (finished tracking)
  /// 'pending' = grey circle (left but grace period not expired)
  /// 'none' = no circle (no tracking data)
  String get trackingState {
    if (dwellStatus == 'active') return 'active';
    if (dwellStatus == 'completed' ||
        dwellStatus == 'auto-stopped' ||
        dwellStatus == 'manual-stopped') {
      return 'completed';
    }
    if (entryTimestamp != null && exitTimestamp == null) {
      // Has entry but no exit - might be in grace period
      return 'pending';
    }
    return 'none';
  }
}
