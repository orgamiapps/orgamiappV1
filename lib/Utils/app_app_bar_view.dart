import 'package:flutter/material.dart';
import 'package:attendus/Utils/app_buttons.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';

class AppAppBarView {
  /// Modern header with title and optional subtitle
  static Widget modernHeader({
    required BuildContext context,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool showBackButton = true,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Modern back button
          if (showBackButton)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.6 : 0.8,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 22,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          if (showBackButton) const SizedBox(width: 16),
          // Title with modern typography
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Optional trailing widget
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
      ),
    );
  }

  /// Modern back button only (for screens with custom headers like Premium)
  static Widget modernBackButton({
    required BuildContext context,
    Color? backgroundColor,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => Navigator.pop(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: backgroundColor ??
                theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.6 : 0.8,
                ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 22,
            color: iconColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  // ========== Legacy methods (deprecated - use modernHeader instead) ==========

  @Deprecated('Use modernHeader instead. This method will be removed in a future version.')
  static Widget appBarView({
    required BuildContext context,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            child: AppButtons.roundedButton(
              iconData: Icons.arrow_back_ios_rounded,
              iconColor: AppThemeColor.pureWhiteColor,
              backgroundColor: AppThemeColor.primaryIndigo,
            ),
          ),
          const SizedBox(width: 15),
          Text(
            title,
            style: const TextStyle(
              color: AppThemeColor.darkBlueColor,
              fontSize: Dimensions.paddingSizeLarge,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @Deprecated('Use modernBackButton instead. This method will be removed in a future version.')
  static Widget appBarWithOnlyBackButton({
    required BuildContext context,
    Color? backButtonColor,
    Color? iconColor,
  }) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8.0),
        child: InkWell(
          onTap: () => Navigator.pop(context),
          child: AppButtons.roundedButton(
            iconData: Icons.arrow_back_ios_rounded,
            iconColor: iconColor ?? AppThemeColor.pureWhiteColor,
            backgroundColor: backButtonColor ?? AppThemeColor.primaryIndigo,
          ),
        ),
      ),
    );
  }
}
