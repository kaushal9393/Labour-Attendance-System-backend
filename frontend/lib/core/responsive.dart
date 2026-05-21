import 'package:flutter/material.dart';

class Responsive {
  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600;

  static bool isLargeTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 900;

  /// Max width for content on tablets (forms, cards)
  static double contentWidth(BuildContext context, {double max = 500}) {
    final w = MediaQuery.sizeOf(context).width;
    return w > max ? max : double.infinity;
  }

  /// Horizontal padding that grows with screen width
  static EdgeInsets hPad(BuildContext context, {double base = 24}) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w > 700 ? (w - 500) / 2 : base;
    return EdgeInsets.symmetric(horizontal: pad.clamp(base, 80));
  }
}

/// Centers content with a max-width constraint — use on every admin screen
class MaxWidthBox extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const MaxWidthBox({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}
