import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/pro.dart';
import '../ui/studio.dart';

/// The one Pro surface: shown as a gate (recorder, 4th book) with a [reason],
/// or as the polite post-session reminder (no reason). Everything stays
/// one-tap dismissable — no delays, no guilt copy.
Future<void> showProSheet(BuildContext context, {String? reason}) {
  final pro = context.read<Pro>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: pro,
      child: _ProSheet(reason: reason),
    ),
  );
}

class _ProSheet extends StatelessWidget {
  final String? reason;
  const _ProSheet({this.reason});

  @override
  Widget build(BuildContext context) {
    final pro = context.watch<Pro>();
    // Purchase completed while the sheet is up — close it on the next frame.
    if (pro.isPro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Studio.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Studio.line),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium_outlined,
                      size: 20, color: Studio.amber),
                  const SizedBox(width: 8),
                  Text('METRO SOUND PRO', style: Studio.label),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                reason ??
                    'Enjoying the practice sessions? One small purchase '
                        'unlocks everything — forever.',
                style: Studio.body,
              ),
              const SizedBox(height: 14),
              const _Benefit(
                icon: Icons.library_music_outlined,
                text: 'Unlimited books in your library',
              ),
              const _Benefit(
                icon: Icons.mic_none,
                text: 'Record your own practice takes',
              ),
              const _Benefit(
                icon: Icons.notifications_off_outlined,
                text: 'No more reminders',
              ),
              const _Benefit(
                icon: Icons.favorite_outline,
                text: 'Support an independent musician-made app',
              ),
              if (pro.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  pro.error!,
                  style: Studio.bodyDim.copyWith(color: Studio.red),
                ),
              ],
              const SizedBox(height: 16),
              StudioButton(
                label: pro.purchasing
                    ? 'Contacting the App Store…'
                    : 'Unlock Pro — ${pro.price} once',
                icon: Icons.lock_open_outlined,
                onTap: pro.purchasing ? () {} : pro.buy,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StudioButton(
                    label: 'Restore purchase',
                    kind: StudioButtonKind.ghost,
                    onTap: pro.restore,
                  ),
                  StudioButton(
                    label: 'Not now',
                    kind: StudioButtonKind.ghost,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Benefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Studio.amber),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Studio.bodyDim)),
        ],
      ),
    );
  }
}
