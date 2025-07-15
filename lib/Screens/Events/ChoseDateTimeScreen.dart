import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orgami/Screens/Events/ChoseLocationInMapScreen.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/dimensions.dart';

class ChoseDateTimeScreen extends StatefulWidget {
  const ChoseDateTimeScreen({
    super.key,
  });

  @override
  State<ChoseDateTimeScreen> createState() => _ChoseDateTimeScreenState();
}

class _ChoseDateTimeScreenState extends State<ChoseDateTimeScreen> {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  DateTime? selectedDate;
  DateTime todayDate = DateTime.now();

  TimeOfDay? selectedTime;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2026),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != selectedTime) {
      setState(() {
        selectedTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.pureWhiteColor,
      body: _bodyView(),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      width: _screenWidth,
      height: _screenHeight,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: AppAppBarView.appBarView(
                context: context,
                title: 'Choose Date & Time',
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _selectDate(context),
                    child: Container(
                      width: _screenWidth,
                      decoration: BoxDecoration(
                        color: AppThemeColor.darkGreenColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppThemeColor.darkBlueColor.withOpacity(0.9),
                            spreadRadius: 1,
                            blurRadius: 7,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                      margin: const EdgeInsets.all(25),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.calendar_month_rounded,
                            size: 55,
                            color: AppThemeColor.pureWhiteColor,
                          ),
                          const SizedBox(
                            height: 10,
                          ),
                          Text(
                            selectedDate != null
                                ? 'Selected Date'
                                : 'Choose Your Date',
                            style: const TextStyle(
                              color: AppThemeColor.pureWhiteColor,
                              fontWeight: FontWeight.w700,
                              fontSize: Dimensions.fontSizeLarge,
                            ),
                          ),
                          if (selectedDate != null)
                            const SizedBox(
                              height: 10,
                            ),
                          if (selectedDate != null)
                            Text(
                              DateFormat('dd MMMM yyyy').format(selectedDate!),
                              style: const TextStyle(
                                color: AppThemeColor.dullFontColor,
                                fontWeight: FontWeight.w700,
                                fontSize: Dimensions.fontSizeLarge,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _selectTime(context),
                    child: Container(
                      width: _screenWidth,
                      decoration: BoxDecoration(
                        color: AppThemeColor.darkBlueColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppThemeColor.darkGreenColor.withOpacity(0.9),
                            spreadRadius: 1,
                            blurRadius: 7,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                      margin: const EdgeInsets.all(25),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 55,
                            color: AppThemeColor.pureWhiteColor,
                          ),
                          const SizedBox(
                            height: 10,
                          ),
                          Text(
                            selectedTime != null
                                ? 'Selected Time'
                                : 'Choose Your Time',
                            style: const TextStyle(
                              color: AppThemeColor.pureWhiteColor,
                              fontWeight: FontWeight.w700,
                              fontSize: Dimensions.fontSizeLarge,
                            ),
                          ),
                          if (selectedTime != null)
                            const SizedBox(
                              height: 10,
                            ),
                          if (selectedTime != null)
                            Text(
                              DateFormat('KK:mm a').format(
                                DateTime(
                                  selectedDate!.year,
                                  selectedDate!.month,
                                  selectedDate!.day,
                                  selectedTime!.hour,
                                  selectedTime!.minute,
                                ),
                              ),
                              style: const TextStyle(
                                color: AppThemeColor.pureWhiteColor,
                                fontWeight: FontWeight.w700,
                                fontSize: Dimensions.fontSizeLarge,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selectedDate != null && selectedTime != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: GestureDetector(
                  onTap: () {
                    DateTime selectedDateAndTime = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedTime!.hour,
                      selectedTime!.minute,
                    );

                    RouterClass.nextScreenNormal(
                      context,
                      ChoseLocationInMapScreen(
                          selectedDateTime: selectedDateAndTime),
                    );
                  },
                  child: AppButtons.button1(
                    width: _screenWidth,
                    height: 57,
                    buttonLoading: false,
                    label: 'Continue',
                    labelSize: Dimensions.fontSizeLarge,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
