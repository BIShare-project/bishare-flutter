import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/drive_service.dart';
import '../domain/drive_models.dart';

/// Maps a thrown error (usually a [DriveException]) to a localization key so the
/// UI can toast a friendly, honest message instead of a raw exception.
String driveErrorKey(Object e) {
  final code = e is DriveException ? e.code : null;
  return switch (code) {
    'STORAGE_LIMIT_EXCEEDED' => 'drive.error_storage_limit',
    'FILE_TOO_LARGE' => 'drive.error_file_too_large',
    'DUPLICATE_NAME' => 'drive.error_duplicate_name',
    'FOLDER_DEPTH_EXCEEDED' => 'drive.error_depth',
    'VALIDATION_ERROR' => 'drive.error_invalid',
    'NOT_FOUND' => 'drive.error_not_found',
    'NETWORK' => 'drive.error_network',
    'CANCELLED' => 'drive.error_cancelled',
    _ => 'drive.error_generic',
  };
}

/// How the current folder's files are ordered.
enum DriveSort { name, newest, largest }

extension DriveSortApi on DriveSort {
  String get field => switch (this) {
    DriveSort.name => 'name',
    DriveSort.newest => 'created_at',
    DriveSort.largest => 'size',
  };

  String get order => this == DriveSort.name ? 'asc' : 'desc';
}

/// Immutable Drive-browse state (the app's Cubit convention — cf. `AuthState`).
class DriveState extends Equatable {
  const DriveState({
    this.loading = true,
    this.loadingMore = false,
    this.errorKey,
    this.folderId,
    this.breadcrumb = const [],
    this.folders = const [],
    this.files = const [],
    this.page = 1,
    this.hasMore = false,
    this.sort = DriveSort.name,
    this.storage,
  });

  /// The initial load of the current folder is in flight.
  final bool loading;

  /// A "load more files" page is in flight.
  final bool loadingMore;

  /// A load failure key (browse errors; mutations surface via toasts).
  final String? errorKey;

  /// Current folder id (null = root).
  final String? folderId;

  /// Root-first ancestor chain (empty at root; current folder last).
  final List<DriveFolder> breadcrumb;
  final List<DriveFolder> folders;
  final List<DriveFile> files;
  final int page;
  final bool hasMore;
  final DriveSort sort;
  final StorageUsage? storage;

  bool get isRoot => folderId == null;
  bool get isEmpty => folders.isEmpty && files.isEmpty;

  /// The current folder's display name (empty at root).
  String get currentName => breadcrumb.isNotEmpty ? breadcrumb.last.name : '';

  DriveState copyWith({
    bool? loading,
    bool? loadingMore,
    String? errorKey,
    bool clearError = false,
    String? folderId,
    bool clearFolderId = false,
    List<DriveFolder>? breadcrumb,
    List<DriveFolder>? folders,
    List<DriveFile>? files,
    int? page,
    bool? hasMore,
    DriveSort? sort,
    StorageUsage? storage,
  }) => DriveState(
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    errorKey: clearError ? null : (errorKey ?? this.errorKey),
    folderId: clearFolderId ? null : (folderId ?? this.folderId),
    breadcrumb: breadcrumb ?? this.breadcrumb,
    folders: folders ?? this.folders,
    files: files ?? this.files,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    sort: sort ?? this.sort,
    storage: storage ?? this.storage,
  );

  @override
  List<Object?> get props => [
    loading,
    loadingMore,
    errorKey,
    folderId,
    breadcrumb,
    folders,
    files,
    page,
    hasMore,
    sort,
    storage,
  ];
}

/// Drives the Drive file-manager: folder navigation, listing, sorting,
/// pagination, storage, and the create/rename/move/delete mutations. Mutation
/// methods return a localization key on failure (null on success) so callers
/// toast the outcome; the cubit refreshes the current folder itself.
class DriveCubit extends Cubit<DriveState> {
  DriveCubit(this._service) : super(const DriveState());

  final DriveService _service;

  static const int _perPage = 50;

  /// Open [folderId] (null = root). Loads breadcrumb + folders + first page of
  /// files, and refreshes the storage meter.
  Future<void> open(String? folderId) async {
    emit(
      DriveState(
        loading: true,
        folderId: folderId,
        sort: state.sort,
        storage: state.storage,
      ),
    );
    try {
      final breadcrumb = folderId == null
          ? const <DriveFolder>[]
          : await _service.breadcrumb(folderId);
      final folders = await _service.folders(parentId: folderId);
      final filePage = await _service.files(
        folderId: folderId,
        page: 1,
        perPage: _perPage,
        sort: state.sort.field,
        order: state.sort.order,
      );
      emit(
        state.copyWith(
          loading: false,
          clearError: true,
          folderId: folderId,
          clearFolderId: folderId == null,
          breadcrumb: breadcrumb,
          folders: folders,
          files: filePage.files,
          page: filePage.page,
          hasMore: filePage.hasMore,
        ),
      );
      unawaited(_loadStorage());
    } on Object catch (e) {
      emit(state.copyWith(loading: false, errorKey: driveErrorKey(e)));
    }
  }

  /// Reload the current folder in place (after a mutation / pull-to-refresh).
  Future<void> refresh() => open(state.folderId);

  /// Navigate up one level (to the parent folder, or root).
  Future<void> goUp() {
    if (state.breadcrumb.length >= 2) {
      return open(state.breadcrumb[state.breadcrumb.length - 2].id);
    }
    return open(null);
  }

  /// Load the next page of files (infinite scroll).
  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.loading) return;
    emit(state.copyWith(loadingMore: true));
    try {
      final next = await _service.files(
        folderId: state.folderId,
        page: state.page + 1,
        perPage: _perPage,
        sort: state.sort.field,
        order: state.sort.order,
      );
      emit(
        state.copyWith(
          loadingMore: false,
          files: [...state.files, ...next.files],
          page: next.page,
          hasMore: next.hasMore,
        ),
      );
    } on Object {
      emit(state.copyWith(loadingMore: false));
    }
  }

  Future<void> setSort(DriveSort sort) async {
    if (sort == state.sort) return;
    emit(state.copyWith(sort: sort));
    await refresh();
  }

  Future<void> _loadStorage() async {
    try {
      emit(state.copyWith(storage: await _service.storageUsage()));
    } on Object {
      // Storage meter is best-effort; a failure just hides it.
    }
  }

  // ---- Mutations (return an error key on failure, null on success) ----------

  Future<String?> createFolder(String name) =>
      _mutate(() => _service.createFolder(name, parentId: state.folderId));

  Future<String?> renameFolder(String id, String name) =>
      _mutate(() => _service.updateFolder(id, name: name));

  Future<String?> renameFile(String id, String name) =>
      _mutate(() => _service.updateFile(id, name: name));

  Future<String?> moveFolder(String id, String? destParentId) =>
      _mutate(() => _service.updateFolder(id, parentId: destParentId));

  Future<String?> moveFile(String id, String? destParentId) =>
      _mutate(() => _service.updateFile(id, parentId: destParentId));

  Future<String?> deleteFolder(String id) =>
      _mutate(() => _service.deleteFolder(id));

  Future<String?> deleteFile(String id) =>
      _mutate(() => _service.deleteFile(id));

  /// Called after an upload completes — just refreshes the current folder.
  Future<void> onUploaded() => refresh();

  Future<String?> _mutate(Future<void> Function() op) async {
    try {
      await op();
      await refresh();
      return null;
    } on Object catch (e) {
      return driveErrorKey(e);
    }
  }
}
