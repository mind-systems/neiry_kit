import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:neiry_kit/neiry_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Static helpers for persisting [IndividualNfbData] to/from JSON files.
abstract final class CalibrationFileManager {
  /// Writes [data] as JSON to the app documents directory.
  ///
  /// The filename is `calibration_<millis>.json` using the current timestamp.
  /// Returns the written [File], or `null` if an error occurs.
  static Future<File?> exportToFile(IndividualNfbData data) async {
    final dir = await getApplicationDocumentsDirectory();
    final millis = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/calibration_$millis.json');
    await file.writeAsString(jsonEncode(data.toMap()));
    return file;
  }

  /// Opens a file picker filtered to `.json` files and parses the chosen file
  /// as [IndividualNfbData].
  ///
  /// Returns `null` when the user cancels or the file cannot be parsed.
  static Future<IndividualNfbData?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) return null;

    final contents = await File(path).readAsString();
    final decoded = jsonDecode(contents) as Map;
    return IndividualNfbData.fromMap(decoded.cast<Object?, Object?>());
  }
}
