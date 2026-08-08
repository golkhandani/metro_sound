import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_reset.dart';
import '../services/pro.dart';
import '../ui/studio.dart';

/// Developer / testing tools. Only reachable from Settings on a test build
/// (debug or TestFlight); hidden entirely in the production App Store because
/// [Pro.isTestBuild] is false there. Holds the destructive data actions and the
/// local purchase reset used to re-test Restore on a single device.
class AdvancedScreen extends StatelessWidget {
  const AdvancedScreen({super.key});

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Future<void> _clearCache(BuildContext context) async {
    final ok = await studioConfirm(
      context,
      title: 'Clear cache?',
      message: 'Deletes temporary and staging files only. Your books, tracks, '
          'photos, and recordings are kept.',
      confirmLabel: 'Clear cache',
    );
    if (!ok || !context.mounted) return;
    final freed = await AppReset.clearCache();
    if (context.mounted) showToast(context, 'Cache cleared — freed ${_mb(freed)}.');
  }

  Future<void> _eraseAll(BuildContext context) async {
    final ok = await studioConfirm(
      context,
      title: 'Erase all data?',
      message: 'Permanently deletes every book, track, sheet photo, recording, '
          'and all settings on this device. This cannot be undone. Your Pro '
          'purchase is not affected. Force-quit and reopen the app afterwards.',
      confirmLabel: 'Erase everything',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await AppReset.eraseAllData();
    if (!context.mounted) return;
    await studioConfirm(
      context,
      title: 'Data erased',
      message: 'All on-device data has been deleted. Please force-quit and '
          'reopen Metro Sound for a clean start.',
      confirmLabel: 'OK',
    );
  }

  Future<void> _resetPurchase(BuildContext context) async {
    final ok = await studioConfirm(
      context,
      title: 'Reset purchase locally?',
      message: 'Clears the Pro unlock on this device only. Your Apple ID still '
          'owns it — tap "Restore purchase" (or relaunch) to get it back. Used '
          'to test the Restore flow.',
      confirmLabel: 'Reset purchase',
    );
    if (!ok || !context.mounted) return;
    await context.read<Pro>().resetPurchaseLocal();
    if (context.mounted) {
      showToast(context, 'Local Pro cleared — now try Restore purchase.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      title: 'Advanced',
      subtitle: 'Test builds only',
      showBack: true,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Storage & data', icon: Icons.sd_storage_outlined),
          const SizedBox(height: 12),
          StudioCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Action(
                  icon: Icons.cleaning_services_outlined,
                  title: 'Clear cache',
                  subtitle: 'Delete temporary files. Keeps your library.',
                  onTap: () => _clearCache(context),
                ),
                const Divider(height: 24),
                _Action(
                  icon: Icons.delete_forever_outlined,
                  title: 'Erase all data',
                  subtitle: 'Delete all books, tracks, photos, recordings, and '
                      'settings. Cannot be undone.',
                  destructive: true,
                  onTap: () => _eraseAll(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const SectionLabel('Purchase', icon: Icons.workspace_premium_outlined),
          const SizedBox(height: 12),
          StudioCard(
            child: _Action(
              icon: Icons.lock_reset,
              title: 'Reset purchase (local)',
              subtitle: 'Clear the Pro unlock on this device to test Restore. '
                  'Your Apple ID keeps the purchase.',
              onTap: () => _resetPurchase(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable settings row: icon, title, subtitle, chevron.
class _Action extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool destructive;
  final VoidCallback onTap;
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Studio.red : Studio.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 22, color: destructive ? Studio.red : Studio.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Studio.title.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: Studio.bodyDim),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: Studio.textDim),
        ],
      ),
    );
  }
}
