import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionSecretStore {
  Future<void> write(String value);
  Future<String?> read();
  Future<void> delete();
}

/// Android secure-storage adapter (backed by the platform keystore).
class FlutterSessionSecretStore implements SessionSecretStore {
  FlutterSessionSecretStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _key = 'advanced_assistant.session_token';
  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}
