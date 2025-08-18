import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/models/attendance_model.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/event_question_model.dart';
import 'package:orgami/Screens/Events/event_analytics_screen.dart';
import 'package:orgami/StorageHelper/file_storage.dart';
import 'package:orgami/Utils/app_buttons.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/router.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xcel;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';

class AttendanceSheetScreen extends StatefulWidget {
  final EventModel eventModel;
  final VoidCallback? onBackPressed;
  const AttendanceSheetScreen({
    super.key,
    required this.eventModel,
    this.onBackPressed,
  });

  @override
  State<AttendanceSheetScreen> createState() => _AttendanceSheetScreenState();
}

class _AttendanceSheetScreenState extends State<AttendanceSheetScreen> {
  late final EventModel eventModel = widget.eventModel;

  int selectedTab = 1;

  List<AttendanceModel> attendanceList = [];
  List<AttendanceModel> registerAttendanceList = [];
  List<EventQuestionModel> questionsList = [];

  Future<void> getAttendanceList() async {
    await FirebaseFirestoreHelper().getAttendance(eventId: eventModel.id).then((
      attendanceData,
    ) {
      setState(() {
        attendanceList = attendanceData;
      });
    });
  }

  Future<void> getRegisterAttendanceList() async {
    await FirebaseFirestoreHelper()
        .getRegisterAttendance(eventId: eventModel.id)
        .then((attendanceData) {
          setState(() {
            registerAttendanceList = attendanceData;
          });
        });
  }

  Future<void> _getQuestions() async {
    await FirebaseFirestoreHelper()
        .getEventQuestions(eventId: eventModel.id)
        .then((value) {
          setState(() {
            questionsList = value;
          });
        });
  }

  List<String> titlesOfSheet = [];

  int? getTitleIndex({required String title}) {
    int? indexIs;
    int count = 1;
    for (var element in titlesOfSheet) {
      if (element == title) {
        indexIs = count;
      }
      count++;
    }
    return indexIs;
  }

  void makeExcelFileForSignIn() {
    titlesOfSheet = [];
    titlesOfSheet = ['#', 'Name', 'Date', 'Time'];

    final xcel.Workbook workbook = xcel.Workbook();
    final xcel.Worksheet sheet = workbook.worksheets[0];
    int index = 1;
    for (var element in questionsList) {
      titlesOfSheet.add(element.questionTitle);
    }

    for (var element in titlesOfSheet) {
      sheet.getRangeByIndex(1, index).setText(element);
      index++;
    }

    for (var i = 0; i < attendanceList.length; i++) {
      final item = attendanceList[i];
      sheet.getRangeByIndex(i + 2, 1).setText((i + 1).toString());
      sheet.getRangeByIndex(i + 2, 2).setText(item.userName);
      sheet
          .getRangeByIndex(i + 2, 3)
          .setText(DateFormat('MMM dd, yyyy').format(item.attendanceDateTime));
      sheet
          .getRangeByIndex(i + 2, 4)
          .setText(DateFormat('h:mm a').format(item.attendanceDateTime));
      for (var element in item.answers) {
        String title = element.split('--ans--').first;
        String answer = element.split('--ans--').last;
        int? indexIs = getTitleIndex(title: title);
        if (indexIs != null) {
          sheet.getRangeByIndex(i + 2, indexIs).setText(answer);
        }
      }
    }

    final List<int> bytes = workbook.saveAsStream();
    FileStorage.writeCounter(
      Uint8List.fromList(bytes),
      "${eventModel.title} Attendance Sheet.xlsx",
    ).then((value) {
      ShowToast().showNormalToast(
        msg: '${eventModel.title} Attendance Sheet.xlsx Saved!',
      );
    });

    workbook.dispose();
  }

  void makeExcelFileForRegister() {
    titlesOfSheet = [];
    titlesOfSheet = ['#', 'Name', 'Date', 'Time'];

    final xcel.Workbook workbook = xcel.Workbook();
    final xcel.Worksheet sheet = workbook.worksheets[0];
    int index = 1;

    for (var element in titlesOfSheet) {
      sheet.getRangeByIndex(1, index).setText(element);
      index++;
    }

    for (var i = 0; i < registerAttendanceList.length; i++) {
      final item = registerAttendanceList[i];
      sheet.getRangeByIndex(i + 2, 1).setText((i + 1).toString());
      sheet.getRangeByIndex(i + 2, 2).setText(item.userName);
      sheet
          .getRangeByIndex(i + 2, 3)
          .setText(DateFormat('MMM dd, yyyy').format(item.attendanceDateTime));
      sheet
          .getRangeByIndex(i + 2, 4)
          .setText(DateFormat('h:mm a').format(item.attendanceDateTime));
    }

    final List<int> bytes = workbook.saveAsStream();
    FileStorage.writeCounter(
      Uint8List.fromList(bytes),
      "${eventModel.title} ${selectedTab == 1 ? '' : "RSVP's"} Attendance Sheet.xlsx",
    ).then((value) {
      ShowToast().showNormalToast(
        msg: '${eventModel.title} Attendance Sheet.xlsx Saved!',
      );
    });

    workbook.dispose();
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppThemeColor.dullFontColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.file_download,
                      color: AppThemeColor.darkBlueColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export Attendance Sheet',
                          style: const TextStyle(
                            color: AppThemeColor.pureBlackColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        Text(
                          'Choose how you want to export the attendance data',
                          style: const TextStyle(
                            color: AppThemeColor.dullFontColor,
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: AppThemeColor.dullFontColor,
                    ),
                  ),
                ],
              ),
            ),

            // Options
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Save Option
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeColor.darkGreenColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.save_rounded, color: Colors.white),
                      label: const Text(
                        'Save to Device',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        if (selectedTab == 1) {
                          makeExcelFileForSignIn();
                        } else {
                          makeExcelFileForRegister();
                        }
                      },
                    ),
                  ),

                  // Share Option
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeColor.darkBlueColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                      icon: const Icon(
                        CupertinoIcons.share,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Share via Email/Message',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _shareAttendanceSheet();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareAttendanceSheet() async {
    try {
      // Create the Excel file first
      if (selectedTab == 1) {
        makeExcelFileForSignIn();
      } else {
        makeExcelFileForRegister();
      }

      // Wait a moment for the file to be created
      await Future.delayed(const Duration(milliseconds: 500));

      // Get the file path
      final fileName =
          "${eventModel.title} ${selectedTab == 1 ? '' : "RSVP's"} Attendance Sheet.xlsx";
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      // Check if file exists
      final file = File(filePath);
      if (await file.exists()) {
        // Share the file
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(filePath)],
            text: 'Attendance Sheet for ${eventModel.title}',
            subject: 'Event Attendance Sheet',
          ),
        );
      } else {
        if (mounted) {
          ShowToast().showSnackBar(
            'File not found. Please try saving first.',
            context,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ShowToast().showSnackBar('Error sharing file: $e', context);
      }
    }
  }

  @override
  void initState() {
    getAttendanceList();
    getRegisterAttendanceList();
    _getQuestions();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.lightBlueColor,
      body: SafeArea(child: _bodyView()),
    );
  }

  Widget _modernTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _modernTabView(label: 'Sign In', index: 1),
          _modernTabView(label: "RSVP's", index: 2),
        ],
      ),
    );
  }

  Widget _modernTabView({required String label, required int index}) {
    bool selectedOne = selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedTab = index;
          });
        },
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selectedOne
                ? AppThemeColor.darkBlueColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selectedOne
                    ? AppThemeColor.pureWhiteColor
                    : AppThemeColor.dullFontColor,
                fontSize: Dimensions.fontSizeDefault,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bodyView() {
    return Column(
      children: [
        // Modern Header with Export Button
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  // Call the callback to show Event Management popup again
                  if (widget.onBackPressed != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.onBackPressed!();
                    });
                  }
                },
                child: AppButtons.roundedButton(
                  iconData: Icons.arrow_back_ios_rounded,
                  iconColor: AppThemeColor.pureWhiteColor,
                  backgroundColor: AppThemeColor.darkBlueColor,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  'Attendance Sheet',
                  style: const TextStyle(
                    color: AppThemeColor.darkBlueColor,
                    fontSize: Dimensions.paddingSizeLarge,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Export Button
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColor.darkBlueColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
                      spreadRadius: 0,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: () => _showExportOptions(),
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Modern Tab Bar
        _modernTabBar(),

        // Content Area
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: AppThemeColor.pureWhiteColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  spreadRadius: 0,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: selectedTab == 1
                ? _modernSignInDetailsView()
                : _modernRegisterDetailsView(),
          ),
        ),

        // View Analytics Button
        Container(
          margin: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeColor.darkBlueColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
              ),
              onPressed: () {
                if (eventModel.customerUid ==
                    FirebaseAuth.instance.currentUser?.uid) {
                  RouterClass.nextScreenNormal(
                    context,
                    EventAnalyticsScreen(eventId: eventModel.id),
                  );
                } else {
                  ShowToast().showSnackBar(
                    'Only event hosts can view analytics',
                    context,
                  );
                }
              },
              child: const Text(
                'View Analytics',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _modernRegisterDetailsView() {
    return Column(
      children: [
        // Header with stats
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppThemeColor.lightBlueColor.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.how_to_reg,
                  color: AppThemeColor.darkBlueColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "RSVP's",
                      style: const TextStyle(
                        color: AppThemeColor.pureBlackColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    Text(
                      "${registerAttendanceList.length} RSVP's",
                      style: const TextStyle(
                        color: AppThemeColor.dullFontColor,
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Attendees List
        Expanded(
          child: registerAttendanceList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppThemeColor.lightGrayColor.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: const Icon(
                          Icons.people_outline,
                          size: 40,
                          color: AppThemeColor.lightGrayColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "No RSVP's yet",
                        style: TextStyle(
                          color: AppThemeColor.dullFontColor,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: registerAttendanceList.length,
                  itemBuilder: (context, index) {
                    final attendee = registerAttendanceList[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppThemeColor.borderColor,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            spreadRadius: 0,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Sequential number (more subtle)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppThemeColor.lightBlueColor.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppThemeColor.darkBlueColor.withValues(
                                  alpha: 0.2,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: AppThemeColor.darkBlueColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  attendee.userName,
                                  style: const TextStyle(
                                    color: AppThemeColor.pureBlackColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Registered on ${DateFormat('MMM dd, yyyy').format(attendee.attendanceDateTime)} at ${DateFormat('h:mm a').format(attendee.attendanceDateTime)}',
                                  style: const TextStyle(
                                    color: AppThemeColor.dullFontColor,
                                    fontSize: 14,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppThemeColor.darkBlueColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Registered',
                              style: TextStyle(
                                color: AppThemeColor.darkBlueColor,
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
    );
  }

  Widget _modernSignInDetailsView() {
    return Column(
      children: [
        // Header with stats and add button
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppThemeColor.lightBlueColor.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: AppThemeColor.darkBlueColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sign-In Attendees',
                      style: const TextStyle(
                        color: AppThemeColor.pureBlackColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    Text(
                      '${attendanceList.length} people signed in',
                      style: const TextStyle(
                        color: AppThemeColor.dullFontColor,
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    // Dwell time summary
                    if (_hasDwellTimeData()) ...[
                      const SizedBox(height: 4),
                      Text(
                        _getDwellTimeSummary(),
                        style: const TextStyle(
                          color: Color(0xFF667EEA),
                          fontSize: 12,
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildLegendChip(
                            color: const Color(0xFF10B981),
                            label: 'Active',
                            count: _countTrackingState('active'),
                          ),
                          _buildLegendChip(
                            color: const Color(0xFFEF4444),
                            label: 'Completed',
                            count: _countTrackingState('completed'),
                          ),
                          _buildLegendChip(
                            color: const Color(0xFF9CA3AF),
                            label: 'Pending',
                            count: _countTrackingState('pending'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Add Name Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemeColor.darkBlueColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add, color: Colors.white, size: 18),
                label: const Text(
                  'Add Name',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                  ),
                ),
                onPressed: () async {
                  final name = await _showAddNameDialog();
                  if (name != null && name.isNotEmpty) {
                    await _addManualAttendance(name);
                  }
                },
              ),
            ],
          ),
        ),

        // Attendees List
        Expanded(
          child: attendanceList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppThemeColor.lightGrayColor.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: const Icon(
                          Icons.check_circle_outline,
                          size: 40,
                          color: AppThemeColor.lightGrayColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No sign-ins yet',
                        style: TextStyle(
                          color: AppThemeColor.dullFontColor,
                          fontSize: 16,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: attendanceList.length,
                  itemBuilder: (context, index) {
                    final attendee = attendanceList[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppThemeColor.borderColor,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            spreadRadius: 0,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Main content area
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row with number, name, and status
                                Row(
                                  children: [
                                    // Attendee number
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: AppThemeColor.lightBlueColor
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: AppThemeColor.darkBlueColor,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Roboto',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    // Name and status indicator
                                    Expanded(
                                      child: Row(
                                        children: [
                                          // Status indicator
                                          if (attendee.trackingState !=
                                              'none') ...[
                                            Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color:
                                                    attendee.trackingState ==
                                                        'active'
                                                    ? const Color(0xFF10B981)
                                                    : attendee.trackingState ==
                                                          'completed'
                                                    ? const Color(0xFFEF4444)
                                                    : const Color(0xFF9CA3AF),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          // Name
                                          Expanded(
                                            child: Text(
                                              (attendee.isAnonymous &&
                                                      eventModel.customerUid ==
                                                          FirebaseAuth
                                                              .instance
                                                              .currentUser
                                                              ?.uid &&
                                                      attendee.realName != null)
                                                  ? attendee.realName!
                                                  : attendee.userName,
                                              style: const TextStyle(
                                                color: AppThemeColor
                                                    .pureBlackColor,
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'Roboto',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Signed In badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppThemeColor.darkBlueColor
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'Signed In',
                                        style: TextStyle(
                                          color: AppThemeColor.darkBlueColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Sign-in time
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 16,
                                      color: AppThemeColor.dullFontColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${DateFormat('MMM dd, yyyy').format(attendee.attendanceDateTime)} at ${DateFormat('h:mm a').format(attendee.attendanceDateTime)}',
                                      style: const TextStyle(
                                        color: AppThemeColor.dullFontColor,
                                        fontSize: 14,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                // Time attended section
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: attendee.trackingState == 'active'
                                        ? const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.08)
                                        : attendee.trackingState == 'completed'
                                        ? const Color(
                                            0xFF667EEA,
                                          ).withValues(alpha: 0.08)
                                        : attendee.trackingState == 'pending'
                                        ? const Color(
                                            0xFF9CA3AF,
                                          ).withValues(alpha: 0.08)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: attendee.trackingState == 'active'
                                          ? const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.2)
                                          : attendee.trackingState ==
                                                'completed'
                                          ? const Color(
                                              0xFF667EEA,
                                            ).withValues(alpha: 0.2)
                                          : attendee.trackingState == 'pending'
                                          ? const Color(
                                              0xFF9CA3AF,
                                            ).withValues(alpha: 0.2)
                                          : const Color(0xFFE5E7EB),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        attendee.trackingState == 'active'
                                            ? Icons.location_on
                                            : Icons.timer,
                                        color:
                                            attendee.trackingState == 'active'
                                            ? const Color(0xFF10B981)
                                            : attendee.trackingState ==
                                                  'completed'
                                            ? const Color(0xFF667EEA)
                                            : attendee.trackingState ==
                                                  'pending'
                                            ? const Color(0xFF9CA3AF)
                                            : const Color(0xFF9CA3AF),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              attendee.trackingState == 'active'
                                                  ? 'Currently Tracking'
                                                  : attendee.trackingState ==
                                                        'completed'
                                                  ? 'Time Attended'
                                                  : attendee.trackingState ==
                                                        'pending'
                                                  ? 'Left Event (Grace Period)'
                                                  : 'Time Tracking',
                                              style: TextStyle(
                                                color:
                                                    attendee.trackingState ==
                                                        'active'
                                                    ? const Color(0xFF10B981)
                                                    : attendee.trackingState ==
                                                          'completed'
                                                    ? const Color(0xFF667EEA)
                                                    : attendee.trackingState ==
                                                          'pending'
                                                    ? const Color(0xFF9CA3AF)
                                                    : const Color(0xFF6B7280),
                                                fontSize: 14,
                                                fontFamily: 'Roboto',
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              attendee.trackingState == 'active'
                                                  ? 'Attendee is currently at the event'
                                                  : attendee.trackingState ==
                                                        'completed'
                                                  ? attendee
                                                            .formattedDwellTime
                                                            .isNotEmpty
                                                        ? attendee
                                                              .formattedDwellTime
                                                        : 'No duration recorded'
                                                  : attendee.trackingState ==
                                                        'pending'
                                                  ? 'Left but grace period not expired'
                                                  : 'No tracking data available',
                                              style: TextStyle(
                                                color:
                                                    attendee.trackingState ==
                                                        'active'
                                                    ? const Color(0xFF10B981)
                                                    : attendee.trackingState ==
                                                          'completed'
                                                    ? const Color(0xFF667EEA)
                                                    : attendee.trackingState ==
                                                          'pending'
                                                    ? const Color(0xFF9CA3AF)
                                                    : const Color(0xFF9CA3AF),
                                                fontSize: 13,
                                                fontFamily: 'Roboto',
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (attendee.dwellNotes != null &&
                                                attendee
                                                    .dwellNotes!
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF9CA3AF,
                                                  ).withValues(alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  attendee.dwellNotes!,
                                                  style: const TextStyle(
                                                    color: Color(0xFF6B7280),
                                                    fontSize: 11,
                                                    fontFamily: 'Roboto',
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Question answers section
                          if (attendee.answers.isNotEmpty) ...[
                            Container(
                              margin: const EdgeInsets.only(top: 1),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppThemeColor.lightBlueColor.withValues(
                                  alpha: 0.05,
                                ),
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                                border: Border.all(
                                  color: AppThemeColor.borderColor.withValues(
                                    alpha: 0.3,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.question_answer,
                                        size: 16,
                                        color: AppThemeColor.darkBlueColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Question Responses (${attendee.answers.length})',
                                        style: const TextStyle(
                                          color: AppThemeColor.darkBlueColor,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ...attendee.answers.map((answer) {
                                    final parts = answer.split('--ans--');
                                    if (parts.length == 2) {
                                      final question = parts[0];
                                      final response = parts[1];
                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              question,
                                              style: const TextStyle(
                                                color: AppThemeColor
                                                    .pureBlackColor,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                fontFamily: 'Roboto',
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color:
                                                      AppThemeColor.borderColor,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                response,
                                                style: const TextStyle(
                                                  color: AppThemeColor
                                                      .dullFontColor,
                                                  fontSize: 13,
                                                  fontFamily: 'Roboto',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<String?> _showAddNameDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        String inputName = '';
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          elevation: 8,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.person_add,
                  color: AppThemeColor.darkBlueColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Add Name to Attendance',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    color: AppThemeColor.pureBlackColor,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                'Enter the name of the person you want to add to the attendance list.',
                style: TextStyle(
                  color: AppThemeColor.dullFontColor,
                  fontSize: 14,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter name',
                  hintStyle: TextStyle(
                    color: AppThemeColor.dullFontColor.withValues(alpha: 0.6),
                    fontFamily: 'Roboto',
                  ),
                  filled: true,
                  fillColor: AppThemeColor.lightBlueColor.withValues(
                    alpha: 0.05,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppThemeColor.borderColor,
                      width: 1,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppThemeColor.borderColor,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppThemeColor.darkBlueColor,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 16),
                onChanged: (value) => inputName = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppThemeColor.dullFontColor,
                  fontFamily: 'Roboto',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeColor.darkBlueColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                elevation: 2,
              ),
              onPressed: () {
                if (inputName.trim().isNotEmpty) {
                  Navigator.pop(context, inputName.trim());
                }
              },
              child: const Text(
                'Add Name',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Roboto',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String getSingleQuestionAnswer({
    required String questionTitle,
    required List<String> answers,
  }) {
    String answer = '';

    for (var element in answers) {
      String title = element.split('--ans--').first;
      String answerIs = element.split('--ans--').last;
      if (title == questionTitle) {
        answer = answerIs;
      }
    }

    return answer;
  }

  Future<void> _addManualAttendance(String name) async {
    final attendanceDateTime = DateTime.now();
    final id =
        '${eventModel.id}-manual-${DateTime.now().millisecondsSinceEpoch}';
    final attendanceModel = AttendanceModel(
      id: id,
      eventId: eventModel.id,
      userName: name,
      customerUid: 'manual',
      attendanceDateTime: attendanceDateTime,
      answers: [],
    );

    await FirebaseFirestoreHelper().addAttendance(attendanceModel);
    getAttendanceList(); // Refresh the list
    ShowToast().showNormalToast(msg: '$name added to attendance.');
  }

  // Removed deprecated excel export example that depended on the 'excel' package.

  /// Checks if any attendees have dwell time data
  bool _hasDwellTimeData() {
    return attendanceList.any(
      (attendee) => attendee.dwellTime != null || attendee.isDwellActive,
    );
  }

  /// Gets a summary of dwell time statistics
  String _getDwellTimeSummary() {
    final activeTracking = attendanceList.where((a) => a.isDwellActive).length;
    final completedTracking = attendanceList
        .where((a) => a.isDwellCompleted)
        .length;

    if (activeTracking > 0 && completedTracking > 0) {
      return '$activeTracking active, $completedTracking completed';
    } else if (activeTracking > 0) {
      return '$activeTracking active tracking';
    } else if (completedTracking > 0) {
      return '$completedTracking completed tracking';
    } else {
      return '';
    }
  }

  int _countTrackingState(String state) {
    return attendanceList.where((a) => a.trackingState == state).length;
  }

  Widget _buildLegendChip({
    required Color color,
    required String label,
    required int count,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label (${count.toString()})',
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 11,
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
