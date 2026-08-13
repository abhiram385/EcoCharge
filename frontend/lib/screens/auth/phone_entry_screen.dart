import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import 'otp_verify_screen.dart';

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _controller = TextEditingController();
  String _countryCode = '+91';

  Future<void> _sendOtp() async {
    final phone = '$_countryCode${_controller.text.trim()}';
    final auth = context.read<AuthProvider>();
    final ok = await auth.requestOtp(phone);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OtpVerifyScreen(phone: phone)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Could not send OTP')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: AeroBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.orbGradientGreen,
                    boxShadow: [
                      BoxShadow(color: AppColors.leafGreen.withValues(alpha: 0.4), blurRadius: 26, spreadRadius: 2),
                    ],
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 24),
                Text(
                  "Let's get you\ncharged up",
                  style: GoogleFonts.baloo2(
                    color: AppColors.deepAzure,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Enter your phone number to sign in or create an account.',
                  style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 28),
                GlassPanel(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: DropdownButton<String>(
                          value: _countryCode,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: '+91', child: Text('🇮🇳 +91')),
                            DropdownMenuItem(value: '+1', child: Text('🇺🇸 +1')),
                            DropdownMenuItem(value: '+44', child: Text('🇬🇧 +44')),
                          ],
                          onChanged: (v) => setState(() => _countryCode = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.nunitoSans(fontSize: 16, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(hintText: 'Phone number', border: InputBorder.none),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                EnergyOrbButton(
                  label: 'Send code',
                  icon: Icons.send_rounded,
                  loading: auth.isLoading,
                  onPressed: auth.isLoading ? null : _sendOtp,
                  width: double.infinity,
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    "By continuing, you agree to EcoCharge's Terms & Privacy Policy.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunitoSans(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
