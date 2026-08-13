import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// A frosted-glass card: blurred translucent fill, a bright top sheen, and a
/// thin dew-white rim — the standard Aero panel used throughout the app in
/// place of flat Material cards.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 26,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.dewWhite.withValues(alpha: 0.85), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.skyBlue.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 42,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
                    gradient: AppColors.chromeSheen,
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}
