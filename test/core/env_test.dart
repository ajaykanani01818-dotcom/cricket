import 'dart:convert';
import 'dart:typed_data';

import 'package:crickbex/core/config/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final secret = Uint8List.fromList(List.generate(32, (i) => i * 7 + 1));
  final mask = Uint8List.fromList([0xA5, 0x3C, 0x99]);

  test('plain secret is decoded', () {
    expect(SecretFragments.resolve(secret: base64.encode(secret)), secret);
  });

  test('split fragments reassemble with the mask (3 and 4 parts)', () {
    for (final n in [3, 4]) {
      final frags = SecretFragments.split(secret, mask, n);
      expect(frags.length, n);
      expect(frags.first, isNot(base64.encode(secret.sublist(0, 11))));
      expect(SecretFragments.resolve(fragments: [...frags, '', ''].take(4).toList(), mask: base64.encode(mask)), secret);
    }
  });

  test('wrong mask / missing mask / bad length / garbage give null', () {
    final frags = SecretFragments.split(secret, mask, 3);
    expect(SecretFragments.resolve(fragments: frags, mask: base64.encode([1, 2, 3])), isNot(secret));
    expect(SecretFragments.resolve(fragments: frags), isNull);
    expect(SecretFragments.resolve(secret: base64.encode([1, 2, 3])), isNull);
    expect(SecretFragments.resolve(secret: '!!!'), isNull);
    expect(SecretFragments.resolve(), isNull);
  });

  test('unconfigured Env reports not configured', () {
    expect(Env.isConfigured, isFalse);
  });
}
