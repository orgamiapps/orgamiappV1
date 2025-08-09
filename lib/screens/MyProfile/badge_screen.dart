import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/badge_model.dart';
import '../../Services/badge_service.dart';
import '../../controller/customer_controller.dart';
import '../../Utils/colors.dart';
import '../../Utils/toast.dart';
import 'Widgets/professional_badge_widget.dart';

class BadgeScreen extends StatefulWidget {
  final String? userId;
  final bool isOwnBadge;

  const BadgeScreen({
    Key? key,
    this.userId,
    this.isOwnBadge = true,
  }) : super(key: key);

  @override
  State<BadgeScreen> createState() => _BadgeScreenState();
}

class _BadgeScreenState extends State<BadgeScreen>
    with TickerProviderStateMixin {
  UserBadgeModel? _badge;
  bool _isLoading = true;
  bool _isRefreshing = false;
  final BadgeService _badgeService = BadgeService();
  final GlobalKey _badgeKey = GlobalKey();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadBadge();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadBadge() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final userId = widget.userId ?? CustomerController.logeInCustomer?.uid;
      if (userId == null) {
        ShowToast().showNormalToast(msg: 'User not found');
        Navigator.pop(context);
        return;
      }

      final badge = await _badgeService.getOrGenerateBadge(userId);
      
      if (mounted) {
        setState(() {
          _badge = badge;
          _isLoading = false;
        });

        if (badge != null) {
          _fadeController.forward();
          Future.delayed(const Duration(milliseconds: 200), () {
            _slideController.forward();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading badge: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to load badge');
      }
    }
  }

  Future<void> _refreshBadge() async {
    try {
      setState(() {
        _isRefreshing = true;
      });

      final userId = widget.userId ?? CustomerController.logeInCustomer?.uid;
      if (userId == null) return;

      final badge = await _badgeService.generateUserBadge(userId);
      
      if (mounted) {
        setState(() {
          _badge = badge;
          _isRefreshing = false;
        });
        ShowToast().showNormalToast(msg: 'Badge updated successfully!');
      }
    } catch (e) {
      debugPrint('Error refreshing badge: $e');
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to refresh badge');
      }
    }
  }

  Future<void> _shareBadge() async {
    try {
      if (_badge == null) return;

      // Capture badge as image
      final boundary = _badgeKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final uint8List = byteData.buffer.asUint8List();
      
      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/badge_${_badge!.userName.replaceAll(' ', '_')}.png');
      await file.writeAsBytes(uint8List);

      // Share the image
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out my Orgami Event Badge! 🏆\n\n'
            'Level: ${_badge!.badgeLevel}\n'
            'Events Created: ${_badge!.eventsCreated}\n'
            'Events Attended: ${_badge!.eventsAttended}\n'
            'Member since: ${_badge!.membershipDuration}',
      );

    } catch (e) {
      debugPrint('Error sharing badge: $e');
      ShowToast().showNormalToast(msg: 'Failed to share badge');
    }
  }

  Future<void> _downloadBadge() async {
    try {
      if (_badge == null) return;

      final boundary = _badgeKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final uint8List = byteData.buffer.asUint8List();
      
      // On Android, save to downloads
      if (Platform.isAndroid) {
        final directory = Directory('/storage/emulated/0/Download');
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
        }
        final file = File('${directory.path}/orgami_badge_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(uint8List);
        ShowToast().showNormalToast(msg: 'Badge saved to Downloads!');
      } else {
        // On iOS, save to app documents
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/orgami_badge_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(uint8List);
        ShowToast().showNormalToast(msg: 'Badge saved successfully!');
      }

    } catch (e) {
      debugPrint('Error downloading badge: $e');
      ShowToast().showNormalToast(msg: 'Failed to download badge');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: _buildAppBar(),
      body: _isLoading ? _buildLoadingView() : _buildBadgeView(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        widget.isOwnBadge ? 'My Badge' : '${_badge?.userName ?? 'User'} Badge',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      actions: [
        if (widget.isOwnBadge && _badge != null)
          IconButton(
            icon: _isRefreshing 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
                    ),
                  )
                : const Icon(Icons.refresh, color: AppColors.primaryColor),
            onPressed: _isRefreshing ? null : _refreshBadge,
          ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
          ),
          SizedBox(height: 16),
          Text(
            'Generating your badge...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeView() {
    if (_badge == null) {
      return _buildErrorView();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            children: [
              _buildBadgeSection(),
              const SizedBox(height: 24),
              _buildStatsSection(),
              const SizedBox(height: 24),
              _buildAchievementsSection(),
              const SizedBox(height: 32),
              _buildActionButtons(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load badge',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loadBadge,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeSection() {
    return RepaintBoundary(
      key: _badgeKey,
      child: Container(
        color: AppColors.backgroundColor,
        child: ProfessionalBadgeWidget(
          badge: _badge!,
          showActions: false,
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Statistics',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Events Created',
                  _badge!.eventsCreated.toString(),
                  Icons.event,
                  AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Events Attended',
                  _badge!.eventsAttended.toString(),
                  Icons.people,
                  const Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Engagement Hours',
                  '${_badge!.totalDwellHours.toStringAsFixed(1)}h',
                  Icons.schedule,
                  const Color(0xFFFF9800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Badge Level',
                  _badge!.badgeLevel.split(' ').first,
                  Icons.military_tech,
                  const Color(0xFF9C27B0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection() {
    if (_badge!.achievements.isEmpty) {
      return const SizedBox();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Achievements',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _badge!.achievements.map((achievement) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryColor.withOpacity(0.8),
                      AppColors.primaryColor,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryColor.withOpacity(0.3),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  achievement,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _shareBadge,
            icon: const Icon(Icons.share),
            label: const Text('Share Badge'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _downloadBadge,
            icon: const Icon(Icons.download),
            label: const Text('Save Badge'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppColors.primaryColor),
              ),
              elevation: 2,
            ),
          ),
        ),
      ],
    );
  }
}