import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/Services/notification_broadcast_service.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

class AttendeeNotificationScreen extends StatefulWidget {
  const AttendeeNotificationScreen({super.key});

  @override
  State<AttendeeNotificationScreen> createState() =>
      _AttendeeNotificationScreenState();
}

class _AttendeeNotificationScreenState extends State<AttendeeNotificationScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<CustomerModel> _attendees = [];
  List<CustomerModel> _filteredAttendees = [];
  List<String> _selectedAttendeeUids = [];
  bool _isLoading = true;
  bool _isSending = false;
  String _messageText = '';
  String _titleText = '';

  // Delivery method
  DeliveryMethod _deliveryMethod = DeliveryMethod.inApp;

  // Notification history
  List<Map<String, dynamic>> _notificationHistory = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAttendees();
    _loadNotificationHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAttendees() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // For now, we'll load all customers as attendees
      // In a real implementation, you'd want to filter by event attendance
      final attendees = await _getAllCustomers();
      setState(() {
        _attendees = attendees;
        _filteredAttendees = attendees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!mounted) return;
      ShowToast().showSnackBar('Error loading attendees: $e', context);
    }
  }

  Future<List<CustomerModel>> _getAllCustomers() async {
    // This is a placeholder implementation
    // In a real app, you'd want to get customers who have attended events
    return [];
  }

  Future<void> _loadNotificationHistory() async {
    setState(() {
      _isLoadingHistory = true;
    });

    try {
      // Fetch combined history (in-app and SMS)
      final history = await NotificationBroadcastService.getHistory();
      if (!mounted) return;
      setState(() {
        _notificationHistory = history;
        _isLoadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  void _filterAttendees(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredAttendees = _attendees;
      } else {
        _filteredAttendees = _attendees.where((attendee) {
          return attendee.name.toLowerCase().contains(query.toLowerCase()) ||
              attendee.email.toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _toggleAttendeeSelection(String uid) {
    setState(() {
      if (_selectedAttendeeUids.contains(uid)) {
        _selectedAttendeeUids.remove(uid);
      } else {
        _selectedAttendeeUids.add(uid);
      }
    });
  }

  void _selectAllAttendees() {
    setState(() {
      if (_deliveryMethod == DeliveryMethod.sms) {
        _selectedAttendeeUids = _filteredAttendees
            .where(
              (attendee) =>
                  attendee.phoneNumber != null &&
                  attendee.phoneNumber!.isNotEmpty,
            )
            .map((attendee) => attendee.uid)
            .toList();
      } else {
        _selectedAttendeeUids = _filteredAttendees.map((a) => a.uid).toList();
      }
    });
  }

  void _deselectAllAttendees() {
    setState(() {
      _selectedAttendeeUids.clear();
    });
  }

  Future<void> _sendNotification() async {
    if (_selectedAttendeeUids.isEmpty || _messageText.trim().isEmpty) {
      if (!mounted) return;
      ShowToast().showSnackBar(
        'Please select attendees and enter a message',
        context,
      );
      return;
    }

    // Prepare recipients by method
    final selectedAttendees = _filteredAttendees
        .where((a) => _selectedAttendeeUids.contains(a.uid))
        .toList();
    final title = _titleText.trim().isEmpty
        ? 'Announcement'
        : _titleText.trim();

    setState(() {
      _isSending = true;
    });

    try {
      if (_deliveryMethod == DeliveryMethod.inApp) {
        final userIds = selectedAttendees.map((a) => a.uid).toList();
        await NotificationBroadcastService.sendInApp(
          userIds: userIds,
          title: title,
          body: _messageText.trim(),
          type: 'broadcast',
          data: {},
        );
      } else {
        // SMS: filter to those with phone numbers
        final phoneNumbers = selectedAttendees
            .map((a) => a.phoneNumber?.trim())
            .where((p) => p != null && p.isNotEmpty)
            .map((p) => p!)
            .toList();
        if (phoneNumbers.isEmpty) {
          throw Exception('No valid phone numbers selected');
        }
        await NotificationBroadcastService.sendSms(
          phoneNumbers: phoneNumbers,
          message: _messageText.trim(),
          meta: {},
        );
      }

      setState(() {
        _isSending = false;
      });

      if (!mounted) return;
      ShowToast().showSnackBar('Notifications sent successfully!', context);
      // Refresh history
      _loadNotificationHistory();
    } catch (e) {
      setState(() {
        _isSending = false;
      });
      if (!mounted) return;
      ShowToast().showSnackBar('Error sending notifications: $e', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 5, // Account tab
      backgroundColor: AppThemeColor.backGroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Enhanced App Bar
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimensions.paddingSizeLarge,
                vertical: Dimensions.paddingSizeLarge,
              ),
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppThemeColor.lightBlueColor,
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: AppThemeColor.darkBlueColor,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: Dimensions.spaceSizedLarge),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send Notifications',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeExtraLarge,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Send SMS or in-app notifications to previous attendees',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeSmall,
                            color: AppThemeColor.dullFontColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: Dimensions.paddingSizeLarge,
                vertical: Dimensions.paddingSizeDefault,
              ),
              decoration: BoxDecoration(
                color: AppThemeColor.lightBlueColor,
                borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelPadding: const EdgeInsets.symmetric(vertical: 8),
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    color: AppThemeColor.darkBlueColor,
                    boxShadow: [
                      BoxShadow(
                        color: AppThemeColor.darkBlueColor.withValues(
                          alpha: 0.3,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  labelColor: AppThemeColor.pureWhiteColor,
                  unselectedLabelColor: AppThemeColor.darkBlueColor,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: Dimensions.fontSizeDefault,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: Dimensions.fontSizeDefault,
                  ),
                  tabs: const [
                    Tab(text: 'Send Notifications'),
                    Tab(text: 'History'),
                  ],
                ),
              ),
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildSendNotificationsTab(), _buildHistoryTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendNotificationsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
      child: Column(
        children: [
          // Delivery method toggle
          Container(
            padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
            decoration: BoxDecoration(
              color: AppThemeColor.pureWhiteColor,
              borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivery Method',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeDefault,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizeSmall),
                Text(
                  'Choose method of sending notifications',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeSmall,
                    color: AppThemeColor.dullFontColor,
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizeSmall),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('In-App'),
                      selected: _deliveryMethod == DeliveryMethod.inApp,
                      onSelected: (v) {
                        if (!v) return;
                        setState(() {
                          _deliveryMethod = DeliveryMethod.inApp;
                          // Keep selection (all users valid)
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('SMS'),
                      selected: _deliveryMethod == DeliveryMethod.sms,
                      onSelected: (v) {
                        if (!v) return;
                        setState(() {
                          _deliveryMethod = DeliveryMethod.sms;
                          // Remove selections without phone numbers
                          _selectedAttendeeUids = _selectedAttendeeUids.where((
                            uid,
                          ) {
                            final a = _filteredAttendees.firstWhere(
                              (x) => x.uid == uid,
                              orElse: () => CustomerModel(
                                uid: '',
                                name: '',
                                email: '',
                                createdAt: DateTime.now(),
                              ),
                            );
                            return a.phoneNumber != null &&
                                a.phoneNumber!.isNotEmpty;
                          }).toList();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search and Selection Controls
          Container(
            padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
            decoration: BoxDecoration(
              color: AppThemeColor.pureWhiteColor,
              borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Attendees',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeDefault,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizeSmall),

                // Search Bar
                TextField(
                  onChanged: _filterAttendees,
                  decoration: InputDecoration(
                    hintText: 'Search attendees...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      borderSide: BorderSide(color: AppThemeColor.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      borderSide: BorderSide(color: AppThemeColor.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      borderSide: BorderSide(
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: Dimensions.spaceSizeSmall),

                // Selection Controls
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _selectAllAttendees,
                        icon: const Icon(Icons.select_all, size: 18),
                        label: const Text('Select All'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemeColor.darkBlueColor,
                          foregroundColor: AppThemeColor.pureWhiteColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              Dimensions.radiusDefault,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Dimensions.spaceSizeSmall),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _deselectAllAttendees,
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Clear All'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppThemeColor.lightGrayColor,
                          foregroundColor: AppThemeColor.darkBlueColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              Dimensions.radiusDefault,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: Dimensions.spaceSizeSmall),

                // Selection Summary
                Container(
                  padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
                  decoration: BoxDecoration(
                    color: AppThemeColor.lightBlueColor,
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.people,
                        color: AppThemeColor.darkBlueColor,
                        size: 20,
                      ),
                      const SizedBox(width: Dimensions.spaceSizeSmall),
                      Expanded(
                        child: Text(
                          '${_selectedAttendeeUids.length} attendees selected',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeDefault,
                            fontWeight: FontWeight.w600,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Message Input
          Container(
            padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
            decoration: BoxDecoration(
              color: AppThemeColor.pureWhiteColor,
              borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Optional title for in-app notifications
                Text(
                  'Title (optional)',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeDefault,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizeSmall),
                TextField(
                  onChanged: (value) => setState(() => _titleText = value),
                  decoration: InputDecoration(
                    hintText: 'Announcement',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      borderSide: BorderSide(color: AppThemeColor.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      borderSide: BorderSide(color: AppThemeColor.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      borderSide: BorderSide(
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizedLarge),
                Text(
                  'Message',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeDefault,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizeSmall),
                TextField(
                  onChanged: (value) => setState(() => _messageText = value),
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Enter your message here...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      borderSide: BorderSide(color: AppThemeColor.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      borderSide: BorderSide(color: AppThemeColor.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      borderSide: BorderSide(
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizeSmall),
                Text(
                  _deliveryMethod == DeliveryMethod.sms
                      ? '${_messageText.length}/160 characters'
                      : '${_messageText.length} characters',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeSmall,
                    color:
                        _deliveryMethod == DeliveryMethod.sms &&
                            _messageText.length > 160
                        ? Colors.red
                        : AppThemeColor.dullFontColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Send Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSending ? null : _sendNotification,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_isSending ? 'Sending...' : 'Send Notification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeColor.darkBlueColor,
                foregroundColor: AppThemeColor.pureWhiteColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                ),
              ),
            ),
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Attendees List
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_filteredAttendees.isEmpty)
            _buildEmptyState()
          else
            _buildAttendeesList(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: AppThemeColor.dullIconColor,
          ),
          const SizedBox(height: Dimensions.spaceSizedLarge),
          Text(
            'No Previous Attendees',
            style: TextStyle(
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.w600,
              color: AppThemeColor.darkBlueColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Dimensions.spaceSizeSmall),
          Text(
            'You don\'t have any previous attendees yet. Create and host events to start building your attendee list.',
            style: TextStyle(
              fontSize: Dimensions.fontSizeDefault,
              color: AppThemeColor.dullFontColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendeesList() {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
            child: Text(
              'Previous Attendees (${_filteredAttendees.length})',
              style: TextStyle(
                fontSize: Dimensions.fontSizeDefault,
                fontWeight: FontWeight.w600,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredAttendees.length,
            itemBuilder: (context, index) {
              final attendee = _filteredAttendees[index];
              final isSelected = _selectedAttendeeUids.contains(attendee.uid);
              final canReceiveSMS =
                  attendee.phoneNumber != null &&
                  attendee.phoneNumber!.isNotEmpty;

              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: Dimensions.paddingSizeLarge,
                  vertical: Dimensions.paddingSizeSmall,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppThemeColor.darkBlueColor.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                  border: Border.all(
                    color: isSelected
                        ? AppThemeColor.darkBlueColor
                        : AppThemeColor.borderColor,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppThemeColor.lightBlueColor,
                    child: Text(
                      attendee.name.isNotEmpty
                          ? attendee.name[0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                        color: AppThemeColor.darkBlueColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    attendee.name,
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeDefault,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColor.darkBlueColor,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attendee.email,
                        style: TextStyle(
                          fontSize: Dimensions.fontSizeSmall,
                          color: AppThemeColor.dullFontColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.event,
                            size: 14,
                            color: AppThemeColor.dullIconColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '0 events attended', // Placeholder - would need to calculate from attendance data
                            style: TextStyle(
                              fontSize: Dimensions.fontSizeSmall,
                              color: AppThemeColor.dullFontColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            canReceiveSMS ? Icons.phone : Icons.phone_disabled,
                            size: 14,
                            color: canReceiveSMS
                                ? AppThemeColor.darkGreenColor
                                : AppThemeColor.dullIconColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            canReceiveSMS ? 'SMS available' : 'No phone number',
                            style: TextStyle(
                              fontSize: Dimensions.fontSizeSmall,
                              color: canReceiveSMS
                                  ? AppThemeColor.darkGreenColor
                                  : AppThemeColor.dullFontColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged:
                        (_deliveryMethod == DeliveryMethod.sms &&
                            !canReceiveSMS)
                        ? null
                        : (value) => _toggleAttendeeSelection(attendee.uid),
                    activeColor: AppThemeColor.darkBlueColor,
                  ),
                  onTap:
                      (_deliveryMethod == DeliveryMethod.sms && !canReceiveSMS)
                      ? null
                      : () => _toggleAttendeeSelection(attendee.uid),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
      child: Column(
        children: [
          if (_isLoadingHistory)
            const Center(child: CircularProgressIndicator())
          else if (_notificationHistory.isEmpty)
            _buildEmptyHistoryState()
          else
            _buildNotificationHistoryList(),
        ],
      ),
    );
  }

  Widget _buildEmptyHistoryState() {
    return Container(
      padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.history, size: 64, color: AppThemeColor.dullIconColor),
          const SizedBox(height: Dimensions.spaceSizedLarge),
          Text(
            'No Notification History',
            style: TextStyle(
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.w600,
              color: AppThemeColor.darkBlueColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Dimensions.spaceSizeSmall),
          Text(
            'Your sent notifications will appear here',
            style: TextStyle(
              fontSize: Dimensions.fontSizeDefault,
              color: AppThemeColor.dullFontColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationHistoryList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _notificationHistory.length,
      itemBuilder: (context, index) {
        final notification = _notificationHistory[index];
        final type = notification['type'] ?? 'in_app';
        final sentAt = (notification['timestamp'] is Timestamp)
            ? (notification['timestamp'] as Timestamp).toDate()
            : (notification['timestamp'] ?? DateTime.now());
        final total = notification['totalRecipients'] ?? 0;
        final success = notification['successCount'] ?? 0;
        final title =
            notification['title'] ??
            (type == 'sms' ? 'SMS Broadcast' : 'In-App Broadcast');
        final message = notification['message'] ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: Dimensions.spaceSizeSmall),
          padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
          decoration: BoxDecoration(
            color: AppThemeColor.pureWhiteColor,
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
                    decoration: BoxDecoration(
                      color: AppThemeColor.lightBlueColor,
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                    ),
                    child: Icon(
                      type == 'sms' ? Icons.sms : Icons.notifications,
                      color: AppThemeColor.darkBlueColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: Dimensions.spaceSizeSmall),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeDefault,
                            fontWeight: FontWeight.w600,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                        Text(
                          DateFormat('MMM dd, yyyy • HH:mm').format(sentAt),
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeSmall,
                            color: AppThemeColor.dullFontColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkGreenColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$success/$total sent',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Dimensions.spaceSizeSmall),
              Text(
                message,
                style: TextStyle(
                  fontSize: Dimensions.fontSizeDefault,
                  color: AppThemeColor.darkBlueColor,
                ),
              ),
              if (type == 'sms' && (notification['failureCount'] ?? 0) > 0) ...[
                const SizedBox(height: Dimensions.spaceSizeSmall),
                Container(
                  padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${notification['failureCount']} failed deliveries',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeSmall,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

enum DeliveryMethod { inApp, sms }
