import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Models/EventQuestionModel.dart';
import 'package:orgami/Screens/Events/Widget/AttendanceAnswersPopup.dart';
import 'package:orgami/StorageHelper/FileStorage.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xcel;

class AttendanceSheetScreen extends StatefulWidget {
  final EventModel eventModel;
  const AttendanceSheetScreen({super.key, required this.eventModel});

  @override
  State<AttendanceSheetScreen> createState() => _AttendanceSheetScreenState();
}

class _AttendanceSheetScreenState extends State<AttendanceSheetScreen> {
  late final EventModel eventModel = widget.eventModel;
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final ScrollController _scrollController = ScrollController();

  int selectedTab = 1;

  List<AttendanceModel> attendanceList = [];
  List<AttendanceModel> registerAttendanceList = [];
  List<EventQuestionModel> questionsList = [];

  Future<void> getAttendanceList() async {
    await FirebaseFirestoreHelper()
        .getAttendance(eventId: eventModel.id)
        .then((attendanceData) {
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
    titlesOfSheet = ['Index', 'Name', 'Date', 'Time'];

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

    // sheet.getRangeByIndex(1, 1).setText("Index");
    // sheet.getRangeByIndex(1, 2).setText("Name");
    // sheet.getRangeByIndex(1, 3).setText("Date");
    // sheet.getRangeByIndex(1, 4).setText("Time");

    for (var i = 0; i < attendanceList.length; i++) {
      final item = attendanceList[i];
      sheet.getRangeByIndex(i + 2, 1).setText((i + 1).toString());
      sheet.getRangeByIndex(i + 2, 2).setText(item.userName);
      sheet.getRangeByIndex(i + 2, 3).setText(DateFormat('EEE dd MMM').format(
            item.attendanceDateTime,
          ));
      sheet.getRangeByIndex(i + 2, 4).setText(DateFormat('KK:mm a').format(
            item.attendanceDateTime,
          ));
      for (var element in item.answers) {
        String title = element.split('--ans--').first;
        String answer = element.split('--ans--').last;
        int? indexIs = getTitleIndex(title: title);
        print('index -- $indexIs');
        if (indexIs != null) {
          print('index is $indexIs');
          sheet.getRangeByIndex(i + 2, indexIs).setText(answer);
        }
      }
    }

    final List<int> bytes = workbook.saveAsStream();
    FileStorage.writeCounter(
      bytes,
      "${eventModel.title} Attendance Sheet.xlsx",
    ).then((value) {
      ShowToast().showNormalToast(
          msg: '${eventModel.title} Attendance Sheet.xlsx Saved!');
    });

    workbook.dispose();
  }

  void makeExcelFileForRegister() {
    titlesOfSheet = [];
    titlesOfSheet = ['Index', 'Name', 'Date', 'Time'];

    final xcel.Workbook workbook = xcel.Workbook();
    final xcel.Worksheet sheet = workbook.worksheets[0];
    int index = 1;
    // for (var element in questionsList) {
    //   titlesOfSheet.add(element.questionTitle);
    // }
    //
    for (var element in titlesOfSheet) {
      sheet.getRangeByIndex(1, index).setText(element);
      index++;
    }

    // sheet.getRangeByIndex(1, 1).setText("Index");
    // sheet.getRangeByIndex(1, 2).setText("Name");
    // sheet.getRangeByIndex(1, 3).setText("Date");
    // sheet.getRangeByIndex(1, 4).setText("Time");

    for (var i = 0; i < registerAttendanceList.length; i++) {
      final item = registerAttendanceList[i];
      sheet.getRangeByIndex(i + 2, 1).setText((i + 1).toString());
      sheet.getRangeByIndex(i + 2, 2).setText(item.userName);
      sheet.getRangeByIndex(i + 2, 3).setText(DateFormat('EEE dd MMM').format(
            item.attendanceDateTime,
          ));
      sheet.getRangeByIndex(i + 2, 4).setText(DateFormat('KK:mm a').format(
            item.attendanceDateTime,
          ));
      // for (var element in item.answers) {
      //   String title = element.split('--ans--').first;
      //   String answer = element.split('--ans--').last;
      //   int? indexIs = getTitleIndex(title: title);
      //   print('index -- $indexIs');
      //   if (indexIs != null) {
      //     print('index is $indexIs');
      //     sheet.getRangeByIndex(i + 2, indexIs).setText(answer);
      //   }
      // }
    }

    final List<int> bytes = workbook.saveAsStream();
    FileStorage.writeCounter(
      bytes,
      "${eventModel.title} ${selectedTab == 1 ? '' : 'Pre Registered'} Attendance Sheet.xlsx",
    ).then((value) {
      ShowToast().showNormalToast(
          msg: '${eventModel.title} Attendance Sheet.xlsx Saved!');
    });

    workbook.dispose();
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
      body: SafeArea(
        child: _bodyView(),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppThemeColor.darkGreenColor,
        onPressed: selectedTab == 1
            ? makeExcelFileForSignIn
            : makeExcelFileForRegister,
        child: const Icon(
          Icons.ios_share_rounded,
          color: AppThemeColor.pureWhiteColor,
        ),
      ),
    );
  }

  Widget _tobTabBar() {
    return Row(
      children: [
        _singleTabBarView(label: 'Sign In', index: 1),
        _singleTabBarView(label: 'Pre Registered', index: 2),
      ],
    );
  }

  Widget _singleTabBarView({required String label, required int index}) {
    bool selectedOne = selectedTab == index;
    return Expanded(
        child: GestureDetector(
      onTap: () {
        setState(() {
          selectedTab = index;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selectedOne
              ? AppThemeColor.darkBlueColor
              : AppThemeColor.darkGreenColor,
        ),
        child: Center(
            child: Text(
          label,
          style: const TextStyle(
            color: AppThemeColor.pureWhiteColor,
            fontSize: Dimensions.fontSizeDefault,
            fontWeight: FontWeight.w600,
          ),
        )),
      ),
    ));
  }

  Widget _bodyView() {
    return SizedBox(
      height: _screenHeight,
      width: _screenWidth,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: AppAppBarView.appBarView(
              context: context,
              title: 'Attendance Sheet',
            ),
          ),
          _tobTabBar(),
          selectedTab == 1 ? _signInDetailsView() : _registerDetailsView(),
        ],
      ),
    );
  }

  Widget _registerDetailsView() {
    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          width: 435,
          child: Column(
            children: [
              const Divider(
                height: 1,
                thickness: 0.5,
                color: AppThemeColor.pureBlackColor,
              ),
              const Row(
                children: [
                  SizedBox(
                    height: 25,
                    child: VerticalDivider(
                      width: 1,
                      thickness: 0.5,
                      color: AppThemeColor.pureBlackColor,
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Center(
                      child: Text(
                        '#',
                        style: TextStyle(
                          color: AppThemeColor.pureBlackColor,
                          fontWeight: FontWeight.w700,
                          fontSize: Dimensions.fontSizeLarge,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 25,
                    child: VerticalDivider(
                      width: 1,
                      thickness: 0.5,
                      color: AppThemeColor.pureBlackColor,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: Center(
                      child: Text(
                        'Name',
                        style: TextStyle(
                          color: AppThemeColor.pureBlackColor,
                          fontWeight: FontWeight.w700,
                          fontSize: Dimensions.fontSizeLarge,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 25,
                    child: VerticalDivider(
                      width: 1,
                      thickness: 0.5,
                      color: AppThemeColor.pureBlackColor,
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Center(
                      child: Text(
                        'Date',
                        style: TextStyle(
                          color: AppThemeColor.pureBlackColor,
                          fontWeight: FontWeight.w700,
                          fontSize: Dimensions.fontSizeLarge,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 25,
                    child: VerticalDivider(
                      width: 1,
                      thickness: 0.5,
                      color: AppThemeColor.pureBlackColor,
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Center(
                      child: Text(
                        'Time',
                        style: TextStyle(
                          color: AppThemeColor.pureBlackColor,
                          fontWeight: FontWeight.w700,
                          fontSize: Dimensions.fontSizeLarge,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 25,
                    child: VerticalDivider(
                      width: 1,
                      thickness: 0.5,
                      color: AppThemeColor.pureBlackColor,
                    ),
                  ),
                  // SizedBox(
                  //   width: (201 * questionsList.length).toDouble(),
                  //   height: 25,
                  //   child: ListView.builder(
                  //       itemCount: questionsList.length,
                  //       physics: const NeverScrollableScrollPhysics(),
                  //       scrollDirection: Axis.horizontal,
                  //       itemBuilder: (listContext, index) {
                  //         EventQuestionModel singleQuestion =
                  //             questionsList[index];
                  //         return Row(
                  //           children: [
                  //             SizedBox(
                  //               width: 200,
                  //               child: Center(
                  //                 child: Text(
                  //                   singleQuestion.questionTitle,
                  //                   style: const TextStyle(
                  //                     color: AppThemeColor.pureBlackColor,
                  //                     fontWeight: FontWeight.w700,
                  //                     fontSize: Dimensions.fontSizeLarge,
                  //                   ),
                  //                 ),
                  //               ),
                  //             ),
                  //             const SizedBox(
                  //               height: 25,
                  //               child: VerticalDivider(
                  //                 width: 1,
                  //                 thickness: 0.5,
                  //                 color: AppThemeColor.pureBlackColor,
                  //               ),
                  //             ),
                  //           ],
                  //         );
                  //       }),
                  // ),
                ],
              ),
              const Divider(
                height: 1,
                thickness: 0.5,
                color: AppThemeColor.pureBlackColor,
              ),
              Expanded(
                  child: SizedBox(
                width: 435,
                child: ListView.builder(
                    itemCount: registerAttendanceList.length,
                    itemBuilder: (listContext, index) {
                      AttendanceModel singleAttendance =
                          registerAttendanceList[index];
                      return Column(
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                height: 25,
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 0.5,
                                  color: AppThemeColor.pureBlackColor,
                                ),
                              ),
                              SizedBox(
                                width: 30,
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: AppThemeColor.dullFontColor,
                                      fontWeight: FontWeight.w400,
                                      fontSize: Dimensions.fontSizeLarge,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 25,
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 0.5,
                                  color: AppThemeColor.pureBlackColor,
                                ),
                              ),
                              SizedBox(
                                width: 200,
                                child: Container(
                                  color: Colors.transparent,
                                  child: Center(
                                    child: Text(
                                      singleAttendance.userName,
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppThemeColor.dullFontColor,
                                        fontWeight: FontWeight.w400,
                                        fontSize: Dimensions.fontSizeLarge,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 25,
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 0.5,
                                  color: AppThemeColor.pureBlackColor,
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Center(
                                  child: Text(
                                    DateFormat('MM/dd/yy').format(
                                      singleAttendance.attendanceDateTime,
                                    ),
                                    style: const TextStyle(
                                      color: AppThemeColor.dullFontColor,
                                      fontWeight: FontWeight.w400,
                                      fontSize: Dimensions.fontSizeSmall,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 25,
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 0.5,
                                  color: AppThemeColor.pureBlackColor,
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Center(
                                  child: Text(
                                    DateFormat('KK:mm a').format(
                                      singleAttendance.attendanceDateTime,
                                    ),
                                    style: const TextStyle(
                                      color: AppThemeColor.dullFontColor,
                                      fontWeight: FontWeight.w400,
                                      fontSize: Dimensions.fontSizeSmall,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 25,
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 0.5,
                                  color: AppThemeColor.pureBlackColor,
                                ),
                              ),
                              // SizedBox(
                              //   width: (201 * questionsList.length).toDouble(),
                              //   height: 25,
                              //   child: ListView.builder(
                              //       itemCount: questionsList.length,
                              //       physics:
                              //           const NeverScrollableScrollPhysics(),
                              //       scrollDirection: Axis.horizontal,
                              //       itemBuilder: (listContext, index) {
                              //         EventQuestionModel singleQuestion =
                              //             questionsList[index];
                              //         return Row(
                              //           children: [
                              //             SizedBox(
                              //               width: 200,
                              //               child: Center(
                              //                 child: Text(
                              //                   getSingleQuestionAnswer(
                              //                     questionTitle: singleQuestion
                              //                         .questionTitle,
                              //                     answers:
                              //                         singleAttendance.answers,
                              //                   ),
                              //                   style: const TextStyle(
                              //                     color: AppThemeColor
                              //                         .dullFontColor,
                              //                     fontWeight: FontWeight.w400,
                              //                     fontSize:
                              //                         Dimensions.fontSizeSmall,
                              //                   ),
                              //                 ),
                              //               ),
                              //             ),
                              //             const SizedBox(
                              //               height: 25,
                              //               child: VerticalDivider(
                              //                 width: 1,
                              //                 thickness: 0.5,
                              //                 color:
                              //                     AppThemeColor.pureBlackColor,
                              //               ),
                              //             ),
                              //           ],
                              //         );
                              //       }),
                              // ),
                            ],
                          ),
                          const Divider(
                            height: 1,
                            thickness: 0.5,
                            color: AppThemeColor.pureBlackColor,
                          ),
                        ],
                      );
                    }),
              ))
            ],
          ),
        ),
      ),
    );
  }

  Widget _signInDetailsView() {
    return Expanded(
      child: Column(
        children: [
          // Add Name Button
          Padding(
            padding:
                const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkGreenColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Add Name',
                      style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    final name = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        String inputName = '';
                        return AlertDialog(
                          title: const Text('Add Name to Attendance'),
                          content: TextField(
                            autofocus: true,
                            decoration:
                                const InputDecoration(hintText: 'Enter name'),
                            onChanged: (value) => inputName = value,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                if (inputName.trim().isNotEmpty) {
                                  Navigator.pop(context, inputName.trim());
                                }
                              },
                              child: const Text('Add'),
                            ),
                          ],
                        );
                      },
                    );
                    if (name != null && name.isNotEmpty) {
                      await _addManualAttendance(name);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              interactive: true,
              trackVisibility: true,
              thickness: 5,
              scrollbarOrientation: ScrollbarOrientation.top,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _scrollController,
                child: SizedBox(
                  width: 415 + (questionsList.length * 211),
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      const Divider(
                        height: 1,
                        thickness: 0.5,
                        color: AppThemeColor.pureBlackColor,
                      ),
                      Row(
                        children: [
                          const SizedBox(
                            height: 25,
                            child: VerticalDivider(
                              width: 1,
                              thickness: 0.5,
                              color: AppThemeColor.pureBlackColor,
                            ),
                          ),
                          const SizedBox(
                            width: 30,
                            child: Center(
                              child: Text(
                                '#',
                                style: TextStyle(
                                  color: AppThemeColor.pureBlackColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: Dimensions.fontSizeLarge,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 25,
                            child: VerticalDivider(
                              width: 1,
                              thickness: 0.5,
                              color: AppThemeColor.pureBlackColor,
                            ),
                          ),
                          const SizedBox(
                            width: 200,
                            child: Center(
                              child: Text(
                                'Name',
                                style: TextStyle(
                                  color: AppThemeColor.pureBlackColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: Dimensions.fontSizeLarge,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 25,
                            child: VerticalDivider(
                              width: 1,
                              thickness: 0.5,
                              color: AppThemeColor.pureBlackColor,
                            ),
                          ),
                          const SizedBox(
                            width: 90,
                            child: Center(
                              child: Text(
                                'Date',
                                style: TextStyle(
                                  color: AppThemeColor.pureBlackColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: Dimensions.fontSizeLarge,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 25,
                            child: VerticalDivider(
                              width: 1,
                              thickness: 0.5,
                              color: AppThemeColor.pureBlackColor,
                            ),
                          ),
                          const SizedBox(
                            width: 90,
                            child: Center(
                              child: Text(
                                'Time',
                                style: TextStyle(
                                  color: AppThemeColor.pureBlackColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: Dimensions.fontSizeLarge,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            height: 25,
                            child: VerticalDivider(
                              width: 1,
                              thickness: 0.5,
                              color: AppThemeColor.pureBlackColor,
                            ),
                          ),
                          SizedBox(
                            width: (201 * questionsList.length).toDouble(),
                            height: 25,
                            child: ListView.builder(
                                itemCount: questionsList.length,
                                physics: const NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                itemBuilder: (listContext, index) {
                                  EventQuestionModel singleQuestion =
                                      questionsList[index];
                                  return Row(
                                    children: [
                                      SizedBox(
                                        width: 200,
                                        child: Center(
                                          child: Text(
                                            singleQuestion.questionTitle,
                                            style: const TextStyle(
                                              color:
                                                  AppThemeColor.pureBlackColor,
                                              fontWeight: FontWeight.w700,
                                              fontSize:
                                                  Dimensions.fontSizeLarge,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 25,
                                        child: VerticalDivider(
                                          width: 1,
                                          thickness: 0.5,
                                          color: AppThemeColor.pureBlackColor,
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                          ),
                        ],
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.5,
                        color: AppThemeColor.pureBlackColor,
                      ),
                      Expanded(
                          child: SizedBox(
                        width: 415 + (questionsList.length * 208),
                        child: ListView.builder(
                            itemCount: attendanceList.length,
                            itemBuilder: (listContext, index) {
                              AttendanceModel singleAttendance =
                                  attendanceList[index];
                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      const SizedBox(
                                        height: 25,
                                        child: VerticalDivider(
                                          width: 1,
                                          thickness: 0.5,
                                          color: AppThemeColor.pureBlackColor,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 30,
                                        child: Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: const TextStyle(
                                              color:
                                                  AppThemeColor.dullFontColor,
                                              fontWeight: FontWeight.w400,
                                              fontSize:
                                                  Dimensions.fontSizeLarge,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 25,
                                        child: VerticalDivider(
                                          width: 1,
                                          thickness: 0.5,
                                          color: AppThemeColor.pureBlackColor,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 200,
                                        child: GestureDetector(
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              builder: (BuildContext context) {
                                                return AttendanceAnswersPopup(
                                                  attendance: singleAttendance,
                                                  eventModel: widget.eventModel,
                                                );
                                              },
                                            );
                                          },
                                          child: Container(
                                            color: Colors.transparent,
                                            child: Center(
                                              child: Text(
                                                singleAttendance.userName,
                                                maxLines: 1,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: AppThemeColor
                                                      .dullFontColor,
                                                  fontWeight: FontWeight.w400,
                                                  fontSize:
                                                      Dimensions.fontSizeLarge,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 25,
                                        child: VerticalDivider(
                                          width: 1,
                                          thickness: 0.5,
                                          color: AppThemeColor.pureBlackColor,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 90,
                                        child: Center(
                                          child: Text(
                                            DateFormat('MM/dd/yy').format(
                                              singleAttendance
                                                  .attendanceDateTime,
                                            ),
                                            style: const TextStyle(
                                              color:
                                                  AppThemeColor.dullFontColor,
                                              fontWeight: FontWeight.w400,
                                              fontSize:
                                                  Dimensions.fontSizeSmall,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 25,
                                        child: VerticalDivider(
                                          width: 1,
                                          thickness: 0.5,
                                          color: AppThemeColor.pureBlackColor,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 90,
                                        child: Center(
                                          child: Text(
                                            DateFormat('KK:mm a').format(
                                              singleAttendance
                                                  .attendanceDateTime,
                                            ),
                                            style: const TextStyle(
                                              color:
                                                  AppThemeColor.dullFontColor,
                                              fontWeight: FontWeight.w400,
                                              fontSize:
                                                  Dimensions.fontSizeSmall,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 25,
                                        child: VerticalDivider(
                                          width: 1,
                                          thickness: 0.5,
                                          color: AppThemeColor.pureBlackColor,
                                        ),
                                      ),
                                      SizedBox(
                                        width: (201 * questionsList.length)
                                            .toDouble(),
                                        height: 25,
                                        child: ListView.builder(
                                            itemCount: questionsList.length,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            scrollDirection: Axis.horizontal,
                                            itemBuilder: (listContext, index) {
                                              EventQuestionModel
                                                  singleQuestion =
                                                  questionsList[index];
                                              return Row(
                                                children: [
                                                  SizedBox(
                                                    width: 200,
                                                    child: Center(
                                                      child: Text(
                                                        getSingleQuestionAnswer(
                                                          questionTitle:
                                                              singleQuestion
                                                                  .questionTitle,
                                                          answers:
                                                              singleAttendance
                                                                  .answers,
                                                        ),
                                                        style: const TextStyle(
                                                          color: AppThemeColor
                                                              .dullFontColor,
                                                          fontWeight:
                                                              FontWeight.w400,
                                                          fontSize: Dimensions
                                                              .fontSizeSmall,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    height: 25,
                                                    child: VerticalDivider(
                                                      width: 1,
                                                      thickness: 0.5,
                                                      color: AppThemeColor
                                                          .pureBlackColor,
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }),
                                      ),
                                    ],
                                  ),
                                  const Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: AppThemeColor.pureBlackColor,
                                  ),
                                ],
                              );
                            }),
                      ))
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String getSingleQuestionAnswer(
      {required String questionTitle, required List<String> answers}) {
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

  Future<void> exportToExcel(List<List<String>> data) async {
    final excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    CellStyle cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.black,
        fontFamily: getFontFamily(FontFamily.Calibri));

    cellStyle.underline = Underline.Single; // or Underline.Double

    var cell = sheetObject.cell(CellIndex.indexByString('A1'));
    cell.value = null; // removing any value
    cell.value = TextCellValue('Some Text');
    cell.value = IntCellValue(8);
    cell.value = BoolCellValue(true);
    cell.value = DoubleCellValue(13.37);
    cell.value = DateCellValue(year: 2023, month: 4, day: 20);
    cell.value = TimeCellValue(hour: 20, minute: 15, second: 5, millisecond: 0);
    cell.value =
        DateTimeCellValue(year: 2023, month: 4, day: 20, hour: 15, minute: 1);
    cell.cellStyle = cellStyle;

// setting the number style
    cell.cellStyle = (cell.cellStyle ?? CellStyle()).copyWith(
      /// for IntCellValue, DoubleCellValue and BoolCellValue use;
      numberFormat: CustomNumericNumFormat(formatCode: '#,##0.00 \\m\\²'),

      // The numberFormat changes automatially if you set a CellValue that
      // does not work with the numberFormat set previously. So in case you
      // want to set a new value, e.g. from a date to a decimal number,
      // make sure you set the new value first and then your custom
      // numberFormat).
    );

// printing cell-type
//     print('CellType: ' + switch(cell.value) {
//       null => 'empty cell',
//       TextCellValue() => 'text',
//       FormulaCellValue() => 'formula',
//       IntCellValue() => 'int',
//       BoolCellValue() => 'bool',
//       DoubleCellValue() => 'double',
//       DateCellValue() => 'date',
//       TimeCellValue => 'time',
//       DateTimeCellValue => 'date with time',
//     });

    ///
    /// Inserting and removing column and rows

// insert column at index = 8
    sheetObject.insertColumn(8);

// remove column at index = 18
    sheetObject.removeColumn(18);

// insert row at index = 82
    sheetObject.insertRow(82);

// remove row at index = 80
    sheetObject.removeRow(80);

    // Save the file
    Directory appDocumentsDirectory = await getApplicationDocumentsDirectory();
    String appDocumentsPath = appDocumentsDirectory.path;
    String filePath = '$appDocumentsPath/example.xlsx';

    excel.save(fileName: eventModel.title);

    // Open the file
    ProcessResult result = await Process.run('open', [filePath]);
    print(result.stdout);
  }
}
