import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How far the device's hinge is open (iPhone Duo; unknown everywhere else).
enum HingeStatus { unknown, closed, partial, full }

/// The hinge and the fold, as iOS reports them (DevicePosturePlugin in
/// ios/Runner/AppDelegate.swift).
@immutable
class DevicePosture {
  const DevicePosture({
    this.status = HingeStatus.unknown,
    this.folds = const [],
  });

  static const none = DevicePosture();

  final HingeStatus status;

  /// The creases to keep controls off, in the window's logical pixels: only
  /// while the device is half open (like a book or a tent); empty when it is
  /// flat, closed, or not a foldable at all.
  final List<Rect> folds;

  /// The fold that splits the screen into a left and a right pane.
  Rect? get verticalFold =>
      folds.where((r) => r.height > r.width).firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is DevicePosture &&
      other.status == status &&
      listEquals(other.folds, folds);

  @override
  int get hashCode => Object.hash(status, Object.hashAll(folds));
}

/// The device's posture, kept current. Listens only on iOS (the only platform
/// with a hinge API here); on every other platform it stays [DevicePosture.none],
/// so nothing that reads it changes there.
class DevicePostureService extends ValueNotifier<DevicePosture>
    with WidgetsBindingObserver {
  DevicePostureService._() : super(DevicePosture.none);

  static final DevicePostureService instance = DevicePostureService._();

  static const _methods = MethodChannel('app.bishare/posture');
  static const _events = EventChannel('app.bishare/posture/events');

  StreamSubscription<dynamic>? _sub;
  bool _started = false;

  /// Start listening (once). A no-op off iOS, in tests and on an older build
  /// without the plugin.
  void start() {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      _sub = _events.receiveBroadcastStream().listen(
        _take,
        onError: (Object _) {},
      );
    } on MissingPluginException {
      _sub = null;
    }
  }

  /// The fold's rect turns with the screen; ask again after a resize.
  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  Future<void> refresh() async {
    try {
      _take(await _methods.invokeMethod<Object?>('state'));
    } on MissingPluginException {
      // An older build: no hinge, nothing changes.
    } on PlatformException {
      // Same.
    }
  }

  void _take(Object? raw) {
    if (raw is! Map) return;
    final status = switch (raw['status']) {
      'closed' => HingeStatus.closed,
      'partial' => HingeStatus.partial,
      'full' => HingeStatus.full,
      _ => HingeStatus.unknown,
    };
    final folds = <Rect>[
      for (final f in (raw['folds'] as List?) ?? const [])
        if (f is List && f.length == 4)
          Rect.fromLTWH(
            (f[0] as num).toDouble(),
            (f[1] as num).toDouble(),
            (f[2] as num).toDouble(),
            (f[3] as num).toDouble(),
          ),
    ];
    value = DevicePosture(status: status, folds: folds);
  }

  @override
  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Rebuilds [builder] when the posture changes.
class DevicePostureBuilder extends StatelessWidget {
  const DevicePostureBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, DevicePosture posture) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DevicePosture>(
    valueListenable: DevicePostureService.instance,
    builder: (context, posture, _) => builder(context, posture),
  );
}

/// [left] and [right] on either side of the fold of a half-open iPhone Duo,
/// nothing on the crease. Without a fold (flat, closed, any other device) it
/// shows [flat] instead, so layouts elsewhere stay exactly as they were.
class FoldSplit extends StatefulWidget {
  const FoldSplit({
    super.key,
    required this.left,
    required this.right,
    required this.flat,
  });

  final Widget left;
  final Widget right;
  final Widget flat;

  @override
  State<FoldSplit> createState() => _FoldSplitState();
}

class _FoldSplitState extends State<FoldSplit> {
  /// The fold in this widget's own coordinates, after the first layout.
  Rect? _local;

  void _measure(Rect? fold) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      Rect? local;
      if (fold != null && box != null && box.hasSize) {
        final origin = box.localToGlobal(Offset.zero);
        final shifted = fold.shift(-origin);
        // Only a fold that actually crosses this widget splits it.
        if (shifted.left > 0 && shifted.right < box.size.width) local = shifted;
      }
      if (local != _local) setState(() => _local = local);
    });
  }

  @override
  Widget build(BuildContext context) => DevicePostureBuilder(
    builder: (context, posture) {
      _measure(posture.verticalFold);
      final fold = _local;
      if (fold == null) return widget.flat;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: fold.left, child: widget.left),
          SizedBox(width: fold.width),
          Expanded(child: widget.right),
        ],
      );
    },
  );
}

/// [child] kept off the fold of a half-open iPhone Duo: laid out in the wider
/// side when a fold crosses it. Without a fold (flat, closed, any other
/// device) it is [child] itself, untouched.
class FoldAvoid extends StatefulWidget {
  const FoldAvoid({super.key, required this.child});

  final Widget child;

  @override
  State<FoldAvoid> createState() => _FoldAvoidState();
}

class _FoldAvoidState extends State<FoldAvoid> {
  Rect? _local;
  double _width = 0;

  void _measure(Rect? fold) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      Rect? local;
      var width = 0.0;
      if (fold != null && box != null && box.hasSize) {
        final shifted = fold.shift(-box.localToGlobal(Offset.zero));
        width = box.size.width;
        if (shifted.left > 0 && shifted.right < width) local = shifted;
      }
      if (local != _local || width != _width) {
        setState(() {
          _local = local;
          _width = width;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => DevicePostureBuilder(
    builder: (context, posture) {
      // Without a fold anywhere, the child alone: no extra layer, no work.
      if (posture.verticalFold == null && _local == null) return widget.child;
      _measure(posture.verticalFold);
      final fold = _local;
      if (fold == null) return widget.child;
      final rightSide = _width - fold.right >= fold.left;
      return Padding(
        padding: rightSide
            ? EdgeInsets.only(left: fold.right)
            : EdgeInsets.only(right: _width - fold.left),
        child: widget.child,
      );
    },
  );
}

