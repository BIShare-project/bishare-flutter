import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';
import '../../send/presentation/tray_cubit.dart';
import '../../send/presentation/voice_recorder_sheet.dart';

/// The native-style share source grid: 6 tinted pills in 2 rows × 3 columns
/// (Photos · Files · Text / Contacts · Voice · Paste). Long-press Files → folder.
class SourceGrid extends StatelessWidget {
  const SourceGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final tray = context.read<TrayCubit>();
    Widget pill(
      String icon,
      String label,
      Color color,
      VoidCallback onTap, {
      VoidCallback? onLongPress,
    }) => Expanded(
      child: AppSourcePill(
        icon: icon,
        label: label,
        color: color,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );

    return Column(
      children: [
        Row(
          children: [
            pill(
              AppIcons.image,
              'home.photos'.tr(),
              const Color(0xFF0A84FF),
              tray.pickMedia,
            ),
            const SizedBox(width: 8),
            pill(
              AppIcons.newFolder,
              'home.files'.tr(),
              const Color(0xFFFF9F0A),
              tray.pickFiles,
              onLongPress: tray.pickFolder,
            ),
            const SizedBox(width: 8),
            pill(
              AppIcons.note,
              'home.text'.tr(),
              const Color(0xFFAF52DE),
              () => _textNote(context, tray),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            pill(
              AppIcons.user,
              'home.contacts'.tr(),
              const Color(0xFF5E5CE6),
              () => _pickContact(context, tray),
            ),
            const SizedBox(width: 8),
            pill(
              AppIcons.mic,
              'home.voice'.tr(),
              const Color(0xFFFF2D55),
              () => _pickVoice(context, tray),
            ),
            const SizedBox(width: 8),
            pill(
              AppIcons.clipboardPaste,
              'home.paste'.tr(),
              const Color(0xFF30B0C7),
              () => _paste(context, tray),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _pickContact(BuildContext context, TrayCubit tray) async {
  final ok = await tray.pickContact();
  if (!ok && context.mounted) toast(context, 'home.no_contact_added'.tr());
}

Future<void> _pickVoice(BuildContext context, TrayCubit tray) async {
  final path = await showVoiceRecorder(context);
  if (path != null) await tray.addDropped([path]);
}

Future<void> _paste(BuildContext context, TrayCubit tray) async {
  final ok = await tray.pasteClipboard();
  if (!ok && context.mounted) toast(context, 'home.clipboard_empty'.tr());
}

Future<void> _textNote(BuildContext context, TrayCubit tray) async {
  final controller = TextEditingController();
  final text = await showAppSheet<String>(
    context,
    icon: AppIcons.note,
    title: 'home.text_note'.tr(),
    subtitle: 'home.text_note_subtitle'.tr(),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShadInput(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          placeholder: Text('home.type_something'.tr()),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ShadButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('home.add'.tr()),
          ),
        ),
      ],
    ),
  );
  if (text != null && text.trim().isNotEmpty) await tray.addText(text);
}
