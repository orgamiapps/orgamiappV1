import 'package:flutter/material.dart';
import 'package:orgami/Services/SMSNotificationService.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Dimensions.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AttendeeNotificationScreen extends StatefulWidget {
  const AttendeeNotificationScreen({super.key});

  @override
  State<AttendeeNotificationScreen> createState() =>
      _AttendeeNotificationScreenState();
}

class _AttendeeNotificationScreenState extends State<AttendeeNotificationScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<AttendeeInfo> _attendees = [];
  List<AttendeeInfo> _filteredAttendees = [];
  List<String> _selectedAttendeeUids = [];
  bool _isLoading = true;
  bool _isSending = false;
  String _searchQuery = '';
  String _messageText = '';
  String _selectedEventTitle = 'All Events';

  // Notification history
  List<NotificationHistory> _notificationHistory = [];
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
      final attendees = await SMSNotificationService()
          .getAllPreviousAttendees();
      setState(() {
        _attendees = attendees;
        _filteredAttendees = attendees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ShowToast().showSnackBar('Error loading attendees: $e', context);
    }
  }

  Future<void> _loadNotificationHistory() async {
    setState(() {
      _isLoadingHistory = true;
    });

    try {
      final history = await SMSNotificationService().getNotificationHistory();
      setState(() {
        _notificationHistory = history;
        _isLoadingHistory = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  void _filterAttendees(String query) {
    setState(() {
      _searchQuery = query;
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
      _selectedAttendeeUids = _filteredAttendees
          .where((attendee) => attendee.hasPhoneNumber)
          .map((attendee) => attendee.uid)
          .toList();
    });
  }

  void _deselectAllAttendees() {
    setState(() {
      _selectedAttendeeUids.clear();
    });
  }

  Future<void> _sendNotification() async {
    if (_selectedAttendeeUids.isEmpty) {
      ShowToast().showSnackBar('Please select at least one attendee', context);
      return;
    }

    if (_messageText.trim().isEmpty) {
      ShowToast().showSnackBar('Please enter a message', context);
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final result = await SMSNotificationService().sendSMSNotification(
        attendeeUids: _selectedAttendeeUids,
        message: _messageText,
        eventTitle: _selectedEventTitle,
      );

      if (result.success) {
        ShowToast().showSnackBar(result.message, context);
        setState(() {
          _selectedAttendeeUids.clear();
          _messageText = '';
        });
        _loadNotificationHistory();
      } else {
        ShowToast().showSnackBar(result.message, context);
      }
    } catch (e) {
      ShowToast().showSnackBar('Error sending notification: $e', context);
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    color: Colors.black.withOpacity(0.08),
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
                          'Attendee Notifications',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeExtraLarge,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Send SMS notifications to previous attendees',
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
                    color: Colors.black.withOpacity(0.08),
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
                        color: AppThemeColor.darkBlueColor.withOpacity(0.3),
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
          // Search and Selection Controls
          Container(
            padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
            decoration: BoxDecoration(
              color: AppThemeColor.pureWhiteColor,
              borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
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
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  '${_messageText.length}/160 characters',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeSmall,
                    color: _messageText.length > 160
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
            color: Colors.black.withOpacity(0.05),
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
            color: Colors.black.withOpacity(0.05),
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
              final canReceiveSMS = attendee.hasPhoneNumber;

              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: Dimensions.paddingSizeLarge,
                  vertical: Dimensions.paddingSizeSmall,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppThemeColor.darkBlueColor.withOpacity(0.1)
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
                            '${attendee.totalEventsAttended} events attended',
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
                  trailing: canReceiveSMS
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (value) =>
                              _toggleAttendeeSelection(attendee.uid),
                          activeColor: AppThemeColor.darkBlueColor,
                        )
                      : Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppThemeColor.lightGrayColor,
                            borderRadius: BorderRadius.circular(
                              Dimensions.radiusDefault,
                            ),
                          ),
                          child: Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppThemeColor.dullIconColor,
                          ),
                        ),
                  onTap: canReceiveSMS
                      ? () => _toggleAttendeeSelection(attendee.uid)
                      : null,
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
            color: Colors.black.withOpacity(0.05),
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

        return Container(
          margin: const EdgeInsets.only(bottom: Dimensions.spaceSizeSmall),
          padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
          decoration: BoxDecoration(
            color: AppThemeColor.pureWhiteColor,
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
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
                      Icons.sms,
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
                          notification.eventTitle,
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeDefault,
                            fontWeight: FontWeight.w600,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                        Text(
                          DateFormat(
                            'MMM dd, yyyy • HH:mm',
                          ).format(notification.sentAt),
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
                      '${notification.totalRecipients} sent',
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
                notification.message,
                style: TextStyle(
                  fontSize: Dimensions.fontSizeDefault,
                  color: AppThemeColor.darkBlueColor,
                ),
              ),
              if (notification.missingPhoneNumbers.isNotEmpty) ...[
                const SizedBox(height: Dimensions.spaceSizeSmall),
                Container(
                  padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${notification.missingPhoneNumbers.length} attendees without phone numbers',
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
