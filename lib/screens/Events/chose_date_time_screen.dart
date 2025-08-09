import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orgami/screens/Events/chose_sign_in_methods_screen.dart';
import 'package:orgami/Utils/router.dart';

class ChoseDateTimeScreen extends StatefulWidget {
  const ChoseDateTimeScreen({super.key});

  @override
  State<ChoseDateTimeScreen> createState() => _ChoseDateTimeScreenState();
}

class _ChoseDateTimeScreenState extends State<ChoseDateTimeScreen>
    with TickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  DateTime? selectedDate;
  DateTime todayDate = DateTime.now();
  // Start and end time for the event
  TimeOfDay? startTime;
  TimeOfDay? endTime;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2026),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF667EEA),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1A1A1A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> _selectStartTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: startTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF667EEA),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1A1A1A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != startTime) {
      setState(() {
        startTime = picked;
        // Reset end time if it's before the new start time
        if (endTime != null) {
          final startMinutes = (startTime!.hour * 60) + startTime!.minute;
          final endMinutes = (endTime!.hour * 60) + endTime!.minute;
          if (endMinutes <= startMinutes) {
            endTime = null;
          }
        }
      });
    }
  }

  Future<void> _selectEndTime(BuildContext context) async {
    final TimeOfDay initialEnd =
        endTime ??
        (startTime != null
            ? TimeOfDay(
                hour: (startTime!.hour + 1) % 24,
                minute: startTime!.minute,
              )
            : TimeOfDay.now());

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialEnd,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF667EEA),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1A1A1A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      // Ensure end time is after start time (same day). If invalid, keep previous or null.
      if (startTime != null) {
        final startMinutes = (startTime!.hour * 60) + startTime!.minute;
        final endMinutes = (picked.hour * 60) + picked.minute;
        if (endMinutes > startMinutes) {
          setState(() => endTime = picked);
        } else {
          // If invalid, just ignore; a small UX hint could be added with a SnackBar
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('End time must be after start time'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // If no start time yet, set end time and let user pick start; but better to require start first
        setState(() => endTime = picked);
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // Initialize fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    // Initialize slide animation
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: FadeTransition(opacity: _fadeAnimation, child: _bodyView()),
      ),
    );
  }

  Widget _bodyView() {
    return SizedBox(
      width: _screenWidth,
      height: _screenHeight,
      child: Column(
        children: [
          _headerView(),
          Expanded(child: _contentView()),
        ],
      ),
    );
  }

  Widget _headerView() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        children: [
          // Back button and title
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Choose Date & Time',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Subtitle
          const Text(
            'Select when your event will take place',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'Roboto',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _contentView() {
    return SlideTransition(
      position: _slideAnimation,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Date Selection Card
            _buildSelectionCard(
              icon: Icons.calendar_month_rounded,
              title: selectedDate != null
                  ? 'Selected Date'
                  : 'Choose Your Date',
              subtitle: selectedDate != null
                  ? DateFormat('EEEE, MMMM dd, yyyy').format(selectedDate!)
                  : 'Tap to select a date',
              isSelected: selectedDate != null,
              onTap: () => _selectDate(context),
            ),
            const SizedBox(height: 20),
            // Start Time Selection Card
            _buildSelectionCard(
              icon: Icons.play_circle_fill_rounded,
              title: startTime != null ? 'Start Time' : 'Choose Start Time',
              subtitle: startTime != null
                  ? DateFormat('KK:mm a').format(
                      DateTime(
                        selectedDate?.year ?? DateTime.now().year,
                        selectedDate?.month ?? DateTime.now().month,
                        selectedDate?.day ?? DateTime.now().day,
                        startTime!.hour,
                        startTime!.minute,
                      ),
                    )
                  : 'Tap to select start time',
              isSelected: startTime != null,
              onTap: () => _selectStartTime(context),
            ),
            const SizedBox(height: 12),
            // End Time Selection Card
            _buildSelectionCard(
              icon: Icons.stop_circle_rounded,
              title: endTime != null ? 'End Time' : 'Choose End Time',
              subtitle: endTime != null
                  ? DateFormat('KK:mm a').format(
                      DateTime(
                        selectedDate?.year ?? DateTime.now().year,
                        selectedDate?.month ?? DateTime.now().month,
                        selectedDate?.day ?? DateTime.now().day,
                        endTime!.hour,
                        endTime!.minute,
                      ),
                    )
                  : (startTime == null
                        ? 'Pick start time first'
                        : 'Tap to select end time'),
              isSelected: endTime != null,
              onTap: startTime == null
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a start time first'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  : () => _selectEndTime(context),
            ),
            const Spacer(),
            // Continue Button
            if (_canContinue) _buildContinueButton(),
          ],
        ),
      ),
    );
  }

  bool get _canContinue {
    if (selectedDate == null || startTime == null || endTime == null)
      return false;
    final startMinutes = (startTime!.hour * 60) + startTime!.minute;
    final endMinutes = (endTime!.hour * 60) + endTime!.minute;
    return endMinutes > startMinutes;
  }

  Widget _buildSelectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                spreadRadius: 0,
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF667EEA)
                  : Colors.grey.withValues(alpha: 0.2),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isSelected
                        ? const [Color(0xFF667EEA), Color(0xFF764BA2)]
                        : [
                            Colors.grey.withValues(alpha: 0.1),
                            Colors.grey.withValues(alpha: 0.1),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : const Color(0xFF667EEA),
                  size: 28,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFF6B7280),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF667EEA)
                            : const Color(0xFF9CA3AF),
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: isSelected
                    ? const Color(0xFF667EEA)
                    : const Color(0xFF9CA3AF),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.3),
            spreadRadius: 0,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Build start DateTime
            final DateTime startDateTime = DateTime(
              selectedDate!.year,
              selectedDate!.month,
              selectedDate!.day,
              startTime!.hour,
              startTime!.minute,
            );
            // Compute duration in whole hours (ceil), min 1 hour
            final int diffMinutes =
                (endTime!.hour * 60 + endTime!.minute) -
                (startTime!.hour * 60 + startTime!.minute);
            int durationHours = (diffMinutes / 60).ceil();
            if (durationHours < 1) durationHours = 1;

            RouterClass.nextScreenNormal(
              context,
              ChoseSignInMethodsScreen(
                selectedDateTime: startDateTime,
                eventDurationHours: durationHours,
              ),
            );
          },
          child: const Center(
            child: Text(
              'Continue',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
