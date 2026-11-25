import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Versioned PBKDF2-HMAC-SHA256 password hashing.
/// Production default: 600,000 iterations. Inject lower values only in tests.
class PasswordHasher {
  PasswordHasher({this.iterations = 600000, Random? random})
      : _random = random ?? Random.secure();

  static const int saltLength = 16;
  static const int keyLengthBits = 256;
  static const String algorithmId = 'pbkdf2-sha256-v1';
  final int iterations;
  final Random _random;

  Future<String> hash(String password) async {
    final salt = List<int>.generate(saltLength, (_) => _random.nextInt(256));
    final derived = await _derive(password, salt, iterations);
    return algorithmId + r'$' + iterations.toString() + r'$' +
        _toHex(salt) + r'$' + _toHex(derived);
  }

  Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != algorithmId) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 10000 || rounds > 1000000) return false;
    final salt = _fromHex(parts[2]);
    final expected = _fromHex(parts[3]);
    if (salt == null || salt.length != saltLength ||
        expected == null || expected.length != keyLengthBits ~/ 8) {
      return false;
    }
    final actual = await _derive(password, salt, rounds);
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected[i] ^ actual[i];
    }
    return difference == 0;
  }

  Future<List<int>> _derive(String password, List<int> salt, int rounds) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: rounds,
      bits: keyLengthBits,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return key.extractBytes();
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int>? _fromHex(String value) {
    if (value.isEmpty || value.length.isOdd ||
        !RegExp(r'^[0-9a-f]+
    return [
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ];
  }
}
).hasMatch(value)) {
      return null;
    }
    return [
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ];
  }
}
