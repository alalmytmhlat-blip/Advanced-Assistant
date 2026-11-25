import 'package:pdfrx/pdfrx.dart';
class PdfRuntime {
  PdfRuntime._();
  static bool _initialized = false;
  static Future<void> initialize() async {
    if (_initialized) return;
    await pdfrxFlutterInitialize();
    _initialized = true;
  }
}
