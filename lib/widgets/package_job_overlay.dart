import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/package_service.dart';
import '../ui/studio.dart';
import 'package_progress_sheet.dart';

/// Navigator key so the overlay (which floats above all routes via
/// MaterialApp.builder) can open the progress sheet on the active navigator.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// A small floating pill shown whenever a package job is running or an export
/// is ready to share. Visible on every screen (it sits above the Navigator);
/// tapping it opens the progress sheet. Also auto-opens the sheet when a
/// ready export is surfaced by a notification tap or app resume.
class PackageJobOverlay extends StatefulWidget {
  const PackageJobOverlay({super.key});

  @override
  State<PackageJobOverlay> createState() => _PackageJobOverlayState();
}

class _PackageJobOverlayState extends State<PackageJobOverlay> {
  PackageService? _service;
  bool _sheetOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<PackageService>();
    if (service != _service) {
      _service?.removeListener(_onService);
      _service = service..addListener(_onService);
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_onService);
    super.dispose();
  }

  void _onService() {
    final service = _service!;
    // A notification tap / foreground resume flagged a ready export: surface it.
    if (service.hasReadyExport &&
        !_sheetOpen &&
        service.consumePendingShare()) {
      _openSheet();
    }
  }

  Future<void> _openSheet() async {
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null || _sheetOpen) return;
    _sheetOpen = true;
    try {
      await showPackageProgressSheet(navContext);
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PackageService>();
    final job = service.job;
    final visible =
        job != null && (job.isActive || job.state == JobState.ready);
    if (!visible) return const SizedBox.shrink();

    final ready = job.state == JobState.ready;
    final label = ready
        ? 'Ready — tap to share'
        : job.kind == JobKind.export
        ? 'Exporting… ${(job.progress * 100).round()}%'
        : 'Importing… ${(job.progress * 100).round()}%';

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 6,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: _openSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Studio.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ready ? Studio.amber : Studio.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ready)
                  Icon(Icons.ios_share, size: 14, color: Studio.amber)
                else
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Studio.amber,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Studio.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
