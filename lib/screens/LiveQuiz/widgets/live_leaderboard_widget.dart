import 'package:flutter/material.dart';
import 'dart:async';
import 'package:attendus/models/quiz_participant_model.dart';
import 'package:attendus/Services/live_quiz_service.dart';

class LiveLeaderboardWidget extends StatefulWidget {
  final String quizId;
  final int maxVisible;
  final bool showAnimation;

  const LiveLeaderboardWidget({
    super.key,
    required this.quizId,
    this.maxVisible = 10,
    this.showAnimation = true,
  });

  @override
  State<LiveLeaderboardWidget> createState() => _LiveLeaderboardWidgetState();
}

class _LiveLeaderboardWidgetState extends State<LiveLeaderboardWidget>
    with TickerProviderStateMixin {
  final _liveQuizService = LiveQuizService();

  List<QuizParticipantModel> _participants = [];
  Map<String, int> _previousRanks = {};
  StreamSubscription<List<QuizParticipantModel>>? _participantsSubscription;

  // Animation controllers
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;

  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupParticipantsStream();
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _slideController.forward();

    if (widget.showAnimation) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    _participantsSubscription?.cancel();
    super.dispose();
  }

  void _setupParticipantsStream() {
    _participantsSubscription = _liveQuizService
        .getParticipantsStream(widget.quizId)
        .listen((participants) {
          // Store previous ranks for animation
          for (final participant in _participants) {
            _previousRanks[participant.id] = participant.currentRank ?? 999;
          }

          setState(() {
            _participants = participants.take(widget.maxVisible).toList();
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
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
              _buildHeader(),
              Expanded(child: _buildLeaderboard()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.topRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.leaderboard, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Live Leaderboard',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
            ),
          ),
          if (widget.showAnimation)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          if (widget.showAnimation) const SizedBox(width: 8),
          if (widget.showAnimation)
            Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard() {
    if (_participants.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, color: Colors.grey, size: 48),
              SizedBox(height: 16),
              Text(
                'No participants yet',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Participants will appear here once they join',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: _participants.length,
      itemBuilder: (context, index) {
        final participant = _participants[index];
        final previousRank = _previousRanks[participant.id];
        return _buildLeaderboardItem(participant, index, previousRank);
      },
    );
  }

  Widget _buildLeaderboardItem(
    QuizParticipantModel participant,
    int index,
    int? previousRank,
  ) {
    final currentRank = participant.currentRank ?? (index + 1);
    final rankChange = previousRank != null ? previousRank - currentRank : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _getRankColor(currentRank),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _getRankBorderColor(currentRank),
            width: currentRank <= 3 ? 2 : 1,
          ),
          boxShadow: currentRank <= 3
              ? [
                  BoxShadow(
                    color: _getRankBorderColor(
                      currentRank,
                    ).withValues(alpha: 0.3),
                    spreadRadius: 0,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Rank badge
            _buildRankBadge(currentRank),
            const SizedBox(width: 16),

            // Avatar
            _buildAvatar(participant, currentRank),
            const SizedBox(width: 12),

            // Participant info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          participant.displayName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: currentRank <= 3
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (rankChange != 0)
                        _buildRankChangeIndicator(rankChange),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${participant.correctAnswers}/${participant.questionsAnswered} correct',
                        style: TextStyle(
                          fontSize: 12,
                          color: currentRank <= 3
                              ? Colors.white.withValues(alpha: 0.8)
                              : Colors.grey.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${participant.accuracyDisplay})',
                        style: TextStyle(
                          fontSize: 12,
                          color: currentRank <= 3
                              ? Colors.white.withValues(alpha: 0.8)
                              : Colors.grey.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Score
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${participant.currentScore}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: currentRank <= 3
                        ? Colors.white
                        : const Color(0xFF667EEA),
                  ),
                ),
                Text(
                  'pts',
                  style: TextStyle(
                    fontSize: 12,
                    color: currentRank <= 3
                        ? Colors.white.withValues(alpha: 0.8)
                        : Colors.grey.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    final isTopThree = rank <= 3;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isTopThree
            ? Colors.white.withValues(alpha: 0.2)
            : const Color(0xFF667EEA).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTopThree
              ? Colors.white.withValues(alpha: 0.4)
              : const Color(0xFF667EEA).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Center(
        child: isTopThree && rank <= 3
            ? _getRankIcon(rank)
            : Text(
                '$rank',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isTopThree ? Colors.white : const Color(0xFF667EEA),
                ),
              ),
      ),
    );
  }

  Widget _buildAvatar(QuizParticipantModel participant, int rank) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: rank <= 3
            ? Colors.white.withValues(alpha: 0.2)
            : const Color(0xFF667EEA).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          participant.displayName.isNotEmpty
              ? participant.displayName[0].toUpperCase()
              : '?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: rank <= 3 ? Colors.white : const Color(0xFF667EEA),
          ),
        ),
      ),
    );
  }

  Widget _buildRankChangeIndicator(int change) {
    if (change == 0) return const SizedBox();

    final isUp = change > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isUp
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.trending_up : Icons.trending_down,
            size: 12,
            color: isUp ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 2),
          Text(
            '${change.abs()}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isUp ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return Colors.white;
    }
  }

  Color _getRankBorderColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.grey.withValues(alpha: 0.2);
    }
  }

  Widget _getRankIcon(int rank) {
    switch (rank) {
      case 1:
        return const Icon(Icons.emoji_events, color: Colors.white, size: 18);
      case 2:
        return const Icon(Icons.military_tech, color: Colors.white, size: 18);
      case 3:
        return const Icon(
          Icons.workspace_premium,
          color: Colors.white,
          size: 18,
        );
      default:
        return Text(
          '$rank',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        );
    }
  }
}

// Compact version for smaller spaces
class CompactLeaderboardWidget extends StatelessWidget {
  final String quizId;
  final int maxVisible;

  const CompactLeaderboardWidget({
    super.key,
    required this.quizId,
    this.maxVisible = 5,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QuizParticipantModel>>(
      stream: LiveQuizService().getParticipantsStream(quizId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: const Center(
              child: Text(
                'No participants yet',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          );
        }

        final topParticipants = snapshot.data!.take(maxVisible).toList();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Top Players',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              ...topParticipants.take(3).map((participant) {
                final rank = participant.currentRank ?? 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _getCompactRankColor(rank),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$rank',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          participant.displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${participant.currentScore}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF667EEA),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Color _getCompactRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return const Color(0xFF667EEA);
    }
  }
}
