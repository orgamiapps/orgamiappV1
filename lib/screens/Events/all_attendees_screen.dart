import 'package:flutter/material.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/models/attendance_model.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/dimensions.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Attendees (${attendees.length})',
          style: const TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: Dimensions.fontSizeLarge,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: AppThemeColor.darkBlueColor,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppThemeColor.darkGreenColor,
              ),
            )
          : attendees.isEmpty
          ? const Center(
              child: Text(
                'No attendees yet',
                style: TextStyle(
                  color: AppThemeColor.dullFontColor,
                  fontSize: Dimensions.fontSizeLarge,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: attendees.length,
              itemBuilder: (context, index) {
                final attendee = attendees[index];
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

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 25,
                      backgroundColor: Colors.grey[300],
                      child: isAnon
                          ? const Icon(
                              Icons.person_off,
                              size: 30,
                              color: Colors.grey,
                            )
                          : (customer.profilePictureUrl != null
                                ? ClipOval(
                                    child: Image.network(
                                      customer.profilePictureUrl!,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return const Icon(
                                              Icons.person,
                                              size: 30,
                                              color: Colors.grey,
                                            );
                                          },
                                    ),
                                  )
                                : const Icon(
                                    Icons.person,
                                    size: 30,
                                    color: Colors.grey,
                                  )),
                    ),
                    title: Text(
                      isAnon
                          ? 'Anonymous'
                          : (attendee.customerUid == 'without_login'
                                ? attendee.userName
                                : customer.name),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: Dimensions.fontSizeLarge,
                        color: AppThemeColor.pureBlackColor,
                      ),
                    ),
                    subtitle: Text(
                      'Signed in at 24{_formatDateTime(attendee.attendanceDateTime)}',
                      style: const TextStyle(
                        color: AppThemeColor.dullFontColor,
                        fontSize: Dimensions.fontSizeSmall,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.check_circle,
                      color: AppThemeColor.darkGreenColor,
                      size: 20,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
