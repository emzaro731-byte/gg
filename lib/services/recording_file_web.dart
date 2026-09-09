import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<String> recordingPath(String filename) async => '';

Future<Uint8List> readRecordingBytes(String path) async {
  if (path.isEmpty) {
    throw StateError('The browser did not return a recording URL.');
  }
  final response = await http.get(Uri.parse(path));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('Unable to read the browser recording (${response.statusCode}).');
  }
  return response.bodyBytes;
}

Future<void> deleteRecordingFile(String path) async {}

const recordingFileExtension = 'wav';
const recordingMimeType = 'audio/wav';
