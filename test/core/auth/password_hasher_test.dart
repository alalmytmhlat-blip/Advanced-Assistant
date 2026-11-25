import 'package:flutter_test/flutter_test.dart';
import 'package:advanced_assistant/core/auth/password_hasher.dart';

void main() {
  test('hashes with unique salt and verifies the correct password', () async {
    final hasher = PasswordHasher(iterations: 10000);
    final first = await hasher.hash('Strong-password-123');
    final second = await hasher.hash('Strong-password-123');
    expect(first, isNot(second));
    expect(await hasher.verify('Strong-password-123', first), isTrue);
    expect(await hasher.verify('wrong-password', first), isFalse);
    expect(await hasher.verify('Strong-password-123', 'plain-text'), isFalse);
  });

  test('rejects malformed and excessive work-factor encodings', () async {
    final hasher = PasswordHasher(iterations: 10000);
    expect(await hasher.verify('password', 'pbkdf2-sha256-v1$99999999$aa$bb'), isFalse);
    expect(await hasher.verify('password', 'unknown$10000$aa$bb'), isFalse);
  });
}
