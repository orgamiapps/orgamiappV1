import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceModel {
  static String firebaseKey = 'Attendance';
  static String registerFirebaseKey = 'RegisterAttendance';

  String id, userName, eventId, customerUid;
  String? realName;

  DateTime attendanceDateTime;
  List<String> answers;
  bool isAnonymous;

  AttendanceModel({
    required this.id,
    required this.userName,
    required this.eventId,
    required this.customerUid,
    required this.attendanceDateTime,
    required this.answers,
    this.isAnonymous = false,
    this.realName,
  });

  factory AttendanceModel.fromJson(parsedJson) {
    return AttendanceModel(
      id: parsedJson['id'],
      userName: parsedJson['userName'],
      eventId: parsedJson['eventId'],
      customerUid: parsedJson['customerUid'],
      attendanceDateTime:
          (parsedJson['attendanceDateTime'] as Timestamp).toDate(),
      answers: List<String>.from(parsedJson['answers']),
      isAnonymous: parsedJson['isAnonymous'] ?? false,
      realName: parsedJson['realName'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};

    data['id'] = id;
    data['userName'] = userName;
    data['eventId'] = eventId;
    data['customerUid'] = customerUid;
    data['attendanceDateTime'] = attendanceDateTime;
    data['answers'] = answers;
    data['isAnonymous'] = isAnonymous;
    if (realName != null) data['realName'] = realName;

    return data;
  }
}
