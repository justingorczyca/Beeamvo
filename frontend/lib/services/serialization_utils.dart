import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

/// Heavy encoding helpers that run on a worker isolate so the UI isolate is not
/// blocked by large audio payloads.

String _encodeBase64(List<int> bytes) => base64Encode(bytes);

Future<String> encodeBase64Async(Uint8List bytes) =>
    Isolate.run(() => _encodeBase64(bytes));

Uint8List _encodeJsonBytes(Object object) =>
    Uint8List.fromList(utf8.encode(jsonEncode(object)));

Future<Uint8List> encodeJsonAsync(Object object) =>
    Isolate.run(() => _encodeJsonBytes(object));
