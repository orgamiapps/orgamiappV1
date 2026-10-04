import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Button labels can sit inside IgnorePointer (segmented/loading buttons).
/// Hit-test their nearest input handler rather than the decorative text leaf.
Finder actionableAncestor(Finder label) {
  final handlers = find.ancestor(
    of: label,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is InkResponse ||
          widget is GestureDetector ||
          widget is ButtonStyleButton,
    ),
  );
  // Reevaluate the path after stream/async rebuilds; capturing a Widget
  // instance turns a still-visible button into an empty finder when rebuilt.
  return handlers.evaluate().isEmpty ? label : handlers.first;
}

Future<Finder> revealAction(WidgetTester tester, Finder label) async {
  // enterText schedules EditableText's caret reveal for the next frame. Drain
  // that reveal before scrolling to another control, or it scrolls us back.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final target = actionableAncestor(label);
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pump();
  return target;
}
