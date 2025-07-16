import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/AppButtons.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';

class FeatureEventScreen extends StatefulWidget {
  final EventModel eventModel;
  const FeatureEventScreen({Key? key, required this.eventModel})
      : super(key: key);

  @override
  State<FeatureEventScreen> createState() => _FeatureEventScreenState();
}

class _FeatureEventScreenState extends State<FeatureEventScreen> {
  int _selectedDays = 7;
  bool _loading = false;

  final List<int> _tiers = [3, 7, 14];

  @override
  Widget build(BuildContext context) {
    final event = widget.eventModel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feature Your Event'),
        backgroundColor: AppThemeColor.darkGreenColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Feature Your Event',
              style: TextStyle(
                fontSize: Dimensions.fontSizeExtraLarge,
                fontWeight: FontWeight.bold,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Benefits:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: Dimensions.fontSizeLarge,
                )),
            const SizedBox(height: 8),
            const BulletPoint(text: 'Pin at top of home screen'),
            const BulletPoint(text: 'Attract more attendees'),
            const SizedBox(height: 20),
            Center(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          event.imageUrl,
                          height: 100,
                          width: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: Dimensions.fontSizeLarge,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        DateFormat('EEEE, MMMM dd yyyy')
                            .format(event.selectedDateTime),
                        style: const TextStyle(
                          color: AppThemeColor.dullFontColor,
                          fontSize: Dimensions.fontSizeDefault,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Choose Duration:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: Dimensions.fontSizeLarge,
                )),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _tiers.map((days) {
                final isSelected = _selectedDays == days;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDays = days;
                    });
                  },
                  child: Card(
                    color: isSelected
                        ? AppThemeColor.darkGreenColor
                        : Colors.white,
                    elevation: isSelected ? 6 : 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected
                            ? AppThemeColor.darkGreenColor
                            : AppThemeColor.grayColor,
                        width: 2,
                      ),
                    ),
                    child: Container(
                      width: 80,
                      height: 60,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$days days',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppThemeColor.darkGreenColor,
                              fontWeight: FontWeight.bold,
                              fontSize: Dimensions.fontSizeLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const Spacer(),
            Center(
              child: GestureDetector(
                onTap: _loading ? null : _featureEvent,
                child: AppButtons.button1(
                  width: double.infinity,
                  height: 50,
                  buttonLoading: _loading,
                  label: 'Feature Now',
                  labelSize: Dimensions.fontSizeLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _featureEvent() async {
    setState(() => _loading = true);
    final endDate = DateTime.now().add(Duration(days: _selectedDays));
    await FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .doc(widget.eventModel.id)
        .update({
      'isFeatured': true,
      'featureEndDate': endDate,
    });
    setState(() => _loading = false);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event is now featured!')),
      );
    }
  }
}

class BulletPoint extends StatelessWidget {
  final String text;
  const BulletPoint({Key? key, required this.text}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(fontSize: 18)),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: Dimensions.fontSizeDefault),
          ),
        ),
      ],
    );
  }
}
