import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.media,
    );
    if (res == null) return;
    final q = _quality.params;
    final resolved = <String>[];
    for (final path in res.paths.whereType<String>()) {
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
    _addPaths(resolved);
  }

  /// Pick any files.
  Future<void> pickFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null) return;
    _addPaths(res.paths.whereType<String>());
  }

  /// Pick a folder → zip it into a single sendable archive.
  Future<void> pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    _addPaths([await MediaSources.zipDirectory(dir)]);
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

  void _addPaths(Iterable<String> paths) {
    final added = paths
        .where((path) => state.every((f) => f.path != path)) // de-dup
        .map((path) => SendableFile.fromPath(path, id: _uuid.v4()))
        .toList();
    if (added.isEmpty) return;
    emit([...state, ...added]);
  }

  bool _isImage(String path) =>
      (lookupMimeType(path) ?? '').startsWith('image/');

  void remove(SendableFile f) =>
      emit(state.where((x) => x.id != f.id).toList());

  void clear() => emit(const []);

  int get totalBytes => state.fold(0, (sum, f) => sum + f.size);
}
