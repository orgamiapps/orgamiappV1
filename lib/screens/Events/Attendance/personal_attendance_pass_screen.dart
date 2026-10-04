import 'package:flutter/material.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/Attendance/attendance_wallet_pass_screen.dart';

class PersonalAttendancePassScreen extends StatelessWidget {
  const PersonalAttendancePassScreen({
    super.key,
    required this.event,
    this.registrationId,
    this.ticketId,
  });
  final EventModel event;
  final String? registrationId;
  final String? ticketId;
  @override
  Widget build(BuildContext context) => AttendanceWalletPassScreen(
    eventId: event.id,
    registrationId: registrationId,
    ticketId: ticketId,
  );
}
