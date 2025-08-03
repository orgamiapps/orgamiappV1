import 'package:cloud_firestore/cloud_firestore.dart';

class TicketModel {
  static String firebaseKey = 'Tickets';

  String id;
  String eventId;
  String eventTitle;
  String eventImageUrl;
  String eventLocation;
  DateTime eventDateTime;
  String customerUid;
  String customerName;
  String ticketCode;
  DateTime issuedDateTime;
  bool isUsed;
  DateTime? usedDateTime;
  String? usedBy;

  TicketModel({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.eventImageUrl,
    required this.eventLocation,
    required this.eventDateTime,
    required this.customerUid,
    required this.customerName,
    required this.ticketCode,
    required this.issuedDateTime,
    this.isUsed = false,
    this.usedDateTime,
    this.usedBy,
  });

  factory TicketModel.fromJson(dynamic parsedJson) {
    final data = parsedJson is Map
        ? parsedJson
        : (parsedJson.data() as Map<String, dynamic>);
    
    return TicketModel(
      id: data['id'],
      eventId: data['eventId'],
      eventTitle: data['eventTitle'],
      eventImageUrl: data['eventImageUrl'],
      eventLocation: data['eventLocation'],
      eventDateTime: (data['eventDateTime'] as Timestamp).toDate(),
      customerUid: data['customerUid'],
      customerName: data['customerName'],
      ticketCode: data['ticketCode'],
      issuedDateTime: (data['issuedDateTime'] as Timestamp).toDate(),
      isUsed: data['isUsed'] ?? false,
      usedDateTime: data['usedDateTime'] != null
          ? (data['usedDateTime'] as Timestamp).toDate()
          : null,
      usedBy: data['usedBy'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eventId': eventId,
      'eventTitle': eventTitle,
      'eventImageUrl': eventImageUrl,
      'eventLocation': eventLocation,
      'eventDateTime': eventDateTime,
      'customerUid': customerUid,
      'customerName': customerName,
      'ticketCode': ticketCode,
      'issuedDateTime': issuedDateTime,
      'isUsed': isUsed,
      'usedDateTime': usedDateTime,
      'usedBy': usedBy,
    };
  }

  // Generate a unique ticket code
  static String generateTicketCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    final code = StringBuffer();
    
    for (int i = 0; i < 8; i++) {
      code.write(chars[random % chars.length]);
    }
    
    return code.toString();
  }
} 