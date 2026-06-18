import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/drive_sync.dart';
import '../services/library_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveSyncService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Google Drive sync',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          if (!drive.configured)
            Card(
              color: cs.errorContainer.withValues(alpha: 0.5),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Google Drive is not configured yet.\n\n'
                  'Add your OAuth client ID and secret in '
                  'lib/config/google_config.dart (see GOOGLE_DRIVE_SETUP.md), '
                  'then rebuild the app.',
                ),
              ),
            )
          else ...[
            Card(
              child: ListTile(
                leading: Icon(
                  drive.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: drive.isConnected ? cs.primary : cs.outline,
                ),
                title: Text(drive.isConnected
                    ? 'Connected'
                    : 'Not connected'),
                subtitle: Text(drive.isConnected
                    ? (drive.accountLabel ?? 'Signed in to Google Drive')
                    : 'Sign in to back up and load your catalog'),
                trailing: drive.busy
                    ? null
                    : (drive.isConnected
                        ? TextButton(
                            onPressed: () => drive.disconnect(),
                            child: const Text('Disconnect'),
                          )
                        : FilledButton(
                            onPressed: () => drive.connect(),
                            child: const Text('Connect'),
                          )),
              ),
            ),
            const SizedBox(height: 16),

            // Backup / Load actions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: (drive.isConnected && !drive.busy)
                          ? () => _backup(context)
                          : null,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Back up to Drive'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Uploads all audio, photos, covers and progress to a '
                      '"Metro Sound" folder in your Drive.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Divider(height: 28),
                    OutlinedButton.icon(
                      onPressed: (drive.isConnected && !drive.busy)
                          ? () => _load(context)
                          : null,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Load catalog from Drive'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Replaces the local catalog with the one in Drive and '
                      'downloads any missing files. Use this on a new device.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            if (drive.busy || drive.status.isNotEmpty)
              Card(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (drive.busy) ...[
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: drive.progress,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(drive.status.isEmpty
                            ? 'Working…'
                            : drive.status),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _load(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Load catalog from Drive?'),
        content: const Text(
          'This replaces your current local catalog with the one stored in '
          'Drive. Books and tracks not in Drive will be removed from this '
          'device. Continue?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Load')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final drive = context.read<DriveSyncService>();
    final library = context.read<LibraryStore>();
    await drive.loadCatalog(library);
  }

  Future<void> _backup(BuildContext context) async {
    final drive = context.read<DriveSyncService>();
    final library = context.read<LibraryStore>();
    await drive.backup(library);
  }
}
