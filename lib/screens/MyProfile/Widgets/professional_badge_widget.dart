import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../models/badge_model.dart';
import '../../../Utils/colors.dart';
import 'package:attendus/Utils/cached_image.dart';
import 'package:attendus/controller/customer_controller.dart';

class ProfessionalBadgeWidget extends StatefulWidget {
  final UserBadgeModel badge;
  final double width;
  final double height;
  final bool showActions;
  final VoidCallback? onShare;
  final VoidCallback? onDownload;

  const ProfessionalBadgeWidget({
    super.key,
    required this.badge,
    this.width = 340,
    this.height = 220,
    this.showActions = true,
    this.onShare,
    this.onDownload,
  });

  @override
  State<ProfessionalBadgeWidget> createState() =>
      _ProfessionalBadgeWidgetState();
}

class _ProfessionalBadgeWidgetState extends State<ProfessionalBadgeWidget>
    with TickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;
  late AnimationController _entranceController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  // Compute a UI scale factor that adapts to large text and small layouts
  double _uiScale(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    // When the user increases text size, gently scale down our UI to maintain fit
    final inverseTextScale = 1.0 / textScale;
    return inverseTextScale.clamp(0.85, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _shimmerController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.elasticOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeIn),
    );

    _entranceController.forward();
    _shimmerController.repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // Previous dynamic gradient based on badge level removed in favor of a consistent silver look

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Column(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      child: Builder(
                        builder: (context) {
                          final scale = _uiScale(context);
                          final card = SizedBox(
                            width: 340,
                            height: 220,
                            child: _buildBadgeCard(),
                          );
                          final scaled = Transform.scale(
                            scale: scale,
                            alignment: Alignment.topLeft,
                            child: card,
                          );
                          return scaled;
                        },
                      ),
                    ),
                  ),
                  if (widget.showActions) _buildActionButtons(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadgeCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFFC0C0C0).withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: 5,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            _buildGradientBackground(),
            _buildShimmerEffect(),
            _buildContrastOverlay(),
            _buildBadgeContent(),
            _buildHolographicEffect(),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientBackground() {
    // Use a silver-toned gradient for the badge background
    const Color silverBase = Color(0xFFC0C0C0);
    const Color silverDark = Color(0xFF9EA4AE);
    const Color silverLight = Color(0xFFE8EBEF);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [silverDark, silverBase, silverLight, silverBase],
          stops: const [0.0, 0.4, 0.75, 1.0],
        ),
      ),
    );
  }

  Widget _buildShimmerEffect() {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.05),
                Colors.transparent,
              ],
              stops: [
                (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                (_shimmerAnimation.value - 0.1).clamp(0.0, 1.0),
                _shimmerAnimation.value.clamp(0.0, 1.0),
                (_shimmerAnimation.value + 0.1).clamp(0.0, 1.0),
                (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }

  // Adds a subtle dark overlay to improve text contrast across light gradients
  Widget _buildContrastOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withValues(alpha: 0.28),
              Colors.black.withValues(alpha: 0.16),
              Colors.black.withValues(alpha: 0.10),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildHolographicEffect() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.06),
              Colors.transparent,
              const Color(0xFF00FFFF).withValues(alpha: 0.06),
              Colors.transparent,
              const Color(0xFFFF00FF).withValues(alpha: 0.06),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadgeContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildProfileSection(),
                const SizedBox(width: 12),
                Expanded(child: Center(child: _buildQrSection())),
              ],
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ATTENDUS',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white.withValues(alpha: 0.98),
            letterSpacing: 2,
            shadows: _textShadows(),
          ),
        ),
        Text(
          'EVENT BADGE',
          style: TextStyle(
            fontSize: 9,
            color: Colors.white.withValues(alpha: 0.9),
            letterSpacing: 1.5,
            shadows: _textShadows(small: true),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection() {
    final scale = _uiScale(context);
    final avatarSize = 45.0 * scale;
    final spacing = 4.0 * scale;
    // Prefer the badge's own data, but fall back to the logged-in user's
    // profile if the badge document is missing these fields. This guarantees
    // the badge shows the user's name/photo on their profile screen.
    final currentUser = CustomerController.logeInCustomer;
    final isCurrentUsersBadge = currentUser?.uid == widget.badge.uid;
    final fallbackName = isCurrentUsersBadge ? (currentUser?.name ?? '') : '';
    final fallbackPhoto = isCurrentUsersBadge
        ? (currentUser?.profilePictureUrl ?? '')
        : '';
    final displayName = (widget.badge.userName.isNotEmpty)
        ? widget.badge.userName
        : fallbackName;
    final displayPhotoUrl =
        (widget.badge.profileImageUrl != null &&
            widget.badge.profileImageUrl!.isNotEmpty)
        ? widget.badge.profileImageUrl!
        : fallbackPhoto;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 70, maxWidth: 100),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: (displayPhotoUrl.isNotEmpty)
                  ? SafeNetworkImage(
                      imageUrl: displayPhotoUrl,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.person, color: Colors.grey),
                      ),
                      errorWidget: Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.person, color: Colors.grey),
                      ),
                    )
                  : Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.person, color: Colors.grey),
                    ),
            ),
          ),
          SizedBox(height: spacing),
          Text(
            displayName.isNotEmpty ? displayName : 'Member',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Removed _buildStatsSection as it's no longer needed

  // Removed _buildRightAlignedStat as it's no longer needed
  // Removed _buildStatsSection as it's no longer needed

  // Build the QR code section with modern UI design
  Widget _buildQrSection() {
    final scale = _uiScale(context);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: EdgeInsets.all(10 * scale),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon and title row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 14 * scale,
                ),
                SizedBox(width: 4 * scale),
                Text(
                  'SCAN TO ACTIVATE',
                  style: TextStyle(
                    fontSize: 8 * scale,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.95),
                    letterSpacing: 0.8,
                    shadows: _textShadows(small: true),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6 * scale),
            // QR Code
            _buildQrCode(),
            SizedBox(height: 4 * scale),
            // Description text
            Text(
              'Valid for all your tickets',
              style: TextStyle(
                fontSize: 6.5 * scale,
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
                shadows: _textShadows(small: true),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Build QR code widget
  Widget _buildQrCode() {
    final scale = _uiScale(context);
    final size = 80.0 * scale;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(4 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: QrImageView(
        data: widget.badge.badgeQrData,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Valid: ${DateTime.now().year}',
          style: TextStyle(
            fontSize: 7,
            color: Colors.white.withValues(alpha: 0.85),
            shadows: _textShadows(small: true),
          ),
        ),
      ],
    );
  }

  List<Shadow> _textShadows({bool small = false}) {
    return [
      Shadow(
        color: Colors.black.withValues(alpha: 0.45),
        blurRadius: small ? 2 : 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  Widget _buildActionButtons() {
    if (!widget.showActions) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: CupertinoIcons.share,
            label: 'Share',
            onTap: widget.onShare,
          ),
          _buildActionButton(
            icon: Icons.download,
            label: 'Download',
            onTap: widget.onDownload,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primaryColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primaryColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Compact version for smaller displays
class CompactBadgeWidget extends StatelessWidget {
  final UserBadgeModel badge;
  final double size;
  final VoidCallback? onTap;

  const CompactBadgeWidget({
    super.key,
    required this.badge,
    this.size = 80,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [_getBadgeColor(), _getBadgeColor().withValues(alpha: 0.7)],
          ),
          boxShadow: [
            BoxShadow(
              color: _getBadgeColor().withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.military_tech, color: Colors.white, size: size * 0.3),
            Text(
              badge.badgeLevel.split(' ').first,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.1,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBadgeColor() {
    switch (badge.badgeLevel) {
      case 'Master Organizer':
        return const Color(0xFFFFD700);
      case 'Senior Event Host':
        return const Color(0xFFC0C0C0);
      case 'Event Specialist':
        return const Color(0xFFCD7F32);
      case 'Active Member':
        return const Color(0xFF4A90E2);
      case 'Community Builder':
        return const Color(0xFF50C878);
      default:
        return const Color(0xFF9B59B6);
    }
  }
}
