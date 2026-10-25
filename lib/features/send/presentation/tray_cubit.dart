import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/apps/installed_apps_channel.dart';
import '../../../core/io/picked_mtime.dart';
import '../../../core/io/media_picker.dart';
import '../../../core/media/media_sources.dart';
import '../../settings/domain/settings.dart';
import '../domain/sendable_file.dart';

/// The staging tray: files queued to send. Tap a device to send the whole tray.
/// Sources: photos/files/folder (`file_picker`), a typed note or clipboard text,
/// and desktop drag-drop. Images are compressed to the current [MediaQuality].
class TrayCubit extends Cubit<List<SendableFile>> {
  TrayCubit(this._prefs) : super(const []);

  final SharedPreferences _prefs;
  final _uuid = const Uuid();

  MediaQuality get _quality =>
      MediaQuality.values.asNameMap()[_prefs.getString('mediaQuality')] ??
      MediaQuality.original;

  /// Pick photos/videos, compressing images to the current quality setting.
  Future<void> pickMedia() async {
    final picked = await pickMediaPaths();
    if (picked.isEmpty) return;
    await stageMedia(picked);
  }

  /// Stage photos and videos already on disk (the Kirim gallery exports them
  /// when sending), compressing images to the current [MediaQuality]. Returns
  /// the staged files in the order given.
  Future<List<SendableFile>> stageMedia(List<String> paths) async {
    final q = _quality.params;
    final resolved = <String>[];
    for (final path in paths) {
      if (_isImage(path)) {
        resolved.add(
          await MediaSources.compressImage(
            path,
            maxDimension: q.maxDimension,
            quality: q.quality,
          ),
        );
      } else {
        resolved.add(path);
      }
    }
    return _addPaths(resolved);
  }

  /// Stage files as they are (documents received earlier).
  List<SendableFile> addPaths(List<String> paths) => _addPaths(paths);

  /// Put the tray in the order of [ids] (the order the user picked in);
  /// files not named keep their place after them.
  void reorder(List<String> ids) {
    final byId = {for (final f in state) f.id: f};
    final ordered = [
      for (final id in ids)
        if (byId.containsKey(id)) byId.remove(id)!,
      ...state.where((f) => byId.containsKey(f.id)),
    ];
    emit(ordered);
  }

  /// Pick any files.
  Future<void> pickFiles() async {
    final paths = await pickFilePaths();
    if (paths.isEmpty) return;
    _addPaths(paths);
  }

  /// Pick a folder → zip it into a single sendable archive.
  Future<void> pickFolder() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return;
    _addPaths([await MediaSources.zipDirectory(dir)]);
  }

  /// Stage installed apps (Android "App Share") — one `.apk`, or one `.apks`
  /// holding base + splits for an App Bundle install. Each is copied
  /// out of `/data/app` first: that path vanishes if the app updates or
  /// uninstalls mid-transfer, and the copy carries a receiver-friendly name.
  Future<List<SendableFile>> stageApks(List<InstalledApp> apps) async {
    final resolved = <String>[];
    for (final app in apps) {
      try {
        resolved.add(
          await MediaSources.stageApk(
            app.apkPath,
            appName: app.name,
            version: app.version,
            splitPaths: app.splitPaths,
          ),
        );
      } on FileSystemException {
        // App uninstalled/updated between listing and staging — skip it.
      }
    }
    return _addPaths(resolved);
  }

  /// Stage a typed note as a `.txt`.
  Future<void> addText(String text, {String? name}) async {
    if (text.trim().isEmpty) return;
    _addPaths([await MediaSources.writeText(text, name: name)]);
  }

  /// Pick a contact and stage it as a `.vcf`. Returns false if unsupported,
  /// permission was denied, or the picker was cancelled. Never throws — the
  /// native picker is Android/iOS-only, so on desktop this is a no-op.
  Future<bool> pickContact() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        return false;
      }
      final contact = await FlutterContacts.native.showPicker(
        properties: {
          ContactProperty.name,
          ContactProperty.phone,
          ContactProperty.email,
          ContactProperty.organization,
          ContactProperty.address,
        },
      );
      if (contact == null) return false;
      final vcf = FlutterContacts.vCard.export(contact);
      _addPaths([await MediaSources.writeVcf(vcf, name: contact.displayName)]);
      return true;
    } on Object {
      return false;
    }
  }

  /// Stage the clipboard's plain text; returns false if the clipboard is empty.
  Future<bool> pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) return false;
    await addText(text, name: 'clipboard');
    return true;
  }

  /// Add OS drag-dropped paths (desktop). Directories are zipped first.
  Future<void> addDropped(List<String> paths) async {
    final resolved = <String>[];
    for (final path in paths) {
      if (FileSystemEntity.isDirectorySync(path)) {
        resolved.add(await MediaSources.zipDirectory(path));
      } else if (FileSystemEntity.isFileSync(path)) {
        resolved.add(path);
      }
    }
    _addPaths(resolved);
  }

  /// Adds [paths] not already staged; returns the staged file for every path
  /// (an already-staged path returns the existing entry), in order.
  List<SendableFile> _addPaths(Iterable<String> paths) {
    final out = <SendableFile>[];
    final added = <SendableFile>[];
    for (final path in paths) {
      final existing =
          state.where((f) => f.path == path).firstOrNull ??
          added.where((f) => f.path == path).firstOrNull;
      if (existing != null) {
        out.add(existing);
        continue;
      }
      final f = SendableFile.fromPath(path, id: _uuid.v4());
      added.add(f);
      out.add(f);
    }
    if (added.isNotEmpty) emit([...state, ...added]);
    return out;
  }

  bool _isImage(String path) =>
      (lookupMimeType(path) ?? '').startsWith('image/');

  void remove(SendableFile f) =>
      emit(state.where((x) => x.id != f.id).toList());

  void clear() => emit(const []);

  int get totalBytes => state.fold(0, (sum, f) => sum + f.size);
}
