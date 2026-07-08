import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../remote/data/cloud_transfer_service.dart' show CloudDownloadException;
import '../data/local_room_service.dart';
import '../data/room_service.dart';
import '../data/room_thumbnail.dart';
import '../domain/room_models.dart';

enum RoomStatus { lobby, connecting, inRoom, error }

/// Immutable room screen state.
class RoomState {
  const RoomState({
    this.status = RoomStatus.lobby,
    this.session,
    this.members = const [],
    this.files = const [],
    this.uploadingLabel,
    this.connectingLabel = 'Connecting…',
    this.error = '',
  });

  final RoomStatus status;
  final RoomSession? session;
  final List<RoomMember> members;
  final List<RoomFile> files;

  /// Non-null while someone is uploading (e.g. "Alex · photo.jpg").
  final String? uploadingLabel;

  /// What we're doing during [RoomStatus.connecting] (e.g. "Looking for a
  /// local room…", "Joining room…").
  final String connectingLabel;
  final String error;

  bool get isHost => session?.isHost ?? false;

  RoomState copyWith({
    RoomStatus? status,
    RoomSession? session,
    List<RoomMember>? members,
    List<RoomFile>? files,
    String? uploadingLabel,
    bool clearUploading = false,
    String? connectingLabel,
    String? error,
  }) => RoomState(
    status: status ?? this.status,
    session: session ?? this.session,
    members: members ?? this.members,
    files: files ?? this.files,
    uploadingLabel: clearUploading ? null : (uploadingLabel ?? this.uploadingLabel),
    connectingLabel: connectingLabel ?? this.connectingLabel,
    error: error ?? this.error,
  );
}

/// Drives the Rooms screen: create/join a remote room, keep members + shared
/// files live over the WebSocket, add + download files.
class RoomCubit extends Cubit<RoomState> {
  RoomCubit(this._remote, this._local) : super(const RoomState()) {
    _remoteSub = _remote.events.listen(_onEvent);
    _localSub = _local.events.listen(_onEvent);
  }

  final RoomService _remote;
  final LocalRoomService _local;
  late final StreamSubscription<RoomEvent> _remoteSub;
  late final StreamSubscription<RoomEvent> _localSub;

  /// Whether the current room is a local (Bonjour) room vs. a remote (relay) one.
  bool _isLocal = false;

  /// Create a room. [local] = same-Wi-Fi Bonjour room (no internet); otherwise
  /// a relay room reachable from any network.
  Future<void> createRoom({bool local = false}) async {
    emit(state.copyWith(
      status: RoomStatus.connecting,
      connectingLabel: local ? 'Creating a local room…' : 'Creating a room…',
    ));
    try {
      _isLocal = local;
      final session =
          local ? await _local.createLocal() : await _remote.createRemote();
      emit(
        RoomState(
          status: RoomStatus.inRoom,
          session: session,
          members: const [],
          files: const [],
        ),
      );
    } on Object {
      emit(
        state.copyWith(
          status: RoomStatus.error,
          error: 'Could not create the room. Please try again.',
        ),
      );
    }
  }

  /// Join by code — tries a local Bonjour room first (same Wi-Fi), then falls
  /// back to the relay (mirrors native local-first behaviour).
  Future<void> joinRoom(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.length < 4) return;
    emit(state.copyWith(
      status: RoomStatus.connecting,
      connectingLabel: 'Looking for a local room',
    ));
    try {
      // Try a local Bonjour room first; any local failure must NOT block the
      // remote fallback, so swallow it and treat as "no local room".
      (RoomSession, List<RoomMember>, List<RoomFile>)? localResult;
      try {
        localResult =
            await _local.joinLocal(trimmed, timeout: const Duration(seconds: 4));
      } on Object {
        localResult = null;
      }
      if (localResult != null) {
        _isLocal = true;
        final (session, members, files) = localResult;
        emit(
          RoomState(
            status: RoomStatus.inRoom,
            session: session,
            members: members,
            files: files,
          ),
        );
        return;
      }
      _isLocal = false;
      emit(state.copyWith(connectingLabel: 'Joining room'));
      final (session, members, files) = await _remote.joinRemote(trimmed);
      emit(
        RoomState(
          status: RoomStatus.inRoom,
          session: session,
          members: members,
          files: files,
        ),
      );
    } on DioException catch (e) {
      final notFound = e.response?.statusCode == 404;
      emit(
        state.copyWith(
          status: RoomStatus.error,
          error: notFound ? 'No room with that code.' : 'Could not join the room.',
        ),
      );
    } on Object {
      emit(
        state.copyWith(
          status: RoomStatus.error,
          error: 'Could not join the room.',
        ),
      );
    }
  }

  void _onEvent(RoomEvent event) {
    if (state.status != RoomStatus.inRoom) return;
    switch (event) {
      case RoomSyncEvent(:final members, :final files):
        emit(state.copyWith(members: members, files: files));
      case RoomMemberJoinedEvent(:final member):
        if (state.members.any((m) => m.fingerprint == member.fingerprint)) return;
        emit(state.copyWith(members: [...state.members, member]));
      case RoomMemberLeftEvent(:final fingerprint):
        emit(
          state.copyWith(
            members:
                state.members.where((m) => m.fingerprint != fingerprint).toList(),
          ),
        );
      case RoomFileAddedEvent(:final file):
        if (state.files.any((f) => f.id == file.id)) return;
        emit(
          state.copyWith(files: [file, ...state.files], clearUploading: true),
        );
      case RoomUploadStartEvent(:final alias, :final fileName):
        emit(state.copyWith(uploadingLabel: '$alias · $fileName'));
      case RoomUploadDoneEvent():
        emit(state.copyWith(clearUploading: true));
      case RoomClosedEvent():
        emit(const RoomState(error: 'The host closed the room.'));
    }
  }

  /// Upload a local file into the room (with an image/video thumbnail so peers
  /// see a preview in the list).
  Future<void> addFile(
    File file, {
    required String name,
    required String mime,
  }) async {
    final code = state.session?.code;
    if (code == null) return;
    final thumb = await generateRoomThumbnail(file.path, mime);
    try {
      if (_isLocal) {
        await _local.addFile(file, name: name, mime: mime, thumbnailBase64: thumb);
      } else {
        await _remote.uploadFile(
          code,
          file,
          fileName: name,
          mimeType: mime,
          thumbnailBase64: thumb,
        );
      }
    } on Object {
      // Clear any stuck "uploading…" indicator, then let the UI report it.
      emit(state.copyWith(clearUploading: true));
      rethrow;
    }
  }

  /// Download a shared file to the save directory (records it in the Inbox).
  Future<File> download(RoomFile file) {
    final code = state.session?.code;
    if (code == null) throw const CloudDownloadException('You left the room.');
    return _isLocal
        ? _local.downloadFile(file)
        : _remote.downloadFile(code, file);
  }

  /// Download a shared file to a temp location for previewing (no Inbox record).
  Future<File> downloadTemp(RoomFile file) {
    final code = state.session?.code;
    if (code == null) throw const CloudDownloadException('You left the room.');
    return _isLocal
        ? _local.downloadToTemp(file)
        : _remote.downloadToTemp(code, file);
  }

  Future<void> leave() async {
    final s = state.session;
    if (s != null) {
      if (_isLocal) {
        await _local.leave();
      } else if (s.isHost && s.hostToken != null) {
        await _remote.close(s.code, s.hostToken!);
      } else {
        await _remote.leave(s.code);
      }
    }
    emit(const RoomState());
  }

  @override
  Future<void> close() {
    _remoteSub.cancel();
    _localSub.cancel();
    return super.close();
  }
}
