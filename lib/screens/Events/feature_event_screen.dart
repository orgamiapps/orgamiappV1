import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/payment_model.dart';
import 'package:attendus/Services/payment_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';

class FeatureEventScreen extends StatefulWidget {
  final EventModel eventModel;
  const FeatureEventScreen({super.key, required this.eventModel});

  @override
  State<FeatureEventScreen> createState() => _FeatureEventScreenState();
}

class _FeatureEventScreenState extends State<FeatureEventScreen>
    with TickerProviderStateMixin {
  int? _selectedDays;
  bool _loading = false;
  final List<int> _tiers = [3, 7, 14];
  bool _untilEvent = false;
  String? _currentPaymentIntentId;
  String? _clientSecret;

  // Animation controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // Event status computed properties
  bool get _isEventPassed {
    final DateTime now = DateTime.now();
    final DateTime eventDateTime = widget.eventModel.selectedDateTime;
    return eventDateTime.isBefore(now);
  }

  bool get _canFeatureEvent {
    return !_isEventPassed && !widget.eventModel.isFeatured;
  }

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

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
    final event = widget.eventModel;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              AppAppBarView.modernHeader(
                context: context,
                title: 'Feature Your Event',
                subtitle:
                    'Boost your event visibility and attract more attendees',
              ),
              Expanded(
                child: SlideTransition(
                  position: _slideAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBenefitsSection(),
                        const SizedBox(height: 24),
                        if (_isEventPassed) ...[
                          _buildEventPassedSection(),
                          const SizedBox(height: 24),
                        ],
                        if (widget.eventModel.isFeatured &&
                            !_isEventPassed) ...[
                          _buildAlreadyFeaturedSection(),
                          const SizedBox(height: 24),
                        ],
                        _buildEventPreviewCard(event),
                        if (_canFeatureEvent) ...[
                          const SizedBox(height: 32),
                          _buildDurationSection(),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
              _buildFeatureButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.star,
                  color: Color(0xFFFF9800),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Benefits',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildBenefitItem(
            icon: Icons.push_pin,
            title: 'Pin at top of home screen',
            description: 'Your event will appear prominently to all users',
          ),
          const SizedBox(height: 12),
          _buildBenefitItem(
            icon: Icons.trending_up,
            title: 'Attract more attendees',
            description: 'Increased visibility leads to higher attendance',
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFFFF9800), size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                  fontFamily: 'Roboto',
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventPreviewCard(EventModel event) {
    return Container(
      width: double.infinity,
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
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: CachedNetworkImage(
              imageUrl: event.imageUrl,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                height: 160,
                color: const Color(0xFFF5F7FA),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF667EEA)),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                height: 160,
                color: const Color(0xFFF5F7FA),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_not_supported,
                        color: Color(0xFF667EEA),
                        size: 48,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Image not available',
                        style: TextStyle(
                          color: Color(0xFF667EEA),
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    fontFamily: 'Roboto',
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat(
                    'EEEE, MMMM dd yyyy',
                  ).format(event.selectedDateTime),
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                    fontFamily: 'Roboto',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventPassedSection() {
    final DateTime eventDateTime = widget.eventModel.selectedDateTime;
    final String formattedDate = DateFormat(
      'MMMM d, yyyy \'at\' h:mm a',
    ).format(eventDateTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.event_busy,
              color: Color(0xFFFF9800),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Event Has Passed',
                  style: TextStyle(
                    color: Color(0xFFE65100),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This event occurred on $formattedDate. Events can only be featured before their scheduled date.',
                  style: const TextStyle(
                    color: Color(0xFFEF6C00),
                    fontSize: 14,
                    fontFamily: 'Roboto',
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyFeaturedSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.star, color: Color(0xFF4CAF50), size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Event Already Featured',
                  style: TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your event is currently being promoted and will appear in featured listings.',
                  style: TextStyle(
                    color: Color(0xFF388E3C),
                    fontSize: 14,
                    fontFamily: 'Roboto',
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Duration:',
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w600,
            fontSize: 18,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: _tiers.map((days) {
            final isSelected = _selectedDays == days;
            final price = FeaturePaymentModel.getPriceForDays(days);
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    // Toggle selection: if already selected, unselect; otherwise select
                    _selectedDays = (_selectedDays == days) ? null : days;
                    _untilEvent = false;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 80,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFF9800) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF9800)
                          : const Color(0xFFE5E7EB),
                      width: 2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFFFF9800,
                              ).withValues(alpha: 0.3),
                              spreadRadius: 0,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              spreadRadius: 0,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$days days',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${price.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        _buildUntilEventOption(),
      ],
    );
  }

  Widget _buildUntilEventOption() {
    final DateTime now = DateTime.now();
    final DateTime eventTime = widget.eventModel.selectedDateTime;
    final bool eventInPast = eventTime.isBefore(now);
    final String timeLeftLabel = eventInPast
        ? 'Event has started'
        : _formatTimeLeft(now, eventTime);

    // Calculate price based on days until event
    final daysUntilEvent = eventTime.difference(now).inDays;
    final price = daysUntilEvent > 0
        ? FeaturePaymentModel.getPriceForDays(
            FeaturePaymentModel.getPricingTierForDays(daysUntilEvent),
          )
        : 0.0;

    return GestureDetector(
      onTap: eventInPast
          ? null
          : () {
              setState(() {
                _untilEvent = true;
                _selectedDays = null;
              });
            },
      child: Container(
        width: double.infinity,
        height: 80,
        decoration: BoxDecoration(
          color: _untilEvent ? const Color(0xFFFF9800) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _untilEvent
                ? const Color(0xFFFF9800)
                : const Color(0xFFE5E7EB),
            width: 2,
          ),
          boxShadow: _untilEvent
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                    spreadRadius: 0,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    spreadRadius: 0,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Until event takes place ',
                      style: TextStyle(
                        color: _untilEvent
                            ? Colors.white
                            : const Color(0xFF1A1A1A),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    TextSpan(
                      text: '($timeLeftLabel)',
                      style: TextStyle(
                        color: _untilEvent
                            ? Colors.white.withValues(alpha: 0.9)
                            : const Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
              if (daysUntilEvent > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: _untilEvent ? Colors.white : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimeLeft(DateTime from, DateTime to) {
    final Duration diff = to.difference(from);
    if (diff.inSeconds <= 0) return '0m left';

    final int days = diff.inDays;
    final int hours = diff.inHours % 24;
    final int minutes = diff.inMinutes % 60;

    if (days > 0) {
      return '${days}d${hours > 0 ? ', ${hours}h' : ''} left';
    } else if (hours > 0) {
      return '${hours}h${minutes > 0 ? ', ${minutes}m' : ''} left';
    } else {
      return '${minutes}m left';
    }
  }

  Widget _buildFeatureButton() {
    // Determine button state and text
    String buttonText;
    bool isEnabled;
    LinearGradient gradient;
    Color textColor;
    IconData? icon;

    if (_isEventPassed) {
      buttonText = 'Event Has Passed';
      isEnabled = false;
      gradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF3F4F6), Color(0xFFE5E7EB)],
      );
      textColor = const Color(0xFF6B7280);
      icon = Icons.event_busy;
    } else if (widget.eventModel.isFeatured) {
      buttonText = 'Event Already Featured';
      isEnabled = false;
      gradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE8F5E8), Color(0xFFE8F5E8)],
      );
      textColor = const Color(0xFF4CAF50);
      icon = Icons.star;
    } else if (_loading) {
      buttonText = '';
      isEnabled = false;
      gradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
      );
      textColor = Colors.white;
    } else if (_selectedDays != null || _untilEvent) {
      buttonText = 'Pay & Feature Event';
      isEnabled = true;
      gradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
      );
      textColor = Colors.white;
    } else {
      buttonText = 'Select Duration to Feature';
      isEnabled = false;
      gradient = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF3F4F6), Color(0xFFE5E7EB)],
      );
      textColor = const Color(0xFF6B7280);
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                    spreadRadius: 0,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    spreadRadius: 0,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: isEnabled ? _processPaymentAndFeature : null,
            child: Center(
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: textColor, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          buttonText,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _processPaymentAndFeature() async {
    if ((_selectedDays == null && !_untilEvent) ||
        _loading ||
        !_canFeatureEvent)
      return;

    setState(() => _loading = true);

    try {
      // Determine duration in days
      int durationDays;
      if (_untilEvent) {
        final daysUntilEvent = widget.eventModel.selectedDateTime
            .difference(DateTime.now())
            .inDays;
        if (daysUntilEvent <= 0) {
          throw Exception('Event has already started or passed');
        }
        // Use pricing tier for "until event" option
        durationDays = FeaturePaymentModel.getPricingTierForDays(
          daysUntilEvent,
        );
      } else {
        durationDays = _selectedDays!;
      }

      // Create payment intent via Cloud Function
      Logger.debug('Creating payment intent...');
      final paymentData = await PaymentService.createPaymentIntent(
        eventId: widget.eventModel.id,
        durationDays: durationDays,
        customerUid: FirebaseAuth.instance.currentUser!.uid,
      );

      _clientSecret = paymentData['clientSecret'];
      _currentPaymentIntentId = paymentData['paymentIntentId'];

      // Process payment with Stripe
      Logger.debug('Processing payment...');
      final paymentSuccess = await PaymentService.processPayment(
        clientSecret: _clientSecret!,
        eventId: widget.eventModel.id,
      );

      if (paymentSuccess) {
        // Payment successful, now feature the event
        await _featureEventAfterPayment();

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment successful! Your event is now featured!'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      } else {
        throw Exception('Payment was cancelled or failed');
      }
    } catch (e) {
      Logger.error('Payment failed: $e', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _featureEventAfterPayment() async {
    DateTime endDate;
    if (_untilEvent) {
      endDate = widget.eventModel.selectedDateTime;
      if (endDate.isBefore(DateTime.now())) {
        throw Exception('Event start time has already passed.');
      }
    } else {
      endDate = DateTime.now().add(Duration(days: _selectedDays!));
    }

    // Update the event to featured status
    await FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .doc(widget.eventModel.id)
        .update({'isFeatured': true, 'featureEndDate': endDate});

    // Confirm payment in backend
    if (_currentPaymentIntentId != null) {
      final durationDays = _untilEvent
          ? FeaturePaymentModel.getPricingTierForDays(
              widget.eventModel.selectedDateTime
                  .difference(DateTime.now())
                  .inDays,
            )
          : _selectedDays!;

      await PaymentService.confirmFeaturePayment(
        paymentIntentId: _currentPaymentIntentId!,
        eventId: widget.eventModel.id,
        durationDays: durationDays,
        untilEvent: _untilEvent,
      );
    }
  }
}
