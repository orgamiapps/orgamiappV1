import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/badge_model.dart';
import '../../../Utils/colors.dart';

class ProfessionalBadgeWidget extends StatefulWidget {
  final UserBadgeModel badge;
  final double width;
  final double height;
  final bool showActions;
  final VoidCallback? onShare;
  final VoidCallback? onDownload;
  final bool enableFullScreenOnTap;

  const ProfessionalBadgeWidget({
    super.key,
    required this.badge,
    this.width = 340,
    this.height = 220,
    this.showActions = true,
    this.onShare,
    this.onDownload,
    this.enableFullScreenOnTap = true,
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
                          if (!widget.enableFullScreenOnTap) return scaled;
                          return GestureDetector(
                            onTap: () => _openFullScreenBadge(context),
                            child: scaled,
                          );
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
            _buildCenterQr(),
            _buildBadgeContent(),
            _buildHolographicEffect(),
          ],
        ),
      ),
    );
  }

  void _openFullScreenBadge(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        pageBuilder: (context, animation, secondaryAnimation) {
          final scale = _uiScale(context);
          return Scaffold(
            backgroundColor: Colors.black.withValues(alpha: 0.85),
            body: _FullScreenBadgeView(
              badgeUid: widget.badge.uid,
              baseScale: scale,
              buildCard: _buildBadgeCard,
              onClose: () => Navigator.of(context).pop(),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
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
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfileSection(),
                const SizedBox(width: 16),
                Expanded(child: _buildStatsSection()),
              ],
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ORGAMI',
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
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Text(
            'ID: ${widget.badge.uid.substring(0, 8)}',
            style: TextStyle(
              fontSize: 8,
              color: Colors.white.withValues(alpha: 0.9),
              fontFamily: 'Courier',
              letterSpacing: 0.5,
              shadows: _textShadows(small: true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection() {
    final scale = _uiScale(context);
    final avatarSize = 50.0 * scale;
    final spacing = 6.0 * scale;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 80, maxWidth: 120),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              child: widget.badge.profileImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: widget.badge.profileImageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.person, color: Colors.grey),
                      ),
                      errorWidget: (context, url, error) => Container(
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
            widget.badge.userName,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    // Align labels closer to their numeric chips on the right side
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildRightAlignedStat(
          'Events Created',
          widget.badge.eventsCreated.toString(),
        ),
        _buildRightAlignedStat(
          'Events Attended',
          widget.badge.eventsAttended.toString(),
        ),
        _buildRightAlignedStat('Member Since', widget.badge.membershipDuration),
      ],
    );
  }

  Widget _buildRightAlignedStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Label pill first (left), followed by the numeric chip on the right
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Center QR positioned in the open middle area of the card
  Widget _buildCenterQr() {
    final scale = _uiScale(context);
    final size = 100.0 * scale;
    return Positioned.fill(
      child: Align(
        alignment: Alignment.center,
        child: Transform.translate(
          offset: Offset(-24.0 * scale, 0),
          child: Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(4 * scale),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
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
          ),
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

class _FullScreenBadgeView extends StatefulWidget {
  final String badgeUid;
  final double baseScale;
  final Widget Function() buildCard;
  final VoidCallback? onClose;
  const _FullScreenBadgeView({
    required this.badgeUid,
    required this.baseScale,
    required this.buildCard,
    this.onClose,
  });

  @override
  State<_FullScreenBadgeView> createState() => _FullScreenBadgeViewState();
}

class _FullScreenBadgeViewState extends State<_FullScreenBadgeView> {
  final TransformationController _tc = TransformationController();

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 32;
    final height = width * (220 / 340);
    return SafeArea(
      child: Stack(
        children: [
          Center(
            child: Hero(
              tag: 'badge_fullscreen_${widget.badgeUid}',
              child: InteractiveViewer(
                transformationController: _tc,
                minScale: 0.8,
                maxScale: 3.0,
                boundaryMargin: const EdgeInsets.all(48),
                child: Material(
                  color: Colors.transparent,
                  child: Transform.scale(
                    scale: widget.baseScale,
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: widget.buildCard(),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top-right close
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: widget.onClose,
              tooltip: 'Close',
            ),
          ),

          // Bottom actions
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _ActionBar(
              onShare: () async {
                final file = await _exportBadgePngStatic(
                  context,
                  widget.buildCard,
                  width,
                  height,
                );
                await SharePlus.instance.share(
                  ShareParams(
                    text: 'My AttendUs badge',
                    files: [XFile(file.path)],
                  ),
                );
              },
              onSave: () async {
                final file = await _exportBadgePngStatic(
                  context,
                  widget.buildCard,
                  width,
                  height,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved to: ${file.path}')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<File> _exportBadgePngStatic(
    BuildContext context,
    Widget Function() builder,
    double width,
    double height,
  ) async {
    final repaintKey = GlobalKey();
    final repaint = RepaintBoundary(
      key: repaintKey,
      child: SizedBox(width: width, height: height, child: builder()),
    );

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Center(child: Opacity(opacity: 0.0, child: repaint)),
    );
    overlay.insert(entry);
    await Future.delayed(const Duration(milliseconds: 16));
    final boundary =
        repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/badge_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(data!.buffer.asUint8List());
    entry.remove();
    return file;
  }
}

class _ActionBar extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onSave;
  const _ActionBar({required this.onShare, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _pillButton(icon: Icons.share, label: 'Share', onTap: onShare),
          _pillButton(
            icon: Icons.download_rounded,
            label: 'Save',
            onTap: onSave,
          ),
          _pillButton(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Save to Wallet',
            onTap: () async {
              try {
                // Determine platform hint
                final platform = Theme.of(context).platform;
                final isApple =
                    platform == TargetPlatform.iOS ||
                    platform == TargetPlatform.macOS;
                final callable = FirebaseFunctions.instance.httpsCallable(
                  'generateUserBadgePass',
                );
                final result = await callable.call({
                  'uid':
                      (ModalRoute.of(context)?.settings.arguments
                          as Map?)?['uid'] ??
                      '',
                  'platform': isApple ? 'apple' : 'google',
                });
                final url = Uri.parse(result.data['url'] as String);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to add to wallet at this time.'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
