import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orgami/models/badge_model.dart';
import 'package:orgami/Services/badge_service.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/screens/Badge/widgets/professional_badge_widget.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shimmer/shimmer.dart';

class BadgeScreen extends StatefulWidget {
  const BadgeScreen({Key? key}) : super(key: key);

  @override
  State<BadgeScreen> createState() => _BadgeScreenState();
}

class _BadgeScreenState extends State<BadgeScreen>
    with TickerProviderStateMixin {
  BadgeModel? userBadge;
  List<BadgeModel> leaderboard = [];
  bool isLoading = true;
  bool isRefreshing = false;
  int selectedTabIndex = 0;
  
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _progressController;
  
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadBadgeData();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOutCirc),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _loadBadgeData() async {
    if (CustomerController.logeInCustomer == null) {
      setState(() {
        isLoading = false;
      });
      ShowToast().showNormalToast(msg: 'Please log in to view your badge');
      return;
    }

    try {
      setState(() {
        isLoading = true;
      });

      // Load user badge and leaderboard in parallel
      final results = await Future.wait([
        BadgeService().getUserBadge(CustomerController.logeInCustomer!.uid),
        BadgeService().getBadgeLeaderboard(limit: 10),
      ]);

      setState(() {
        userBadge = results[0] as BadgeModel?;
        leaderboard = results[1] as List<BadgeModel>;
        isLoading = false;
      });

      // Start animations
      _fadeController.forward();
      _slideController.forward();
      _progressController.forward();

    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ShowToast().showNormalToast(msg: 'Failed to load badge data: $e');
    }
  }

  Future<void> _refreshBadge() async {
    if (isRefreshing || CustomerController.logeInCustomer == null) return;

    try {
      setState(() {
        isRefreshing = true;
      });

      final refreshedBadge = await BadgeService().createOrUpdateUserBadge(
        CustomerController.logeInCustomer!.uid,
      );

      setState(() {
        userBadge = refreshedBadge;
        isRefreshing = false;
      });

      // Restart progress animation
      _progressController.reset();
      _progressController.forward();

      ShowToast().showNormalToast(msg: 'Badge updated successfully!');
    } catch (e) {
      setState(() {
        isRefreshing = false;
      });
      ShowToast().showNormalToast(msg: 'Failed to refresh badge: $e');
    }
  }

  Future<void> _shareBadge() async {
    if (userBadge == null) return;

    try {
      // Generate a simple text share for now
      final shareText = '''
🏆 Check out my ${userBadge!.badgeLevel} Badge!

👤 ${userBadge!.userName}
🎯 ${userBadge!.totalPoints} Total Points
📅 Events Created: ${userBadge!.eventsCreated}
👥 Events Attended: ${userBadge!.eventsAttended}
📆 Member Since: ${userBadge!.memberSince.year}

#EventBadge #${userBadge!.badgeLevel}Member
      '''.trim();

      await Share.share(shareText);
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to share badge');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColor.backGroundColor,
      appBar: AppBar(
        title: const Text(
          'My Badge',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppThemeColor.pureBlackColor,
          ),
        ),
        backgroundColor: AppThemeColor.backGroundColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppThemeColor.pureBlackColor),
        actions: [
          if (userBadge != null) ...[
            IconButton(
              icon: isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _refreshBadge,
              tooltip: 'Refresh Badge',
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareBadge,
              tooltip: 'Share Badge',
            ),
          ],
        ],
      ),
      body: isLoading ? _buildLoadingState() : _buildContent(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppThemeColor.darkBlueColor),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading your badge...',
            style: TextStyle(
              color: AppThemeColor.dullFontColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (userBadge == null) {
      return _buildErrorState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main badge display
              Center(
                child: ProfessionalBadgeWidget(
                  badge: userBadge!,
                  onTap: () => _showBadgeDetails(),
                ),
              ),

              const SizedBox(height: 24),

              // Tab selector
              _buildTabSelector(),

              const SizedBox(height: 16),

              // Tab content
              if (selectedTabIndex == 0) _buildProgressTab(),
              if (selectedTabIndex == 1) _buildAchievementsTab(),
              if (selectedTabIndex == 2) _buildLeaderboardTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: AppThemeColor.dullFontColor,
          ),
          const SizedBox(height: 16),
          Text(
            'Unable to load your badge',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppThemeColor.dullFontColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please check your connection and try again',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppThemeColor.lightGrayColor,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadBadgeData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemeColor.darkBlueColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    final tabs = ['Progress', 'Achievements', 'Leaderboard'];

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: AppThemeColor.cardBackGroundColor,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: AppThemeColor.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final title = entry.value;
          final isSelected = selectedTabIndex == index;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  selectedTabIndex = index;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppThemeColor.buttonGradient : null,
                  color: isSelected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : AppThemeColor.dullFontColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProgressTab() {
    final pointsForNext = userBadge!.getPointsForNextLevel();
    final nextLevel = userBadge!.getNextBadgeLevel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress to next level
        _buildProgressCard(
          title: 'Progress to $nextLevel',
          subtitle: pointsForNext > 0
              ? '$pointsForNext points needed'
              : 'Maximum level reached!',
          progress: pointsForNext > 0
              ? 1.0 - (pointsForNext / _getPointsForLevel(nextLevel))
              : 1.0,
          color: AppThemeColor.darkBlueColor,
        ),

        const SizedBox(height: 16),

        // Statistics breakdown
        Text(
          'Your Statistics',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppThemeColor.pureBlackColor,
          ),
        ),

        const SizedBox(height: 12),

        _buildStatisticsGrid(),
      ],
    );
  }

  Widget _buildProgressCard({
    required String title,
    required String subtitle,
    required double progress,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColor.cardBackGroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppThemeColor.borderColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppThemeColor.pureBlackColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: AppThemeColor.dullFontColor,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) {
              return LinearProgressIndicator(
                value: progress * _progressAnimation.value,
                backgroundColor: AppThemeColor.borderColor,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsGrid() {
    final stats = [
      {
        'title': 'Events Created',
        'value': userBadge!.eventsCreated.toString(),
        'icon': Icons.event_note,
        'color': AppThemeColor.darkBlueColor,
      },
      {
        'title': 'Events Attended',
        'value': userBadge!.eventsAttended.toString(),
        'icon': Icons.person,
        'color': AppThemeColor.darkGreenColor,
      },
      {
        'title': 'Total Attendees',
        'value': userBadge!.totalAttendeeCount.toString(),
        'icon': Icons.groups,
        'color': AppThemeColor.orangeColor,
      },
      {
        'title': 'Active Months',
        'value': userBadge!.consecutiveMonthsActive.toString(),
        'icon': Icons.calendar_today,
        'color': AppThemeColor.dullBlueColor,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppThemeColor.cardBackGroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppThemeColor.borderColor,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                stat['icon'] as IconData,
                color: stat['color'] as Color,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                stat['value'] as String,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColor.pureBlackColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stat['title'] as String,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppThemeColor.dullFontColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAchievementsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Achievements',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppThemeColor.pureBlackColor,
          ),
        ),
        const SizedBox(height: 16),
        _buildAchievementsList(),
      ],
    );
  }

  Widget _buildAchievementsList() {
    final achievements = _generateAchievements();
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: achievements.length,
      itemBuilder: (context, index) {
        final achievement = achievements[index];
        return _buildAchievementItem(achievement);
      },
    );
  }

  Widget _buildAchievementItem(Map<String, dynamic> achievement) {
    final isUnlocked = achievement['unlocked'] as bool;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUnlocked
            ? AppThemeColor.cardBackGroundColor
            : AppThemeColor.cardBackGroundColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnlocked
              ? AppThemeColor.darkGreenColor.withOpacity(0.3)
              : AppThemeColor.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isUnlocked
                  ? AppThemeColor.darkGreenColor
                  : AppThemeColor.dullIconColor,
            ),
            child: Icon(
              achievement['icon'] as IconData,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement['title'] as String,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isUnlocked
                        ? AppThemeColor.pureBlackColor
                        : AppThemeColor.dullFontColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  achievement['description'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColor.dullFontColor,
                  ),
                ),
              ],
            ),
          ),
          if (isUnlocked)
            Icon(
              Icons.check_circle,
              color: AppThemeColor.darkGreenColor,
              size: 24,
            ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    if (leaderboard.isEmpty) {
      return Center(
        child: Text(
          'No leaderboard data available',
          style: TextStyle(
            color: AppThemeColor.dullFontColor,
            fontSize: 16,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Badge Holders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppThemeColor.pureBlackColor,
          ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leaderboard.length,
          itemBuilder: (context, index) {
            final badge = leaderboard[index];
            final isCurrentUser = badge.userId == userBadge?.userId;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCurrentUser
                    ? AppThemeColor.darkBlueColor.withOpacity(0.1)
                    : AppThemeColor.cardBackGroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCurrentUser
                      ? AppThemeColor.darkBlueColor
                      : AppThemeColor.borderColor,
                  width: isCurrentUser ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Rank
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index < 3
                          ? [Colors.amber, Colors.grey, Colors.brown][index]
                          : AppThemeColor.dullFontColor,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // User info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              badge.userName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppThemeColor.pureBlackColor,
                              ),
                            ),
                            if (isCurrentUser) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppThemeColor.darkBlueColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'YOU',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${badge.badgeLevel} • ${badge.totalPoints} points',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppThemeColor.dullFontColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Badge level indicator
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: badge.getBadgeGradient()
                            .map((color) => Color(
                                int.parse(color.substring(1), radix: 16) + 0xFF000000))
                            .toList(),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        badge.badgeLevel[0],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _showBadgeDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        'Badge Details',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColor.pureBlackColor,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ProfessionalBadgeWidget(
                        badge: userBadge!,
                        width: 350,
                        height: 220,
                      ),
                      // Add more badge details here if needed
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _generateAchievements() {
    return [
      {
        'title': 'First Event',
        'description': 'Create your first event',
        'icon': Icons.star,
        'unlocked': userBadge!.eventsCreated >= 1,
      },
      {
        'title': 'Event Creator',
        'description': 'Create 5 events',
        'icon': Icons.event_note,
        'unlocked': userBadge!.eventsCreated >= 5,
      },
      {
        'title': 'Social Butterfly',
        'description': 'Attend 10 events',
        'icon': Icons.people,
        'unlocked': userBadge!.eventsAttended >= 10,
      },
      {
        'title': 'Community Builder',
        'description': 'Have 50 people attend your events',
        'icon': Icons.groups,
        'unlocked': userBadge!.totalAttendeeCount >= 50,
      },
      {
        'title': 'Consistent Creator',
        'description': 'Stay active for 3 consecutive months',
        'icon': Icons.calendar_today,
        'unlocked': userBadge!.consecutiveMonthsActive >= 3,
      },
      {
        'title': 'Point Master',
        'description': 'Earn 1,000 total points',
        'icon': Icons.star_border,
        'unlocked': userBadge!.totalPoints >= 1000,
      },
    ];
  }

  int _getPointsForLevel(String level) {
    switch (level) {
      case 'Silver':
        return 500;
      case 'Gold':
        return 2000;
      case 'Platinum':
        return 5000;
      case 'Diamond':
        return 10000;
      default:
        return 500;
    }
  }
}