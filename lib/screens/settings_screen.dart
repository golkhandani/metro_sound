import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/features.dart';
import '../services/drive_sync.dart';
import '../services/icloud_sync.dart';
import '../services/library_store.dart';
import '../services/metronome.dart';
import '../services/package_service.dart';
import '../services/pro.dart';
import '../services/settings.dart';
import '../ui/studio.dart';
import '../dev/screenshot_director.dart';
import 'advanced_screen.dart';
import '../widgets/coach_marks.dart';
import '../widgets/import_preview_sheet.dart';
import '../widgets/package_progress_sheet.dart';
import '../widgets/pro_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _backup(BuildContext context) async {
    final drive = context.read<DriveSyncService>();
    final lib = context.read<LibraryStore>();
    final folders = await drive.listFolders();
    if (!context.mounted) return;
    showStudioMenu(
      context,
      title: 'Back up to…',
      actions: [
        StudioMenuAction(
          'New folder…',
          icon: Icons.create_new_folder_outlined,
          onTap: () async {
            final name = await studioPrompt(
              context,
              title: 'New backup folder',
              hint: 'Folder name',
            );
            if (name != null && name.trim().isNotEmpty) {
              await drive.backup(lib, folderName: name.trim());
            }
          },
        ),
        for (final f in folders)
          StudioMenuAction(
            f.name,
            icon: Icons.folder_outlined,
            onTap: () => drive.backup(lib, folderId: f.id, folderName: f.name),
          ),
      ],
    );
  }

  /// Export the whole library in the background and show the progress sheet.
  Future<void> _shareLibrary(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final books = library.books.toList();
    if (books.isEmpty) {
      showToast(context, 'No books to share yet');
      return;
    }
    final packages = context.read<PackageService>();
    if (!await packages.startExportBooks(books, label: 'MetroSound Library')) {
      if (context.mounted) {
        showToast(context, 'Another export is already running');
      }
      return;
    }
    if (context.mounted) await showPackageProgressSheet(context);
  }

  /// Pick a shared `.metrosound` file, preview its contents, choose which
  /// books/tracks to import (append or new copy), then import in background.
  Future<void> _importShared(BuildContext context) async {
    final pro = context.read<Pro>();
    final library = context.read<LibraryStore>();
    if (!pro.isPro && library.books.length >= Pro.freeBookLimit) {
      return showProSheet(
        context,
        reason:
            '${Pro.freeLibraryLimitText} '
            'Unlock Pro for an unlimited library.',
      );
    }
    return runPackageImportFlow(context);
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
    showStudioMenu(
      context,
      title: 'Load from…',
      actions: [
        for (final f in folders)
          StudioMenuAction(
            f.name,
            icon: Icons.folder_outlined,
            onTap: () async {
              final ok = await studioConfirm(
                context,
                title: 'Load "${f.name}"?',
                message:
                    'Replaces your local catalog with this backup. Books and '
                    'tracks not in it will be removed from this device.',
                confirmLabel: 'Load',
              );
              if (ok) {
                await drive.loadCatalog(
                  lib,
                  folderId: f.id,
                  folderName: f.name,
                );
              }
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveSyncService>();
    final m = context.watch<Metronome>();

    return StudioScaffold(
      title: 'Settings',
      showBack: false,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Developer/testing shortcuts. Only shown on a test build (debug or
          // TestFlight); hidden in the production App Store because isTestBuild
          // is false there. They deep-link into the Advanced page.
          if (context.watch<Pro>().isTestBuild && !ScreenshotDirector.active) ...[
            const SectionLabel('Testing', icon: Icons.science_outlined),
            const SizedBox(height: 12),
            StudioCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Developer tools — test builds only, hidden in the App Store.',
                    style: Studio.bodyDim,
                  ),
                  const SizedBox(height: 12),
                  StudioButton(
                    label: 'Storage & data cleanup',
                    icon: Icons.cleaning_services_outlined,
                    kind: StudioButtonKind.ghost,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdvancedScreen()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  StudioButton(
                    label: 'Reset purchase',
                    icon: Icons.lock_reset,
                    kind: StudioButtonKind.ghost,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdvancedScreen()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],
          if (context.watch<Pro>().supported) ...[
            const SectionLabel(
              'Metro Sound Pro',
              icon: Icons.workspace_premium_outlined,
            ),
            const SizedBox(height: 12),
            const _ProCard(),
            const SizedBox(height: 28),
          ],
          const SectionLabel('Appearance', icon: Icons.brightness_6_outlined),
          const SizedBox(height: 12),
          StudioCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) {
                    final mode = context.select<AppSettings, String>(
                      (s) => s.themeMode,
                    );
                    return StudioSegmented<String>(
                      selected: mode,
                      options: const [
                        ('system', 'System'),
                        ('light', 'Light'),
                        ('dark', 'Dark'),
                      ],
                      onChanged: (m) =>
                          context.read<AppSettings>().setThemeMode(m),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'System follows your iPhone appearance automatically.',
                  style: Studio.bodyDim,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const SectionLabel('Metronome', icon: Icons.av_timer),
          const SizedBox(height: 12),
          StudioCard(
            key: CoachKeys.settingsMetroCard,
            child: Column(
              children: [
                _SettingToggle(
                  icon: m.lockedToMusic
                      ? Icons.lock_clock
                      : Icons.lock_open_outlined,
                  title: 'Lock click to music',
                  subtitle: 'Beats follow the track so the click never drifts',
                  value: m.lockedToMusic,
                  onChanged: m.setLockedToMusic,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Studio.line, height: 1),
                ),
                _SettingToggle(
                  icon: m.visualEnabled
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  title: 'Visual metronome',
                  subtitle: 'Animated pendulum that swings with the beat',
                  value: m.visualEnabled,
                  onChanged: m.setVisualEnabled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const SectionLabel('Share libraries', icon: Icons.ios_share),
          const SizedBox(height: 12),
          StudioCard(
            key: CoachKeys.settingsShareCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioButton(
                  label: 'Share my library',
                  icon: Icons.ios_share,
                  onTap: () => _shareLibrary(context),
                ),
                const SizedBox(height: 10),
                StudioButton(
                  label: 'Import shared library',
                  icon: Icons.download_outlined,
                  kind: StudioButtonKind.ghost,
                  onTap: () => _importShared(context),
                ),
                const SizedBox(height: 12),
                Text(
                  'Share sends your whole library as one file (any channel — '
                  'AirDrop, Messages, Drive…). Import adds a library someone '
                  'sent you. You can also share a single book from inside it.',
                  style: Studio.bodyDim,
                ),
              ],
            ),
          ),
          // iCloud sync (iOS/macOS) — behind a flag until provisioned + tested.
          if (icloudSyncEnabled) ...[
            const SizedBox(height: 28),
            const SectionLabel('iCloud Sync', icon: Icons.cloud_outlined),
            const SizedBox(height: 12),
            const _ICloudSyncCard(),
          ],
          // Hidden for the initial release; ships later (maybe paid).
          if (driveSyncEnabled) ...[
            const SizedBox(height: 28),
            const SectionLabel('Google Drive Sync', icon: Icons.cloud_outlined),
            const SizedBox(height: 12),
            if (!drive.configured)
              StudioCard(
                color: Studio.red.withValues(alpha: 0.12),
                child: Text(
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
                    Icon(
                      drive.isConnected ? Icons.cloud_done : Icons.cloud_off,
                      color: drive.isConnected
                          ? Studio.amber
                          : Studio.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            drive.isConnected ? 'Connected' : 'Not connected',
                            style: Studio.title,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            drive.isConnected
                                ? (drive.accountLabel ?? 'Signed in')
                                : 'Sign in to back up and load your catalog',
                            style: Studio.bodyDim,
                          ),
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
              if (drive.isConnected) ...[
                const SizedBox(height: 14),
                StudioCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            drive.autoSyncEnabled
                                ? Icons.sync
                                : Icons.sync_disabled,
                            color: drive.autoSyncEnabled
                                ? Studio.amber
                                : Studio.textSecondary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Auto-sync (two-way)',
                                  style: Studio.title,
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Edits sync to Drive automatically and pull '
                                  'changes from your other devices',
                                  style: Studio.bodyDim,
                                ),
                              ],
                            ),
                          ),
                          StudioSwitch(
                            value: drive.autoSyncEnabled,
                            onChanged: (v) => drive.setAutoSync(v),
                          ),
                        ],
                      ),
                      if (drive.autoSyncEnabled &&
                          drive.autoSyncState.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: drive.autoSyncState == 'Synced'
                                  ? Studio.teal
                                  : Studio.amber,
                            ),
                            const SizedBox(width: 8),
                            Text(drive.autoSyncState, style: Studio.bodyDim),
                          ],
                        ),
                      ],
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: Studio.line, height: 1),
                      ),
                      Text(
                        'How it works:\n'
                        '• Your edits (done, BPM, photos, names…) upload to your '
                        '"Metro Sound" Drive folder a few seconds after each change.\n'
                        '• Changes from your other devices are pulled in about every '
                        '30 seconds and merged — newest edit wins per item, so '
                        'nothing gets silently overwritten.\n'
                        '• Offline edits are saved and sync automatically once '
                        "you're back online.\n"
                        '• Turn this on with the same Google account on every device.',
                        style: Studio.bodyDim,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              StudioCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StudioButton(
                      label: 'Back up to Drive',
                      icon: Icons.cloud_upload_outlined,
                      onTap: (drive.isConnected && !drive.busy)
                          ? () => _backup(context)
                          : null,
                    ),
                    const SizedBox(height: 10),
                    StudioButton(
                      label: 'Load catalog',
                      icon: Icons.cloud_download_outlined,
                      kind: StudioButtonKind.ghost,
                      onTap: (drive.isConnected && !drive.busy)
                          ? () => _load(context)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Backs up audio, photos, covers and progress into a '
                      '"Metro Sound" folder (created inside the folder you pick, '
                      'with a subfolder per book). Load replaces the local catalog.',
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
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Studio.amber,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          drive.status.isEmpty ? 'Working…' : drive.status,
                          style: Studio.body,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
          const SizedBox(height: 28),
          const SectionLabel('Help', icon: Icons.help_outline),
          const SizedBox(height: 12),
          StudioCard(
            padding: EdgeInsets.zero,
            child: Pressable(
              onTap: () => context.read<AppSettings>().resetTutorial(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.replay, color: Studio.amber, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Replay tutorial', style: Studio.title),
                          SizedBox(height: 2),
                          Text(
                            'Show the intro tour and on-screen tips again',
                            style: Studio.bodyDim,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Studio.textDim, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const _About(),
        ],
      ),
    );
  }
}

/// A labeled on/off row used in the settings cards.
class _SettingToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: value ? Studio.amber : Studio.textSecondary,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Studio.title),
              const SizedBox(height: 2),
              Text(subtitle, style: Studio.bodyDim),
            ],
          ),
        ),
        StudioSwitch(value: value, onChanged: onChanged),
      ],
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
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/icon/icon_ios.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 10),
          Text('Metro Sound', style: Studio.title.copyWith(letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text('Version $kAppVersion', style: Studio.bodyDim),
          const SizedBox(height: 4),
          Text(
            'Practice player · metronome · photos',
            style: TextStyle(fontSize: 11, color: Studio.textDim),
          ),
        ],
      ),
    );
  }
}

/// Purchase state card: an upgrade pitch for free users, a thank-you for Pro.
class _ProCard extends StatelessWidget {
  const _ProCard();

  @override
  Widget build(BuildContext context) {
    final pro = context.watch<Pro>();
    if (pro.isPro) {
      return StudioCard(
        child: Row(
          children: [
            Icon(Icons.verified_outlined, size: 20, color: Studio.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pro unlocked — thank you for supporting Metro Sound!',
                style: Studio.body,
              ),
            ),
          ],
        ),
      );
    }
    return StudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Unlimited books, the practice recorder, and no reminders — '
            'one purchase, yours forever.',
            style: Studio.bodyDim,
          ),
          const SizedBox(height: 12),
          StudioButton(
            label: 'Unlock Pro — ${pro.price}',
            icon: Icons.lock_open_outlined,
            onTap: () => showProSheet(context),
          ),
          const SizedBox(height: 10),
          StudioButton(
            label: 'Restore purchase',
            kind: StudioButtonKind.ghost,
            onTap: pro.restore,
          ),
        ],
      ),
    );
  }
}

/// iCloud sync controls + live status (gated by `icloudSyncEnabled`).
class _ICloudSyncCard extends StatelessWidget {
  const _ICloudSyncCard();

  @override
  Widget build(BuildContext context) {
    final icloud = context.watch<ICloudSyncService>();
    final (IconData sIcon, String sLabel, Color sColor) = switch (icloud.state) {
      ICloudState.syncing => (Icons.sync, 'Syncing…', Studio.amber),
      ICloudState.synced => (Icons.cloud_done_outlined, 'Synced', Studio.amber),
      ICloudState.error => (Icons.cloud_off_outlined, 'Sync error', Studio.red),
      ICloudState.unavailable =>
        (Icons.cloud_off_outlined, 'iCloud unavailable', Studio.textDim),
      _ => (Icons.cloud_outlined, 'Off', Studio.textDim),
    };
    final showErr = icloud.error != null &&
        (icloud.state == ICloudState.error ||
            icloud.state == ICloudState.unavailable);
    return StudioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, size: 22, color: Studio.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sync with iCloud', style: Studio.title),
                    const SizedBox(height: 2),
                    Text('Keep your books in sync across your devices',
                        style: Studio.bodyDim),
                  ],
                ),
              ),
              StudioSwitch(
                value: icloud.autoSync,
                onChanged: (v) => icloud.setAutoSync(v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(sIcon, size: 16, color: sColor),
              const SizedBox(width: 6),
              Text(sLabel, style: Studio.bodyDim.copyWith(color: sColor)),
            ],
          ),
          if (showErr) ...[
            const SizedBox(height: 8),
            Text(icloud.error!,
                style: TextStyle(fontSize: 12, color: Studio.red)),
          ],
          if (icloud.autoSync && icloud.available) ...[
            const SizedBox(height: 12),
            StudioButton(
              label: 'Sync now',
              kind: StudioButtonKind.ghost,
              onTap: () => icloud.syncNow(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Your library lives in your own private iCloud and stays in sync '
            'across your devices. Nothing is sent to our servers.',
            style: Studio.bodyDim,
          ),
        ],
      ),
    );
  }
}
