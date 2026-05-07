import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:neiry_kit/neiry_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Static helpers for persisting [PhysiologicalStatesBaselines] to/from JSON files.
abstract final class PhysioBaselinesFileManager {
  /// Writes [baselines] as JSON to the app documents directory.
  ///
  /// The filename is `physio_baselines_<millis>.json` using the current timestamp.
  /// Returns the written [File].
  static Future<File> exportToFile(
      PhysiologicalStatesBaselines baselines) async {
    final dir = await getApplicationDocumentsDirectory();
    final millis = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/physio_baselines_$millis.json');
    await file.writeAsString(jsonEncode(baselines.toMap()));
    return file;
  }

  /// Opens a file picker filtered to `.json` files and parses the chosen file
  /// as [PhysiologicalStatesBaselines].
  ///
  /// Returns `null` when the user cancels or the file cannot be parsed.
  static Future<PhysiologicalStatesBaselines?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) return null;

    final contents = await File(path).readAsString();
    final decoded = jsonDecode(contents) as Map;
    return PhysiologicalStatesBaselines.fromMap(
        decoded.cast<Object?, Object?>());
  }
}
