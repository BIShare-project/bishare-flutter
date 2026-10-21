import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/app_database.dart';
import '../../../../core/storage/vault_tables.dart';

/// Where the Drive screen is looking.
enum DriveView { files, recent, media, documents, audio, trash }

enum DriveSort { name, modified, size, kind }

/// MIME families of the Documents view (besides `text/*`).
const driveDocumentTypes = [
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.oasis.opendocument.text',
  'application/vnd.oasis.opendocument.spreadsheet',
  'application/vnd.oasis.opendocument.presentation',
  'application/rtf',
  'application/epub+zip',
  'application/json',
  'application/xml',
];

/// The state of one Drive screen: view, folder path, search, sort, grid or
/// list, and the selection. Sort and layout are remembered on the device.
class DriveController extends ChangeNotifier {
  DriveController(this._dao, {SharedPreferences? prefs}) : _prefs = prefs {
    final p = prefs;
    if (p != null) {
      _grid = p.getBool(_kGrid) ?? false;
      _sort = DriveSort.values.firstWhere(
        (s) => s.name == p.getString(_kSort),
        orElse: () => DriveSort.name,
      );
      _ascending = p.getBool(_kAsc) ?? true;
    }
  }

  final VaultDao _dao;
  final SharedPreferences? _prefs;

  static const _kGrid = 'vault.grid';
  static const _kSort = 'vault.sort';
  static const _kAsc = 'vault.sortAscending';

  DriveView _view = DriveView.files;
  final List<VaultObject> _path = [];
  String _query = '';
  bool _grid = false;
  DriveSort _sort = DriveSort.name;
  bool _ascending = true;
  final Set<String> _selected = {};
  String? _anchor;

  DriveView get view => _view;
  List<VaultObject> get path => List.unmodifiable(_path);
  String? get folder => _path.isEmpty ? null : _path.last.id;
  String get query => _query;
  bool get searching => _query.trim().isNotEmpty;
  bool get grid => _grid;
  DriveSort get sort => _sort;
  bool get ascending => _ascending;
  Set<String> get selected => Set.unmodifiable(_selected);
  bool get selecting => _selected.isNotEmpty;

  /// Folders can be made and files added only in the folder view.
  bool get canAdd => _view == DriveView.files && !searching;

  // ---- where ---------------------------------------------------------------------

  void setView(DriveView v) {
    if (_view == v && !searching && _path.isEmpty) return;
    _view = v;
    _path.clear();
    _query = '';
    _selected.clear();
    notifyListeners();
  }

  void open(VaultObject folder) {
    if (folder.kind != 'dir') return;
    _view = DriveView.files;
    _query = '';
    _path.add(folder);
    _selected.clear();
    notifyListeners();
  }

  /// Show [folder] with its whole path (from search results or Recent).
  Future<void> reveal(String? folder) async {
    final path = folder == null ? <VaultObject>[] : await _dao.pathTo(folder);
    _view = DriveView.files;
    _query = '';
    _path
      ..clear()
      ..addAll(path);
    _selected.clear();
    notifyListeners();
  }

  /// One folder up; false at the top (the caller may leave the screen).
  bool up() {
    if (selecting) {
      clearSelection();
      return true;
    }
    if (searching) {
      setQuery('');
      return true;
    }
    if (_path.isEmpty) {
      if (_view == DriveView.files) return false;
      setView(DriveView.files);
      return true;
    }
    _path.removeLast();
    _selected.clear();
    notifyListeners();
    return true;
  }

  /// Back to the [depth]-th folder of the path (0: the top of the Drive).
  void goTo(int depth) {
    if (depth >= _path.length) return;
    _path.removeRange(depth, _path.length);
    _selected.clear();
    notifyListeners();
  }

  /// Back to the top of the Drive with nothing selected (another account).
  void reset() {
    _view = DriveView.files;
    _path.clear();
    _query = '';
    _selected.clear();
    notifyListeners();
  }

  /// Drop folders from the path that no longer exist (deleted or trashed on
  /// another device).
  Future<void> prune() async {
    for (var i = 0; i < _path.length; i++) {
      final o = await _dao.object(_path[i].id);
      if (o == null || o.trashedAt != null) {
        _path.removeRange(i, _path.length);
        notifyListeners();
        return;
      }
      _path[i] = o;
    }
  }

  void setQuery(String q) {
    if (q == _query) return;
    _query = q;
    _selected.clear();
    notifyListeners();
  }

  // ---- how ---------------------------------------------------------------------------

  void setGrid(bool grid) {
    _grid = grid;
    _prefs?.setBool(_kGrid, grid);
    notifyListeners();
  }

  void setSort(DriveSort sort) {
    if (_sort == sort) {
      _ascending = !_ascending;
    } else {
      _sort = sort;
      // Newest and largest first is what people want from those two.
      _ascending = sort == DriveSort.name || sort == DriveSort.kind;
    }
    _prefs?.setString(_kSort, _sort.name);
    _prefs?.setBool(_kAsc, _ascending);
    notifyListeners();
  }

  /// The items of the current view, in order. Folders stay first.
  Stream<List<VaultObject>> items() {
    final Stream<List<VaultObject>> source;
    if (searching) {
      // Search in Trash looks only at what is in the trash, so what it finds
      // gets the trash's actions (restore, delete for good) and nothing else.
      source = _view == DriveView.trash
          ? _dao.watchTrash().map(
              (all) => _topOfTrash(all).where(_matches).toList(),
            )
          : _dao.watchSearch(_query);
    } else {
      source = switch (_view) {
        DriveView.files => _dao.watchChildren(folder),
        DriveView.recent => _dao.watchRecent(),
        DriveView.media => _dao.watchFilesOfType(
          prefixes: ['image/', 'video/'],
        ),
        DriveView.documents => _dao.watchFilesOfType(
          prefixes: ['text/'],
          types: driveDocumentTypes,
        ),
        DriveView.audio => _dao.watchFilesOfType(prefixes: ['audio/']),
        DriveView.trash => _dao.watchTrash().map(_topOfTrash),
      };
    }
    // Recent keeps its own order (newest first).
    if (_view == DriveView.recent && !searching) return source;
    return source.map(sorted);
  }

  bool _matches(VaultObject o) =>
      o.name.toLowerCase().contains(_query.trim().toLowerCase());

  /// Only the top of each trashed tree: a trashed folder shows once.
  static List<VaultObject> _topOfTrash(List<VaultObject> all) {
    final ids = {for (final o in all) o.id};
    return all
        .where((o) => o.parent == null || !ids.contains(o.parent))
        .toList();
  }

  List<VaultObject> sorted(List<VaultObject> list) {
    int byKey(VaultObject a, VaultObject b) {
      final r = switch (_sort) {
        DriveSort.name => _name(a, b),
        DriveSort.modified => a.mtime.compareTo(b.mtime),
        DriveSort.size => (a.size ?? 0).compareTo(b.size ?? 0),
        DriveSort.kind => _ext(a).compareTo(_ext(b)),
      };
      final tie = r == 0 ? _name(a, b) : r;
      return _ascending || r == 0 ? tie : -tie;
    }

    return [...list]..sort((a, b) {
      if (a.kind != b.kind) return a.kind == 'dir' ? -1 : 1;
      return byKey(a, b);
    });
  }

  static int _name(VaultObject a, VaultObject b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  static String _ext(VaultObject o) {
    final dot = o.name.lastIndexOf('.');
    return dot > 0 ? o.name.substring(dot + 1).toLowerCase() : '';
  }

  // ---- selection ------------------------------------------------------------------

  bool isSelected(String id) => _selected.contains(id);

  void toggle(String id) {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
    _anchor = id;
    notifyListeners();
  }

  /// Shift-click: everything between the last clicked item and [id].
  void selectRange(List<VaultObject> visible, String id) {
    final a = visible.indexWhere((o) => o.id == _anchor);
    final b = visible.indexWhere((o) => o.id == id);
    if (a < 0 || b < 0) return toggle(id);
    final (from, to) = a < b ? (a, b) : (b, a);
    for (var i = from; i <= to; i++) {
      _selected.add(visible[i].id);
    }
    notifyListeners();
  }

  void selectAll(List<VaultObject> visible) {
    if (visible.every((o) => _selected.contains(o.id))) {
      _selected.clear();
    } else {
      _selected.addAll(visible.map((o) => o.id));
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Keep only ids still on screen (after a move or delete).
  void keepSelected(Iterable<String> visible) {
    final keep = visible.toSet();
    final before = _selected.length;
    _selected.removeWhere((id) => !keep.contains(id));
    if (_selected.length != before) notifyListeners();
  }
}
