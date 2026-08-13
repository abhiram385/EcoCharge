import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// EcoCharge's signature control: a glossy, convex "energy orb" pill button
/// with a diagonal chrome sheen, a soft pulsing glow ring, and a droplet
/// ripple on tap. Used for every primary action (send OTP, book, charge,
/// pay) in place of a flat ElevatedButton.
class EnergyOrbButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool green;
  final double? width;

  const EnergyOrbButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.loading = false,
    this.green = false,
    this.width,
  });

  @override
  State<EnergyOrbButton> createState() => _EnergyOrbButtonState();
}

class _EnergyOrbButtonState extends State<EnergyOrbButton> with TickerProviderStateMixin {
  late final AnimationController _pulseController =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  late final AnimationController _pressController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 120), value: 0);

  final List<_Ripple> _ripples = [];

  @override
  void dispose() {
    _pulseController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _addRipple(Offset localPos) {
    final ripple = _Ripple(localPos);
    setState(() => _ripples.add(ripple));
  }

  @override
  Widget build(BuildContext context) {
    final gradient = widget.green ? AppColors.orbGradientGreen : AppColors.orbGradient;
    final glow = widget.green ? AppColors.leafGreen : AppColors.skyBlue;

    return GestureDetector(
      onTapDown: _enabled ? (d) {
        _pressController.forward();
        _addRipple(d.localPosition);
      } : null,
      onTapUp: _enabled ? (_) => _pressController.reverse() : null,
      onTapCancel: _enabled ? () => _pressController.reverse() : null,
      onTap: _enabled ? widget.onPressed : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _pressController]),
        builder: (context, _) {
          final pulse = 0.55 + _pulseController.value * 0.45;
          final press = _pressController.value;
          final scale = 1.0 - press * 0.035;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: widget.width,
              constraints: const BoxConstraints(minHeight: 56),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: _enabled
                    ? gradient
                    : const LinearGradient(colors: [Color(0xFFC9D8DE), Color(0xFFB5C6CD)]),
                boxShadow: _enabled
                    ? [
                        BoxShadow(
                          color: glow.withValues(alpha: 0.35 * pulse),
                          blurRadius: 22 + 10 * pulse,
                          spreadRadius: 1,
                        ),
                        const BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 3)),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Chrome sheen highlight across the top half.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(999)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: _enabled ? 0.55 + press * 0.2 : 0.25),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ..._ripples.map((r) => _RippleWidget(
                          ripple: r,
                          onComplete: () {
                            if (mounted) setState(() => _ripples.remove(r));
                          },
                        )),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      child: widget.loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.icon != null) ...[
                                  Icon(widget.icon, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Text(
                                    widget.label,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: GoogleFonts.baloo2(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      shadows: const [Shadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Ripple {
  final Offset origin;
  late final AnimationController controller;
  _Ripple(this.origin);
}

class _RippleWidget extends StatefulWidget {
  final _Ripple ripple;
  final VoidCallback onComplete;
  const _RippleWidget({required this.ripple, required this.onComplete});

  @override
  State<_RippleWidget> createState() => _RippleWidgetState();
}

class _RippleWidgetState extends State<_RippleWidget> with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.ripple.controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    widget.ripple.controller.forward().whenComplete(() {
      widget.onComplete();
      widget.ripple.controller.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ripple.controller,
      builder: (context, _) {
        final t = widget.ripple.controller.value;
        return Positioned(
          left: widget.ripple.origin.dx - 60 * t,
          top: widget.ripple.origin.dy - 60 * t,
          child: IgnorePointer(
            child: Opacity(
              opacity: (1 - t).clamp(0, 1),
              child: Container(
                width: 120 * t,
                height: 120 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
