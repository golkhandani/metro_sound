import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver for the automated QA sweep. Writes each screenshot the test captures
/// (via `binding.takeScreenshot(name)`) to `qa_artifacts/<name>.png`.
Future<void> main() async {
  final dir = Directory('qa_artifacts');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes,
        [Map<String, Object?>? args]) async {
      File('qa_artifacts/$name.png').writeAsBytesSync(bytes);
      stdout.writeln('QA-SHOT $name (${bytes.length} bytes)');
      return true;
    },
  );
}
