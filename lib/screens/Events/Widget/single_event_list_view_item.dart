import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/screens/Events/single_event_screen.dart';
import 'package:orgami/screens/Events/event_location_view_screen.dart';
import 'package:orgami/Utils/router.dart';
import 'package:orgami/Utils/cached_image.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/Utils/toast.dart';

class SingleEventListViewItem extends StatefulWidget {
  final EventModel eventModel;
  final bool disableTap;
  final VoidCallback? onFavoriteChanged;
  final VoidCallback? onTap;

  const SingleEventListViewItem({
    super.key,
    required this.eventModel,
    this.disableTap = false,
    this.onFavoriteChanged,
    this.onTap,
  });

  @override
  State<SingleEventListViewItem> createState() =>
      _SingleEventListViewItemState();
}

class _SingleEventListViewItemState extends State<SingleEventListViewItem>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  bool _isFavorited = false;
  bool _isLoadingFavorite = false;
  bool _hasCheckedFavoriteStatus = false;
  late AnimationController _favoriteController;
  late Animation<double> _favoriteScaleAnimation;

  @override
  bool get wantKeepAlive => true; // Prevent rebuilding when scrolling

  @override
  void initState() {
    super.initState();
    _favoriteController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _favoriteScaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _favoriteController, curve: Curves.elasticOut),
    );
    // Delay favorite status check to prevent flashing during rapid scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasCheckedFavoriteStatus) {
        _checkFavoriteStatus();
      }
    });
  }

  @override
  void dispose() {
    _favoriteController.dispose();
    super.dispose();
  }

  Future<void> _checkFavoriteStatus() async {
    if (CustomerController.logeInCustomer == null || _hasCheckedFavoriteStatus)
      return;

    _hasCheckedFavoriteStatus = true;

    try {
      final isFavorited = await FirebaseFirestoreHelper().isEventFavorited(
        userId: CustomerController.logeInCustomer!.uid,
        eventId: widget.eventModel.id,
      );

      if (mounted) {
        setState(() {
          _isFavorited = isFavorited;
        });
      }
    } catch (e) {
      debugPrint('Error checking favorite status: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    if (CustomerController.logeInCustomer == null) {
      ShowToast().showNormalToast(msg: 'Please log in to save events');
      return;
    }

    setState(() {
      _isLoadingFavorite = true;
    });

    try {
      if (_isFavorited) {
        await FirebaseFirestoreHelper().removeFromFavorites(
          userId: CustomerController.logeInCustomer!.uid,
          eventId: widget.eventModel.id,
        );
      } else {
        await FirebaseFirestoreHelper().addToFavorites(
          userId: CustomerController.logeInCustomer!.uid,
          eventId: widget.eventModel.id,
        );
      }

      if (mounted) {
        setState(() {
          _isFavorited = !_isFavorited;
          _isLoadingFavorite = false;
        });

        _favoriteController.forward().then((_) {
          _favoriteController.reverse();
        });

        ShowToast().showNormalToast(
          msg: _isFavorited ? 'Event saved!' : 'Event removed from saved!',
        );
        widget.onFavoriteChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFavorite = false;
        });
      }
      ShowToast().showNormalToast(msg: 'Failed to update saved events');
      debugPrint('Error toggling favorite: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Card(
      elevation: 5,
      shadowColor: Colors.black.withOpacity(0.1),
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.disableTap
            ? null
            : () {
                widget.onTap?.call();
                RouterClass.nextScreenNormal(
                  context,
                  SingleEventScreen(eventModel: widget.eventModel),
                );
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_buildImageSection(), _buildContentSection(context)],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: SafeNetworkImage(
              imageUrl: widget.eventModel.imageUrl,
              fit: BoxFit.cover,
              placeholder: Container(color: const Color(0xFFF5F7FA)),
              errorWidget: Container(
                color: const Color(0xFFF5F7FA),
                child: const Center(
                  child: Icon(Icons.image_not_supported, color: Colors.grey),
                ),
              ),
            ),
          ),
          Positioned(top: 12, right: 12, child: _buildFavoriteButton()),
          if (widget.eventModel.isFeatured)
            Positioned(top: 12, left: 12, child: _buildFeaturedBadge()),
        ],
      ),
    );
  }

  Widget _buildFavoriteButton() {
    return AnimatedBuilder(
      animation: _favoriteController,
      builder: (context, child) {
        return Transform.scale(
          scale: _favoriteScaleAnimation.value,
          child: GestureDetector(
            onTap: _isLoadingFavorite ? null : _toggleFavorite,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: _isLoadingFavorite
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF667EEA),
                        ),
                      ),
                    )
                  : Icon(
                      _isFavorited ? Icons.bookmark : Icons.bookmark_border,
                      color: _isFavorited
                          ? const Color(0xFFE53E3E)
                          : const Color(0xFF667EEA),
                      size: 22,
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeaturedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          const Text(
            'Featured',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.eventModel.title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              fontFamily: 'Roboto',
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.calendar_today,
            DateFormat.yMMMMd().format(widget.eventModel.selectedDateTime),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.access_time,
            DateFormat.jm().format(widget.eventModel.selectedDateTime),
          ),
          const SizedBox(height: 8),
          _buildLocationRow(context),
          const SizedBox(height: 16),
          Text(
            widget.eventModel.description,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              height: 1.5,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF667EEA), size: 16),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 14, color: Colors.grey[800])),
      ],
    );
  }

  Widget _buildLocationRow(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.location_on, color: Color(0xFF667EEA), size: 16),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: Text(
            widget.eventModel.location,
            style: TextStyle(fontSize: 14, color: Colors.grey[800]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.eventModel.latitude != 0 && widget.eventModel.longitude != 0) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => RouterClass.nextScreenNormal(
              context,
              EventLocationViewScreen(eventModel: widget.eventModel),
            ),
            child: const Icon(
              Icons.map_outlined,
              color: Color(0xFF667EEA),
              size: 20,
            ),
          ),
        ],
      ],
    );
  }
}
