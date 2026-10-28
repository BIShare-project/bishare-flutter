import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Driver for integration_test/perf_test.dart (redesign-plan.md "How it is
/// measured"): one timeline summary per scenario in build/perf/, and one
/// line each on the console (build and raster p90, worst frame, missed),
/// plus the engine's FrameTiming line per scenario (the more complete one).
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    final out = Directory('build/perf')..createSync(recursive: true);
    final lines = <String>[];
    for (final MapEntry(:key, :value) in data.entries) {
      // The engine's own frame times, already one line per scenario.
      if (key == 'engine') {
        lines.addAll((value as Map).values.map((v) => 'engine $v'));
        continue;
      }
      final timeline = driver.Timeline.fromJson(value as Map<String, dynamic>);
      final summary = driver.TimelineSummary.summarize(timeline);
      await summary.writeTimelineToFile(key, destinationDirectory: out.path);
      final j = summary.summaryJson;
      lines.add(
        '$key: build p90 ${j['90th_percentile_frame_build_time_millis']} ms, '
        'raster p90 ${j['90th_percentile_frame_rasterizer_time_millis']} ms, '
        'worst build ${j['worst_frame_build_time_millis']} ms, '
        'worst raster ${j['worst_frame_rasterizer_time_millis']} ms, '
        'missed build ${j['missed_frame_build_budget_count']}, '
        'missed raster ${j['missed_frame_rasterizer_budget_count']}, '
        'frames ${j['frame_count']}',
      );
    }
    File('${out.path}/summary.txt').writeAsStringSync('${lines.join('\n')}\n');
    stdout.writeln(const JsonEncoder.withIndent(' ').convert(lines));
  },
);
