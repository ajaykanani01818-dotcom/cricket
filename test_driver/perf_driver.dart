import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Runs integration_test/perf_test.dart in PROFILE mode on a real device and
/// writes one timeline summary per traced scenario to build/perf/.
///   flutter drive --profile --driver=test_driver/perf_driver.dart \
///     --target=integration_test/perf_test.dart --dart-define-from-file=env/local.json -d DEVICE_ID
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        for (final entry in data.entries) {
          final timeline = driver.Timeline.fromJson(entry.value as Map<String, dynamic>);
          final summary = driver.TimelineSummary.summarize(timeline);
          await summary.writeTimelineToFile(entry.key, pretty: true, includeSummary: true, destinationDirectory: 'build/perf');
        }
      },
    );
