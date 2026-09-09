import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> recordingPath(String filename) async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/$filename';
}

Future<Uint8List> readRecordingBytes(String path) => File(path).readAsBytes();

Future<void> deleteRecordingFile(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}

const recordingFileExtension = 'm4a';
const recordingMimeType = 'audio/mp4';
