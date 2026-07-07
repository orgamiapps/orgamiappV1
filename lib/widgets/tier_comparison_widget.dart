import 'package:flutter/material.dart';

class TierComparisonWidget extends StatefulWidget {
  final VoidCallback? onBasicSelected;
  final VoidCallback? onPremiumSelected;
  final bool showButtons;

  const TierComparisonWidget({
    super.key,
    this.onBasicSelected,
    this.onPremiumSelected,
    this.showButtons = true,
  });

  @override
  State<TierComparisonWidget> createState() => _TierComparisonWidgetState();
}

class _TierComparisonWidgetState extends State<TierComparisonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late List<Animation<double>> _itemAnimations;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Create staggered animations for each row
    _itemAnimations = List.generate(
      8,
      (index) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            index * 0.1,
            0.5 + (index * 0.1),
            curve: Curves.easeOutCubic,
          ),
        ),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Text(
              'Feature Comparison',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Column headers
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text(
                    'Feature',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Expanded(child: _buildHeaderCell('Free', Colors.grey)),
                Expanded(child: _buildHeaderCell('Basic', Colors.blue)),
                Expanded(
                  child: _buildHeaderCell('Premium', theme.colorScheme.primary),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 1),
          ),

          // Feature rows
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildAnimatedRow(0, 'Browse events', true, true, true),
                _buildAnimatedRow(1, 'RSVP to events', true, true, true),
                _buildAnimatedRow(
                  2,
                  'Create events',
                  '5 lifetime',
                  '5/month',
                  'Unlimited',
                ),
                _buildAnimatedRow(3, 'Attendance tracking', true, true, true),
                _buildAnimatedRow(4, 'Event sharing', true, true, true),
                _buildAnimatedRow(5, 'Event analytics', false, false, true),
                _buildAnimatedRow(6, 'Create groups', false, false, true),
                _buildAnimatedRow(7, 'Priority support', false, false, true),
              ],
            ),
          ),

          // Action buttons
          if (widget.showButtons)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onBasicSelected,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.blue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Choose Basic',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.onPremiumSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Choose Premium',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildAnimatedRow(
    int index,
    String feature,
    dynamic free,
    dynamic basic,
    dynamic premium,
  ) {
    return AnimatedBuilder(
      animation: _itemAnimations[index],
      builder: (context, child) {
        return Opacity(
          opacity: _itemAnimations[index].value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - _itemAnimations[index].value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                feature,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: _buildFeatureCell(free)),
            Expanded(child: _buildFeatureCell(basic)),
            Expanded(child: _buildFeatureCell(premium)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCell(dynamic value) {
    if (value is bool) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: value
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            value ? Icons.check : Icons.close,
            color: value ? Colors.green : Colors.red,
            size: 16,
          ),
        ),
      );
    } else {
      return Center(
        child: Text(
          value.toString(),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
  }
}
