import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/swap.dart';
import 'aero/glass_panel.dart';

class SwapPointCard extends StatelessWidget {
  final SwapPoint point;
  final VoidCallback onTap;

  const SwapPointCard({super.key, required this.point, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.orbGradientGreen,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: AppColors.leafGreen.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: const Icon(Icons.battery_charging_full_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point.name,
                      style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.deepAzure),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      point.address ?? point.city ?? '',
                      style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _pill(Icons.star_rounded, point.rating.toStringAsFixed(1), AppColors.sunGlow, AppColors.sunPale),
                        const SizedBox(width: 8),
                        if (point.distanceKm != null)
                          _pill(Icons.near_me_rounded, '${point.distanceKm} km', AppColors.deepAzure, AppColors.chromeMist),
                        const SizedBox(width: 8),
                        if (point.isOpen24h)
                          _pill(Icons.access_time_filled_rounded, '24/7', AppColors.leafDark, AppColors.leafPale),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.nunitoSans(color: fg, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
