import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../receive/presentation/receive_cubit.dart';
import 'tv_focusable.dart';

/// TV-side incoming layer: a centered, D-pad Accept/Decline prompt while a
/// transfer is pending, then a live progress banner while it downloads. Sits on
/// top of the [TvShell] stack.
class TvIncomingOverlay extends StatelessWidget {
  const TvIncomingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiveCubit, ReceiveState>(
      builder: (context, state) {
        if (state.pending != null) {
          return _AcceptPrompt(state: state);
        }
        final p = state.progress;
        if (p != null && !p.isComplete) {
          return _ProgressBanner(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

String _fmtBytes(int b) {
  if (b < 1024) return '$b B';
  final kb = b / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

class _AcceptPrompt extends StatelessWidget {
  const _AcceptPrompt({required this.state});
  final ReceiveState state;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final pending = state.pending!;
    final count = pending.files.length;
    final cubit = context.read<ReceiveCubit>();

    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      alignment: Alignment.center,
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.download_rounded, size: 34, color: cs.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'tv.incoming_title'.tr(),
              style: TextStyle(
                color: cs.foreground,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'tv.incoming_desc'.tr(namedArgs: {
                'sender': pending.sender.alias,
                'files': 'tv.n_files'.plural(count),
                'size': _fmtBytes(pending.totalBytes),
              }),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.mutedForeground, fontSize: 18),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: _TvButton(
                    label: 'tv.decline'.tr(),
                    primary: false,
                    onSelect: cubit.reject,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _TvButton(
                    label: 'tv.accept'.tr(),
                    primary: true,
                    autofocus: true,
                    onSelect: cubit.accept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TvButton extends StatelessWidget {
  const _TvButton({
    required this.label,
    required this.onSelect,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onSelect;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (context, focused) {
        final bg = primary ? cs.primary : cs.secondary;
        final fg = primary ? cs.primaryForeground : cs.foreground;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? cs.foreground : Colors.transparent,
              width: 3,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.4),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({required this.state});
  final ReceiveState state;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final p = state.progress!;
    final speed = state.speed;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.download_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'tv.receiving_from'.tr(namedArgs: {
                      'sender': p.senderAlias,
                      'file': p.currentFileName,
                    }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.foreground,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${p.completedFiles}/${p.totalFiles}',
                  style: TextStyle(color: cs.mutedForeground, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: p.fraction,
                minHeight: 8,
                backgroundColor: cs.border,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${(p.fraction * 100).toStringAsFixed(0)}%'
              '${speed > 0 ? '  ·  ${_fmtBytes(speed.round())}/s' : ''}',
              style: TextStyle(color: cs.mutedForeground, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
