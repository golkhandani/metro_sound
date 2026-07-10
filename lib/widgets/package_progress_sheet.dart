import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/package_service.dart';
import '../ui/studio.dart';

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// Bottom sheet showing the current package job: details, live progress,
/// Cancel while running, Share when an export is ready, Close when finished.
/// Dismissing it never touches the job (the global chip keeps it reachable).
Future<void> showPackageProgressSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _PackageProgressSheet(),
  );
}

class _PackageProgressSheet extends StatefulWidget {
  const _PackageProgressSheet();

  @override
  State<_PackageProgressSheet> createState() => _PackageProgressSheetState();
}

class _PackageProgressSheetState extends State<_PackageProgressSheet> {
  bool _autoShared = false;

  Future<void> _share(PackageService service) async {
    final job = service.job;
    final path = job?.outputPath;
    if (job == null || path == null) return;
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(path)],
      subject: job.scopeLabel,
      sharePositionOrigin: box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 100, 100),
    );
    // Whatever the user did in the share sheet, the job stays until they
    // dismiss it here — but a completed share is the natural end.
    if (mounted) {
      service.dismissJob();
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<PackageService>();
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final job = service.job;
        // Auto-open the share sheet exactly once when the export turns ready
        // while this sheet is visible.
        if (job != null &&
            job.state == JobState.ready &&
            service.consumePendingShare() &&
            !_autoShared) {
          _autoShared = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _share(service));
        }
        return Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          decoration: BoxDecoration(
            color: Studio.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Studio.line),
          ),
          child: SafeArea(
            top: false,
            child: job == null ? _empty(context) : _body(context, service, job),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No export in progress', style: Studio.bodyDim),
          ),
          StudioButton(
              label: 'Close',
              kind: StudioButtonKind.ghost,
              onTap: () => Navigator.of(context).pop()),
        ],
      );

  Widget _body(BuildContext context, PackageService service, PackageJob job) {
    final (icon, title) = switch (job.state) {
      JobState.preparing => (Icons.hourglass_top, 'Preparing…'),
      JobState.running => (
          job.kind == JobKind.export ? Icons.ios_share : Icons.download,
          job.kind == JobKind.export ? 'Exporting…' : 'Importing…'
        ),
      JobState.ready => (Icons.check_circle_outline, 'Ready to share'),
      JobState.done => (Icons.check_circle_outline, 'Import complete'),
      JobState.failed => (Icons.error_outline, 'Failed'),
      JobState.cancelled => (Icons.cancel_outlined, 'Cancelled'),
    };
    final accent = switch (job.state) {
      JobState.failed => Studio.red,
      JobState.ready || JobState.done => Studio.teal,
      _ => Studio.amber,
    };

    final detail = StringBuffer();
    if (job.trackCount > 0) detail.write('${job.trackCount} tracks · ');
    detail.write('${job.filesDone}/${job.filesTotal} files');
    if (job.bytesTotal > 0) {
      detail.write(
          ' · ${formatBytes(job.bytesDone)} of ${formatBytes(job.bytesTotal)}');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Studio.title),
                const SizedBox(height: 2),
                Text(job.scopeLabel,
                    style: Studio.bodyDim, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 14),
        if (job.isActive) ...[
          Text(detail.toString(), style: Studio.bodyDim),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Stack(children: [
                Container(color: Studio.line),
                FractionallySizedBox(
                  widthFactor: job.progress.clamp(0.0, 1.0),
                  child: Container(color: Studio.amber),
                ),
              ]),
            ),
          ),
        ] else if (job.state == JobState.failed)
          Text(job.error ?? 'Something went wrong', style: Studio.bodyDim)
        else if (job.state == JobState.done)
          Text(job.resultSummary ?? 'Import complete', style: Studio.bodyDim)
        else if (job.state == JobState.ready)
          Text(
              'The package is ready'
              '${job.bytesTotal > 0 ? ' (${formatBytes(job.bytesTotal)})' : ''}'
              ' — share it anywhere.',
              style: Studio.bodyDim),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (job.isActive)
              StudioButton(
                  label: 'Cancel',
                  kind: StudioButtonKind.ghost,
                  onTap: service.cancel)
            else ...[
              StudioButton(
                label: job.state == JobState.ready ? 'Discard' : 'Close',
                kind: StudioButtonKind.ghost,
                onTap: () {
                  service.dismissJob();
                  Navigator.of(context).pop();
                },
              ),
              if (job.state == JobState.ready) ...[
                const SizedBox(width: 12),
                StudioButton(
                    label: 'Share',
                    icon: Icons.ios_share,
                    onTap: () => _share(service)),
              ],
            ],
          ],
        ),
      ],
    );
  }
}
