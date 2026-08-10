import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../remote/data/cloud_transfer_service.dart' show CloudDownloadException;
import '../data/local_room_service.dart';
import '../data/room_service.dart';
import '../data/room_thumbnail.dart';
import '../data/webrtc_room_service.dart';
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
  RoomCubit(this._remote, this._local, this._webrtc) : super(const RoomState()) {
    _remoteSub = _remote.events.listen(_onEvent);
    _localSub = _local.events.listen(_onEvent);
    _webrtcSub = _webrtc.events.listen(_onEvent);
  }

  final RoomService _remote;
  final LocalRoomService _local;
  final WebrtcRoomService _webrtc;
  late final StreamSubscription<RoomEvent> _remoteSub;
  late final StreamSubscription<RoomEvent> _localSub;
  late final StreamSubscription<RoomEvent> _webrtcSub;

  /// Which transport backs the current room: Bonjour (local), WebRTC P2P
  /// (a browser-hosted local room), or the relay (remote). Mutually exclusive.
  bool _isLocal = false;
  bool _isWebrtc = false;

  /// Create a room. [local] = same-Wi-Fi Bonjour room (no internet); otherwise
  /// a relay room reachable from any network.
  Future<void> createRoom({bool local = false}) async {
    emit(state.copyWith(
      status: RoomStatus.connecting,
      connectingLabel: local
          ? 'room.connecting_create_local'.tr()
          : 'room.connecting_create_remote'.tr(),
    ));
    // Yield one turn so the connecting spinner actually paints before we touch
    // Bonjour / the relay — otherwise the synchronous run-up plus first-use
    // native hitch can make the lobby look frozen until the room appears.
    await Future<void>.delayed(Duration.zero);
    try {
      _isLocal = local;
      _isWebrtc = false;
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
          error: 'room.error_create'.tr(),
        ),
      );
    }
  }

  /// Join by code. Local Bonjour rooms take priority (same-Wi-Fi, private),
  /// but we race local discovery against the relay join instead of waiting out
  /// the full local timeout first: a room code lives in exactly one realm (a
  /// host makes EITHER a local OR a remote room), so the realm that doesn't
  /// have the code always fails cleanly and the other wins. This keeps
  /// local-first behaviour while a remote-only code no longer sits on the
  /// "looking for a local room" spinner for the whole discovery window.
  Future<void> joinRoom(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.length < 4) return;
    emit(state.copyWith(
      status: RoomStatus.connecting,
      connectingLabel: 'room.connecting_finding'.tr(),
    ));
    // Yield one turn so the spinner paints before discovery / the relay call.
    await Future<void>.delayed(Duration.zero);

    final done = Completer<void>();
    var localMissed = false;
    var webrtcMissed = false;
    Object? remoteError;

    // Only surface an error once ALL THREE realms (Bonjour, WebRTC P2P, relay)
    // have given up; prefer the remote error message (a genuine local-only room
    // fails remote with 404, and a genuine remote room is what the user most
    // likely meant).
    void failIfBothDone() {
      if (done.isCompleted) return;
      if (localMissed && webrtcMissed && remoteError != null) {
        done.completeError(remoteError!);
      }
    }

    // Local-first: a resolved local room wins immediately.
    unawaited(
      _local
          .joinLocal(trimmed, timeout: const Duration(seconds: 4))
          .then((local) {
        if (done.isCompleted) return;
        if (local != null) {
          _isLocal = true;
          _isWebrtc = false;
          final (session, members, files) = local;
          emit(
            RoomState(
              status: RoomStatus.inRoom,
              session: session,
              members: members,
              files: files,
            ),
          );
          done.complete();
        } else {
          localMissed = true;
          failIfBothDone();
        }
      }).catchError((Object _) {
        // joinLocal is self-guarding and shouldn't throw; treat any escape as
        // "no local room" so the remote result can still win.
        if (done.isCompleted) return;
        localMissed = true;
        failIfBothDone();
      }),
    );

    // Remote runs concurrently so a remote-only code resolves as fast as the
    // relay answers rather than after the local discovery timeout.
    unawaited(
      _remote.joinRemote(trimmed).then((remote) {
        if (done.isCompleted) return;
        _isLocal = false;
        _isWebrtc = false;
        final (session, members, files) = remote;
        emit(
          RoomState(
            status: RoomStatus.inRoom,
            session: session,
            members: members,
            files: files,
          ),
        );
        done.complete();
      }).catchError((Object e) {
        if (done.isCompleted) return;
        remoteError = e;
        failIfBothDone();
      }),
    );

    // WebRTC P2P: if the code is a browser-hosted local room (no Bonjour host on
    // the LAN, no relay room), signaling finds a peer and this wins. Runs
    // concurrently; drops its signaling if another realm resolves first.
    unawaited(
      _webrtc.joinWebrtc(trimmed, timeout: const Duration(seconds: 4)).then((r) {
        if (done.isCompleted) {
          if (r != null) unawaited(_webrtc.leave());
          return;
        }
        if (r != null) {
          _isLocal = false;
          _isWebrtc = true;
          final (session, members, files) = r;
          emit(
            RoomState(
              status: RoomStatus.inRoom,
              session: session,
              members: members,
              files: files,
            ),
          );
          done.complete();
        } else {
          webrtcMissed = true;
          failIfBothDone();
        }
      }).catchError((Object _) {
        if (done.isCompleted) return;
        webrtcMissed = true;
        failIfBothDone();
      }),
    );

    try {
      await done.future;
    } on DioException catch (e) {
      final notFound = e.response?.statusCode == 404;
      emit(
        state.copyWith(
          status: RoomStatus.error,
          error: notFound
              ? 'room.error_not_found'.tr()
              : 'room.error_join'.tr(),
        ),
      );
    } on Object {
      emit(
        state.copyWith(
          status: RoomStatus.error,
          error: 'room.error_join'.tr(),
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
      } else if (_isWebrtc) {
        await _webrtc.addFile(file, name: name, mime: mime);
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
    if (_isLocal) return _local.downloadFile(file);
    if (_isWebrtc) return _webrtc.downloadFile(file);
    return _remote.downloadFile(code, file);
  }

  /// Download a shared file to a temp location for previewing (no Inbox record).
  Future<File> downloadTemp(RoomFile file) {
    final code = state.session?.code;
    if (code == null) throw const CloudDownloadException('You left the room.');
    if (_isLocal) return _local.downloadToTemp(file);
    if (_isWebrtc) return _webrtc.downloadToTemp(file);
    return _remote.downloadToTemp(code, file);
  }

  Future<void> leave() async {
    final s = state.session;
    if (s != null) {
      if (_isLocal) {
        await _local.leave();
      } else if (_isWebrtc) {
        await _webrtc.leave();
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
    _webrtcSub.cancel();
    return super.close();
  }
}
