import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/widgets/app_bottom_navigation.dart';

class AppScaffoldWrapper extends StatefulWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final bool showBottomNavigation;
  final int? selectedBottomNavIndex;
  final bool? resizeToAvoidBottomInset;
  final Widget? drawer;
  final Widget? endDrawer;

  const AppScaffoldWrapper({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.showBottomNavigation = true,
    this.selectedBottomNavIndex,
    this.resizeToAvoidBottomInset,
    this.drawer,
    this.endDrawer,
  });

  @override
  State<AppScaffoldWrapper> createState() => _AppScaffoldWrapperState();
}

class _AppScaffoldWrapperState extends State<AppScaffoldWrapper> {
  bool _hasScrolledContent = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar,
      backgroundColor: widget.backgroundColor,
      floatingActionButton: widget.floatingActionButton,
      floatingActionButtonLocation: widget.floatingActionButtonLocation,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      drawer: widget.drawer,
      endDrawer: widget.endDrawer,
      body: widget.showBottomNavigation
          ? NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Track if any vertical scrollable in the subtree has scrolled from top
                try {
                  final bool isVertical = notification.metrics.axis == Axis.vertical;
                  if (isVertical && mounted) {
                    final bool scrolled = notification.metrics.pixels > 0.0;
                    if (scrolled != _hasScrolledContent) {
                      setState(() => _hasScrolledContent = scrolled);
                    }
                  }
                } catch (e) {
                  // Silently handle any errors during scroll notification
                  debugPrint('Error in scroll notification: $e');
                }
                return false;
              },
              child: widget.body,
            )
          : widget.body,
      bottomNavigationBar: widget.showBottomNavigation
          ? AppBottomNavigation(
              selectedIndex: widget.selectedBottomNavIndex,
              hasScrolledContent: _hasScrolledContent,
            )
          : null,
    );
  }
}
