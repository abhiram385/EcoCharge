import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// The sky-and-bubbles backdrop used behind every screen: a soft blue-white
/// gradient with a handful of slow-drifting translucent bubbles, echoing the
/// Frutiger Aero wallpapers this app's whole aesthetic is built around.
class AeroBackground extends StatefulWidget {
  final Widget child;
  final int bubbleCount;

  const AeroBackground({super.key, required this.child, this.bubbleCount = 9});

  @override
  State<AeroBackground> createState() => _AeroBackgroundState();
}

class _AeroBackgroundState extends State<AeroBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Bubble> _bubbles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
    final rand = Random(7);
    _bubbles = List.generate(widget.bubbleCount, (i) {
      return _Bubble(
        dx: rand.nextDouble(),
        dy: rand.nextDouble(),
        size: 50.0 + rand.nextDouble() * 120,
        speed: 0.4 + rand.nextDouble() * 0.6,
        drift: rand.nextDouble() * pi * 2,
        green: i.isEven,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.skyGradient),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final size = MediaQuery.of(context).size;
                return Stack(
                  children: _bubbles.map((b) {
                    final t = _controller.value * 2 * pi * b.speed + b.drift;
                    final x = b.dx * size.width + sin(t) * 18;
                    final y = (b.dy * size.height - _controller.value * size.height * 0.15 * b.speed) %
                        (size.height + b.size) -
                        b.size;
                    return Positioned(
                      left: x,
                      top: y,
                      child: IgnorePointer(
                        child: Container(
                          width: b.size,
                          height: b.size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.35, -0.4),
                              colors: b.green
                                  ? [
                                      AppColors.leafGreen.withValues(alpha: 0.38),
                                      AppColors.leafGreen.withValues(alpha: 0.04),
                                    ]
                                  : [
                                      AppColors.skyBlue.withValues(alpha: 0.38),
                                      AppColors.skyBlue.withValues(alpha: 0.04),
                                    ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _Bubble {
  final double dx, dy, size, speed, drift;
  final bool green;
  _Bubble({required this.dx, required this.dy, required this.size, required this.speed, required this.drift, required this.green});
}
