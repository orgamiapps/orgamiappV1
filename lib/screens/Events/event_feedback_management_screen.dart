import 'package:flutter/material.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/event_feedback_model.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';

class EventFeedbackManagementScreen extends StatefulWidget {
  final EventModel eventModel;

  const EventFeedbackManagementScreen({super.key, required this.eventModel});

  @override
  State<EventFeedbackManagementScreen> createState() =>
      _EventFeedbackManagementScreenState();
}

class _EventFeedbackManagementScreenState
    extends State<EventFeedbackManagementScreen> {
  List<EventFeedbackModel> _feedbackList = [];
  EventFeedbackAnalytics? _feedbackAnalytics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFeedbackData();
  }

  Future<void> _loadFeedbackData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final feedbackList = await FirebaseFirestoreHelper().getEventFeedback(
        eventId: widget.eventModel.id,
      );
      final analytics = await FirebaseFirestoreHelper()
          .getEventFeedbackAnalytics(eventId: widget.eventModel.id);

      setState(() {
        _feedbackList = feedbackList;
        _feedbackAnalytics = analytics;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      Logger.error('Error loading feedback data: $e');
    }
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Text(
                'Event Feedback',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.eventModel.title,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCard() {
    if (_feedbackAnalytics == null || _feedbackAnalytics!.totalRatings == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(Icons.star_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No feedback available yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Feedback will appear once attendees rate your event',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall Rating',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColor.darkBlueColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getSentimentColor(_feedbackAnalytics!.sentiment),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _feedbackAnalytics!.sentiment.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _feedbackAnalytics!.averageRating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.star, size: 48, color: Colors.amber),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_feedbackAnalytics!.totalRatings} total ratings',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Anonymous',
                  _feedbackAnalytics!.anonymousCount.toString(),
                  Icons.person_off,
                  Colors.grey[600]!,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Named',
                  _feedbackAnalytics!.namedCount.toString(),
                  Icons.person,
                  AppThemeColor.darkBlueColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(title, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildRatingDistribution() {
    if (_feedbackAnalytics == null || _feedbackAnalytics!.totalRatings == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rating Distribution',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(5, (index) {
            final rating = 5 - index;
            final count = _feedbackAnalytics!.ratingDistribution[rating] ?? 0;
            final percentage = _feedbackAnalytics!.totalRatings > 0
                ? (count / _feedbackAnalytics!.totalRatings * 100)
                : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Text(
                    '$rating',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.amber,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$count (${percentage.toStringAsFixed(1)}%)',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFeedbackList() {
    if (_feedbackList.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Feedback',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(height: 16),
          ..._feedbackList
              .take(10)
              .map((feedback) => _buildFeedbackItem(feedback)),
        ],
      ),
    );
  }

  Widget _buildFeedbackItem(EventFeedbackModel feedback) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < feedback.rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  );
                }),
              ),
              const SizedBox(width: 8),
              Text(
                '${feedback.rating}/5',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const Spacer(),
              Text(
                _formatTimestamp(feedback.timestamp),
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
          if (feedback.comment != null && feedback.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              feedback.comment!,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                feedback.isAnonymous ? Icons.person_off : Icons.person,
                size: 14,
                color: Colors.grey[500],
              ),
              const SizedBox(width: 4),
              Text(
                feedback.isAnonymous ? 'Anonymous' : 'Named User',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  Color _getSentimentColor(String sentiment) {
    switch (sentiment.toLowerCase()) {
      case 'positive':
        return const Color(0xFF667EEA);
      case 'negative':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppAppBarView.modernHeader(
              context: context,
              title: 'Event Feedback',
              subtitle: 'Manage feedback and reviews for your event',
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadFeedbackData,
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadFeedbackData,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 20),
                            _buildAnalyticsCard(),
                            const SizedBox(height: 20),
                            _buildRatingDistribution(),
                            const SizedBox(height: 20),
                            _buildFeedbackList(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
