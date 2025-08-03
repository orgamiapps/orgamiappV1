import 'package:flutter/material.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/dimensions.dart';

class PreRegisteredHorizontalList extends StatefulWidget {
  final EventModel eventModel;

  const PreRegisteredHorizontalList({super.key, required this.eventModel});

  @override
  State<PreRegisteredHorizontalList> createState() =>
      _PreRegisteredHorizontalListState();
}

class _PreRegisteredHorizontalListState
    extends State<PreRegisteredHorizontalList> {
  List<AttendanceModel> preRegistered = [];
  List<CustomerModel> customerDetails = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreRegistered();
  }

  Future<void> _loadPreRegistered() async {
    try {
      setState(() {
        isLoading = true;
      });

      // Get all pre-registered for this event
      final preRegisteredList = await FirebaseFirestoreHelper()
          .getRegisterAttendance(eventId: widget.eventModel.id);

      // Get customer details for each pre-registered (limit to first 10 for performance)
      List<CustomerModel> customers = [];
      for (var attendee in preRegisteredList.take(10)) {
        final customer = await FirebaseFirestoreHelper().getSingleCustomer(
          customerId: attendee.customerUid,
        );
        if (customer != null) {
          customers.add(customer);
        }
      }

      setState(() {
        preRegistered = preRegisteredList;
        customerDetails = customers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print('Error loading pre-registered: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: CircularProgressIndicator(
            color: AppThemeColor.darkGreenColor,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modern Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  spreadRadius: 0,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.how_to_reg,
                    color: Color(0xFF667EEA),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registered',
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      Text(
                        '${preRegistered.length} people registered',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
                if (preRegistered.length >= 1)
                  GestureDetector(
                    onTap: () {
                      _showAllRegisteredPopup();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF667EEA).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF667EEA),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'See All',
                        style: TextStyle(
                          color: Color(0xFF667EEA),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Modern Registered List
          SizedBox(
            height: 100,
            child: preRegistered.isEmpty
                ? Center(
                    child: Text(
                      'No registered users yet',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: preRegistered.length > 5
                        ? 5
                        : preRegistered.length,
                    itemBuilder: (context, index) {
                      final attendee = preRegistered[index];
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

                      return Container(
                        margin: const EdgeInsets.only(right: 16),
                        child: Column(
                          children: [
                            // Modern Profile Picture
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isAnon
                                    ? const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF6B7280),
                                          Color(0xFF9CA3AF),
                                        ],
                                      )
                                    : const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF667EEA),
                                          Color(0xFF764BA2),
                                        ],
                                      ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isAnon
                                        ? const Color(
                                            0xFF6B7280,
                                          ).withOpacity(0.3)
                                        : const Color(
                                            0xFF667EEA,
                                          ).withOpacity(0.3),
                                    spreadRadius: 0,
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: isAnon
                                    ? Container(
                                        color: Colors.transparent,
                                        child: const Icon(
                                          Icons.person_off,
                                          size: 28,
                                          color: Colors.white,
                                        ),
                                      )
                                    : (customer.profilePictureUrl != null
                                          ? Image.network(
                                              customer.profilePictureUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return Container(
                                                      color: Colors.transparent,
                                                      child: const Icon(
                                                        Icons.person,
                                                        size: 28,
                                                        color: Colors.white,
                                                      ),
                                                    );
                                                  },
                                            )
                                          : Container(
                                              color: Colors.transparent,
                                              child: const Icon(
                                                Icons.person,
                                                size: 28,
                                                color: Colors.white,
                                              ),
                                            )),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Name with better styling
                            SizedBox(
                              width: 70,
                              child: Text(
                                isAnon
                                    ? 'Anonymous'
                                    : (attendee.customerUid == 'without_login'
                                          ? attendee.userName
                                          : customer.name),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isAnon
                                      ? const Color(0xFF6B7280)
                                      : const Color(0xFF1A1A1A),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showAllRegisteredPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 500),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF667EEA).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.how_to_reg,
                        color: Color(0xFF667EEA),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'All Registered',
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Roboto',
                            ),
                          ),
                          Text(
                            '${preRegistered.length} people registered',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 14,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: preRegistered.length,
                    itemBuilder: (context, index) {
                      final attendee = preRegistered[index];
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

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isAnon
                                    ? const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF6B7280),
                                          Color(0xFF9CA3AF),
                                        ],
                                      )
                                    : const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF667EEA),
                                          Color(0xFF764BA2),
                                        ],
                                      ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isAnon
                                        ? const Color(
                                            0xFF6B7280,
                                          ).withOpacity(0.3)
                                        : const Color(
                                            0xFF667EEA,
                                          ).withOpacity(0.3),
                                    spreadRadius: 0,
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: isAnon
                                    ? Container(
                                        color: Colors.transparent,
                                        child: const Icon(
                                          Icons.person_off,
                                          size: 24,
                                          color: Colors.white,
                                        ),
                                      )
                                    : (customer.profilePictureUrl != null
                                          ? Image.network(
                                              customer.profilePictureUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return Container(
                                                      color: Colors.transparent,
                                                      child: const Icon(
                                                        Icons.person,
                                                        size: 24,
                                                        color: Colors.white,
                                                      ),
                                                    );
                                                  },
                                            )
                                          : Container(
                                              color: Colors.transparent,
                                              child: const Icon(
                                                Icons.person,
                                                size: 24,
                                                color: Colors.white,
                                              ),
                                            )),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Name and details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAnon
                                        ? 'Anonymous'
                                        : (attendee.customerUid ==
                                                  'without_login'
                                              ? attendee.userName
                                              : customer.name),
                                    style: TextStyle(
                                      color: isAnon
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFF1A1A1A),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Status indicator
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF667EEA).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Registered',
                                style: const TextStyle(
                                  color: Color(0xFF667EEA),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
