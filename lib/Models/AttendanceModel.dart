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

    return data;
  }
}
