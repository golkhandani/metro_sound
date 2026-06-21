import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/drive_sync.dart';
import '../services/library_store.dart';
import '../ui/studio.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _backup(BuildContext context) async {
    final drive = context.read<DriveSyncService>();
    final lib = context.read<LibraryStore>();
    final folders = await drive.listFolders();
    if (!context.mounted) return;
    showStudioMenu(context, title: 'Back up to…', actions: [
      StudioMenuAction('New folder…', icon: Icons.create_new_folder_outlined,
          onTap: () async {
        final name = await studioPrompt(context,
            title: 'New backup folder', hint: 'Folder name');
        if (name != null && name.trim().isNotEmpty) {
          await drive.backup(lib, folderName: name.trim());
        }
      }),
      for (final f in folders)
        StudioMenuAction(f.name,
            icon: Icons.folder_outlined,
            onTap: () => drive.backup(lib, folderId: f.id)),
    ]);
  }

  Future<void> _load(BuildContext context) async {
    final drive = context.read<DriveSyncService>();
    final lib = context.read<LibraryStore>();
    final folders = await drive.listFolders();
    if (!context.mounted) return;
    if (folders.isEmpty) {
      showToast(context, 'No backup folders found in Drive');
      return;
    }
    showStudioMenu(context, title: 'Load from…', actions: [
      for (final f in folders)
        StudioMenuAction(f.name, icon: Icons.folder_outlined, onTap: () async {
          final ok = await studioConfirm(context,
              title: 'Load "${f.name}"?',
              message:
                  'Replaces your local catalog with this backup. Books and '
                  'tracks not in it will be removed from this device.',
              confirmLabel: 'Load');
          if (ok) await drive.loadCatalog(lib, folderId: f.id);
        }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveSyncService>();

    return StudioScaffold(
      title: 'Settings',
      showBack: true,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Google Drive Sync', icon: Icons.cloud_outlined),
          const SizedBox(height: 12),
          if (!drive.configured)
            StudioCard(
              color: Studio.red.withValues(alpha: 0.12),
              child: const Text(
                'Google Drive is not configured. Add your OAuth client ID/'
                'secret to env.json and rebuild with '
                '--dart-define-from-file=env.json.',
                style: Studio.bodyDim,
              ),
            )
          else ...[
            StudioCard(
              child: Row(
                children: [
                  Icon(drive.isConnected ? Icons.cloud_done : Icons.cloud_off,
                      color: drive.isConnected
                          ? Studio.amber
                          : Studio.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(drive.isConnected ? 'Connected' : 'Not connected',
                            style: Studio.title),
                        const SizedBox(height: 2),
                        Text(
                            drive.isConnected
                                ? (drive.accountLabel ?? 'Signed in')
                                : 'Sign in to back up and load your catalog',
                            style: Studio.bodyDim),
                      ],
                    ),
                  ),
                  if (!drive.busy)
                    StudioButton(
                      label: drive.isConnected ? 'Disconnect' : 'Connect',
                      kind: drive.isConnected
                          ? StudioButtonKind.ghost
                          : StudioButtonKind.filled,
                      onTap: () => drive.isConnected
                          ? drive.disconnect()
                          : drive.connect(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            StudioCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      StudioButton(
                        label: 'Back up to Drive',
                        icon: Icons.cloud_upload_outlined,
                        onTap: (drive.isConnected && !drive.busy)
                            ? () => _backup(context)
                            : null,
                      ),
                      StudioButton(
                        label: 'Load catalog',
                        icon: Icons.cloud_download_outlined,
                        kind: StudioButtonKind.ghost,
                        onTap: (drive.isConnected && !drive.busy)
                            ? () => _load(context)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Backs up audio, photos, covers and progress to a '
                    '"Metro Sound" folder in your Drive (a subfolder per book). '
                    'Load replaces the local catalog.',
                    style: Studio.bodyDim,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (drive.busy || drive.status.isNotEmpty)
              StudioCard(
                child: Row(
                  children: [
                    if (drive.busy) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Studio.amber),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                          drive.status.isEmpty ? 'Working…' : drive.status,
                          style: Studio.body),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 28),
          const _About(),
        ],
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Studio.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Studio.line),
            ),
            child: const Icon(Icons.av_timer, color: Studio.amber, size: 30),
          ),
          const SizedBox(height: 10),
          Text('Metro Sound',
              style: Studio.title.copyWith(letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text('Version $kAppVersion', style: Studio.bodyDim),
          const SizedBox(height: 4),
          const Text('Practice player · metronome · photos',
              style: TextStyle(fontSize: 11, color: Studio.textDim)),
        ],
      ),
    );
  }
}
