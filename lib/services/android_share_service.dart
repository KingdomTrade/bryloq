import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum SharedContentKind {
  text,
  file,
}

class SharedContent {
  final SharedContentKind kind;
  final String? text;
  final String? uri;
  final String? mimeType;
  final String? fileName;

  const SharedContent({
    required this.kind,
    this.text,
    this.uri,
    this.mimeType,
    this.fileName,
  });

  factory SharedContent.fromMap(
    Map<dynamic, dynamic> map,
  ) {
    final kindValue = map['kind']?.toString();

    return SharedContent(
      kind: kindValue == 'file'
          ? SharedContentKind.file
          : SharedContentKind.text,
      text: map['text']?.toString(),
      uri: map['uri']?.toString(),
      mimeType: map['mimeType']?.toString(),
      fileName: map['fileName']?.toString(),
    );
  }
}

typedef SharedContentHandler = Future<void> Function(
  SharedContent shared,
);

class AndroidShareService {
  static const MethodChannel _channel = 
      MethodChannel('com.bryloq.app/share');
  

  SharedContentHandler? onSharedContent;
  bool _initialised = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialise() async {
    if (_initialised || !_isAndroid) {
      _initialised = true;
      return;
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedContent') {
        return;
      }

      final arguments = call.arguments;

      if (arguments is! Map) {
        return;
      }

      final handler = onSharedContent;

      if (handler == null) {
        return;
      }

      await handler(
        SharedContent.fromMap(arguments),
      );
    });

    _initialised = true;
  }

  Future<SharedContent?> getInitialShare() async {
    await initialise();

    if (!_isAndroid) {
      return null;
    }

    final result = await _channel.invokeMethod<dynamic>(
      'getInitialShare',
    );

    if (result is! Map) {
      return null;
    }

    return SharedContent.fromMap(result);
  }

  Future<Uint8List> readSharedBytes(
    String uri,
  ) async {
    await initialise();

    if (!_isAndroid) {
      throw UnsupportedError(
        'Android share files are only available on Android.',
      );
    }

    final bytes = await _channel.invokeMethod<Uint8List>(
      'readSharedUri',
      {
        'uri': uri,
      },
    );

    if (bytes == null || bytes.isEmpty) {
      throw Exception(
        'BRYLOQ could not read the shared file.',
      );
    }

    return bytes;
  }

  Future<void> dispose() async {
    if (!_isAndroid || !_initialised) {
      return;
    }

    _channel.setMethodCallHandler(null);
    _initialised = false;
  }
}
