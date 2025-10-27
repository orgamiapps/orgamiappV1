import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/event_model.dart';
import 'dart:typed_data';

class EventFlyerGenerator {
  /// Generates a beautiful event flyer image and returns the file path
  static Future<File> generateEventFlyer(
    EventModel event,
    GlobalKey repaintBoundaryKey,
  ) async {
    try {
      // Wait for the widget to be fully rendered, including QR code
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify the context exists
      if (repaintBoundaryKey.currentContext == null) {
        throw Exception(
          'RepaintBoundary context is null. Widget may have been disposed.',
        );
      }

      // Get the RenderRepaintBoundary
      final RenderObject? renderObject = repaintBoundaryKey.currentContext!
          .findRenderObject();

      if (renderObject == null) {
        throw Exception('RenderObject not found');
      }

      if (renderObject is! RenderRepaintBoundary) {
        throw Exception('RenderObject is not a RenderRepaintBoundary');
      }

      final RenderRepaintBoundary boundary = renderObject;

      // Convert to image with high quality
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        throw Exception('Failed to convert image to byte data');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/event_flyer_${event.id}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      print('Event flyer generated successfully: ${file.path}');
      return file;
    } catch (e, stackTrace) {
      print('Error generating event flyer: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}

class EventFlyerWidget extends StatelessWidget {
  final EventModel event;

  const EventFlyerWidget({Key? key, required this.event}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final eventUrl = 'attendus://event/${event.id}';
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

    return Container(
      width: 1080, // Instagram portrait width
      height: 1350, // Instagram portrait height (4:5)
      color: const Color(0xFF1A1A2E), // Fallback background
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: Background Image (or placeholder)
          _buildBackgroundImage(),

          // Layer 2: Dark gradient overlay for text readability
          _buildGradientOverlay(),

          // Layer 3: Main Content
          Padding(
            padding: const EdgeInsets.all(60.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const Spacer(),
                _buildMainInfo(),
                const SizedBox(height: 30),
                _buildDetails(dateFormat, timeFormat),
                const Spacer(),
                const Spacer(),
                _buildFooter(eventUrl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundImage() {
    if (event.imageUrl.isNotEmpty) {
      return Image.network(
        event.imageUrl,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        // Basic error builder in case image fails to load
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholderImage();
        },
      );
    }
    return _buildPlaceholderImage();
  }

  Widget _buildPlaceholderImage() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6C63FF), Color(0xFF5A52D5), Color(0xFF1A1A2E)],
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: 0.15,
          child: Image.asset(
            'attendus_logo_only.png',
            width: 300,
            height: 300,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to icon pattern if logo not available
              return const Icon(Icons.event, size: 200, color: Colors.white24);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Text(
      "YOU'RE INVITED",
      style: TextStyle(
        color: Colors.white70,
        fontSize: 36,
        fontWeight: FontWeight.w300,
        letterSpacing: 4,
        fontFamily: 'Roboto',
      ),
    );
  }

  Widget _buildMainInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          event.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 80,
            fontWeight: FontWeight.bold,
            height: 1.1,
            fontFamily: 'Roboto',
            shadows: [
              Shadow(
                blurRadius: 10.0,
                color: Colors.black54,
                offset: Offset(0, 4),
              ),
            ],
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 20),
        Text(
          event.description,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 34,
            height: 1.4,
            fontFamily: 'Roboto',
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildDetails(DateFormat dateFormat, DateFormat timeFormat) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.0),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          padding: const EdgeInsets.all(30.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(
                Icons.calendar_today_outlined,
                dateFormat.format(event.selectedDateTime),
              ),
              const SizedBox(height: 25),
              _buildDetailRow(
                Icons.access_time_outlined,
                '${timeFormat.format(event.selectedDateTime)} - ${timeFormat.format(event.eventEndTime)}',
              ),
              const SizedBox(height: 25),
              _buildLocationRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationRow() {
    // Get formatted location string showing both name and address when available
    final locationText = _getFormattedLocation();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.location_on_outlined, color: Colors.white, size: 44),
        const SizedBox(width: 24),
        Expanded(
          child: Text(
            locationText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w500,
              fontFamily: 'Roboto',
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _getFormattedLocation() {
    final hasLocationName =
        event.locationName != null && event.locationName!.isNotEmpty;
    final hasLocation = event.location.isNotEmpty;

    // If both exist and are different, show both
    if (hasLocationName && hasLocation) {
      // Check if they're the same (avoid duplication)
      if (event.locationName!.trim() == event.location.trim()) {
        return event.locationName!;
      }
      // Show both: "Venue Name\nFull Address"
      return '${event.locationName}\n${event.location}';
    }

    // If only location name exists
    if (hasLocationName) {
      return event.locationName!;
    }

    // If only location exists (or as fallback)
    return event.location;
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 44),
        const SizedBox(width: 24),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w500,
              fontFamily: 'Roboto',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(String eventUrl) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Image.asset('attendus_logo_only.png', height: 52),
                const SizedBox(width: 12),
                const Text(
                  'Attendus',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 46,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Scan QR to view event details',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 26,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18.0),
          ),
          child: QrImageView(
            data: eventUrl,
            version: QrVersions.auto,
            size: 290.0,
            gapless: false,
            errorStateBuilder: (cxt, err) {
              return const Center(
                child: Text(
                  'QR Error',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
