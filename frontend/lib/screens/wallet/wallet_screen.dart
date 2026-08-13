import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<WalletProvider>().load());
  }

  Future<void> _showTopUpSheet() async {
    final amounts = [200, 500, 1000, 2000];
    int? selected;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.chromeMist,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add money to wallet', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: amounts.map((a) {
                  final isSel = selected == a;
                  return ChoiceChip(
                    label: Text('₹$a'),
                    selected: isSel,
                    onSelected: (_) => setSheetState(() => selected = a),
                    selectedColor: AppColors.skyBlue,
                    labelStyle: GoogleFonts.nunitoSans(color: isSel ? Colors.white : AppColors.deepAzure, fontWeight: FontWeight.w700),
                    backgroundColor: Colors.white,
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              EnergyOrbButton(
                label: 'Add money',
                icon: Icons.add_rounded,
                green: true,
                width: double.infinity,
                onPressed: selected == null
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        final ok = await context.read<WalletProvider>().topUp(selected!.toDouble());
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ok ? 'Added ₹$selected to wallet' : 'Top-up failed')),
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: AeroBackground(
        bubbleCount: 3,
        child: RefreshIndicator(
          onRefresh: () => context.read<WalletProvider>().load(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppColors.orbGradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: AppColors.skyBlue.withValues(alpha: 0.4), blurRadius: 26, offset: const Offset(0, 10))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Available balance', style: GoogleFonts.nunitoSans(color: Colors.white70, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      '₹${wallet.balance.toStringAsFixed(2)}',
                      style: GoogleFonts.baloo2(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 18),
                    EnergyOrbButton(
                      label: 'Add money',
                      icon: Icons.add_rounded,
                      width: double.infinity,
                      green: true,
                      onPressed: _showTopUpSheet,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text('Recent activity', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.deepAzure)),
              const SizedBox(height: 12),
              if (wallet.isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.skyBlue)))
              else if (wallet.transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('No transactions yet', style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                )
              else
                ...wallet.transactions.map((tx) {
                  final isCredit = tx.type == 'topup' || tx.type == 'refund';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassPanel(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      radius: 20,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: isCredit ? AppColors.chromeMist : AppColors.leafPale,
                          child: Icon(
                            isCredit ? Icons.arrow_downward_rounded : Icons.bolt_rounded,
                            color: isCredit ? AppColors.skyBlue : AppColors.leafDark,
                          ),
                        ),
                        title: Text(_txLabel(tx.type), style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                        subtitle: Text(DateFormat('MMM d, h:mm a').format(tx.createdAt), style: GoogleFonts.nunitoSans(fontSize: 12.5)),
                        trailing: Text(
                          '${isCredit ? '+' : '-'}₹${tx.amount.toStringAsFixed(0)}',
                          style: GoogleFonts.baloo2(
                            color: isCredit ? AppColors.success : AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  String _txLabel(String type) {
    switch (type) {
      case 'topup':
        return 'Wallet top-up';
      case 'charge_debit':
        return 'Charging session';
      case 'refund':
        return 'Refund';
      default:
        return type;
    }
  }
}
