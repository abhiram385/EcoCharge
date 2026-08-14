import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../home/home_shell.dart';

class OtpVerifyScreen extends StatefulWidget {
  final String phone;
  final String? devOtp;
  const OtpVerifyScreen({super.key, required this.phone, this.devOtp});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  String _code = '';
  late final TextEditingController _pinController;

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController(text: widget.devOtp ?? '');
    if (widget.devOtp != null) {
      _code = widget.devOtp!;
    }
  }

  Future<void> _verify() async {
    if (_code.length != 6) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyOtp(widget.phone, _code);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Invalid OTP')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: AeroBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Verify your number',
                  style: GoogleFonts.baloo2(color: AppColors.deepAzure, fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code sent to ${widget.phone}',
                  style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 28),
                GlassPanel(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                  child: PinCodeTextField(
                    appContext: context,
                    controller: _pinController,
                    length: 6,
                    onChanged: (v) => setState(() => _code = v),
                    onCompleted: (v) => _verify(),
                    keyboardType: TextInputType.number,
                    animationType: AnimationType.scale,
                    pinTheme: PinTheme(
                      shape: PinCodeFieldShape.box,
                      borderRadius: BorderRadius.circular(16),
                      fieldHeight: 52,
                      fieldWidth: 44,
                      activeColor: AppColors.skyBlue,
                      selectedColor: AppColors.leafGreen,
                      inactiveColor: AppColors.divider,
                      activeFillColor: AppColors.surfaceMuted,
                      inactiveFillColor: AppColors.surfaceMuted,
                      selectedFillColor: AppColors.chromeMist,
                    ),
                  ),
                ),
                if (widget.devOtp != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Dev code (no SMS configured): ${widget.devOtp}',
                    style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 28),
                EnergyOrbButton(
                  label: 'Verify & continue',
                  icon: Icons.check_rounded,
                  loading: auth.isLoading,
                  onPressed: auth.isLoading ? null : _verify,
                  green: true,
                  width: double.infinity,
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      final auth = context.read<AuthProvider>();
                      await auth.requestOtp(widget.phone);
                      if (!mounted) return;
                      final newCode = auth.lastDevOtp;
                      if (newCode != null) {
                        setState(() => _code = newCode);
                        _pinController.text = newCode;
                      }
                    },
                    child: Text('Resend code', style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
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
