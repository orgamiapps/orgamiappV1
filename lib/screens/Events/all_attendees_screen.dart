import 'package:flutter/material.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/attendance_model.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:intl/intl.dart';

class AllAttendeesScreen extends StatefulWidget {
  final EventModel eventModel;

  const AllAttendeesScreen({super.key, required this.eventModel});

  @override
  State<AllAttendeesScreen> createState() => _AllAttendeesScreenState();
}

class _AllAttendeesScreenState extends State<AllAttendeesScreen> {
  List<AttendanceModel> attendees = [];
  List<CustomerModel> customerDetails = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAttendees();
  }

  Future<void> _loadAttendees() async {
    try {
      setState(() {
        isLoading = true;
      });

      // Get all attendees for this event
      final attendeesList = await FirebaseFirestoreHelper().getAttendance(
        eventId: widget.eventModel.id,
      );

      // Get customer details for each attendee
      List<CustomerModel> customers = [];
      for (var attendee in attendeesList) {
        final customer = await FirebaseFirestoreHelper().getSingleCustomer(
          customerId: attendee.customerUid,
        );
        if (customer != null) {
          customers.add(customer);
        }
      }

      setState(() {
        attendees = attendeesList;
        customerDetails = customers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      // debugPrint('Error loading attendees: $e'); // Replace with proper logging
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkedInCount = attendees.length;
    final anonymousCount = attendees.where((item) => item.isAnonymous).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendees'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
      ),
      body: isLoading
          ? const AttendUsLoadingState(label: 'Loading attendees...')
          : attendees.isEmpty
          ? AttendUsEmptyState(
              icon: Icons.people_outline,
              title: 'No attendees yet',
              message:
                  'Checked-in attendees will appear here as guests arrive.',
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: attendees.length + 1,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return AttendUsPageSection(
                        title: widget.eventModel.title,
                        subtitle:
                            'Checked-in attendees, identity status, and arrival times.',
                        icon: Icons.fact_check_outlined,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 640;
                            final tiles = [
                              AttendUsMetricTile(
                                label: 'Checked in',
                                value: '$checkedInCount',
                                icon: Icons.check_circle_outline,
                                tone: AttendUsStatusTone.success,
                              ),
                              AttendUsMetricTile(
                                label: 'Anonymous',
                                value: '$anonymousCount',
                                icon: Icons.visibility_off_outlined,
                                tone: AttendUsStatusTone.neutral,
                              ),
                            ];
                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: isWide ? 2 : 1,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: isWide ? 3.1 : 3.6,
                              children: tiles,
                            );
                          },
                        ),
                      );
                    }

                    final attendee = attendees[index - 1];
                    final customer = customerDetails.firstWhere(
                      (c) => c.uid == attendee.customerUid,
                      orElse: () => CustomerModel(
                        uid: attendee.customerUid,
                        name: attendee.userName,
                        email: '',
                        createdAt: DateTime.now(),
                      ),
                    );

                    final isAnon = attendee.isAnonymous;
                    final displayName = isAnon
                        ? 'Anonymous attendee'
                        : (attendee.customerUid == 'without_login'
                              ? attendee.userName
                              : customer.name);

                    return AttendUsListTile(
                      leading: AttendUsAvatar(
                        imageUrl: isAnon ? null : customer.profilePictureUrl,
                        name: displayName,
                        fallbackIcon: isAnon
                            ? Icons.person_off_outlined
                            : Icons.person_outline,
                        tone: isAnon
                            ? AttendUsStatusTone.neutral
                            : AttendUsStatusTone.info,
                      ),
                      title: displayName,
                      subtitle:
                          'Signed in ${DateFormat('MMM d, yyyy • h:mm a').format(attendee.attendanceDateTime)}',
                      trailing: AttendUsStatusBadge(
                        label: 'Checked in',
                        icon: Icons.check,
                        tone: AttendUsStatusTone.success,
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
