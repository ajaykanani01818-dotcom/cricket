import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// SBX1 envelope (see docs/SECURITY_PROTOCOL.md). Wire-identical to
/// livescore-postdata/src/security/sbx1.js.
class Sbx1Keys {
  const Sbx1Keys(this.enc, this.mac, this.res, this.resMac);
  final List<int> enc, mac, res, resMac;
}

class Sbx1Request {
  const Sbx1Request({
    required this.t,
    required this.n,
    required this.d,
    required this.s,
  });
  final int t;
  final String n, d, s;

  Map<String, Object> toJson() => {'v': 1, 't': t, 'n': n, 'd': d, 's': s};
}

class Sbx1Exception implements Exception {
  const Sbx1Exception(this.reason);
  final String reason;
  @override
  String toString() => 'Sbx1Exception($reason)';
}

class Sbx1 {
  Sbx1._();

  static final _hmac = Hmac.sha256();
  static final _gcm = AesGcm.with256bits();

  static String b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  static Uint8List unb64u(String s) {
    final pad = (4 - s.length % 4) % 4;
    return Uint8List.fromList(base64Url.decode(s + '=' * pad));
  }

  static Uint8List randomBytes(int n, [Random? rng]) {
    final r = rng ?? Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  static Future<List<int>> _hkdf(
    List<int> secret,
    List<int> salt,
    String info,
  ) async {
    final k = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
      info: utf8.encode(info),
    );
    return k.extractBytes();
  }

  static Future<Sbx1Keys> deriveKeys(List<int> secret, List<int> nonce) async =>
      Sbx1Keys(
        await _hkdf(secret, nonce, 'sbx1|enc'),
        await _hkdf(secret, nonce, 'sbx1|mac'),
        await _hkdf(secret, nonce, 'sbx1|res'),
        await _hkdf(secret, nonce, 'sbx1|resmac'),
      );

  static Future<String> hmac(List<int> key, String str) async => b64u(
    (await _hmac.calculateMac(
      utf8.encode(str),
      secretKey: SecretKey(key),
    )).bytes,
  );

  static bool constEq(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    if (x.length != y.length) return false;
    var r = 0;
    for (var i = 0; i < x.length; i++) {
      r |= x[i] ^ y[i];
    }
    return r == 0;
  }

  /// base64url(iv(12) | ciphertext | tag(16))
  static Future<String> seal(
    List<int> key,
    String plaintext,
    String aad,
    List<int> iv,
  ) async {
    final box = await _gcm.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(key),
      nonce: iv,
      aad: utf8.encode(aad),
    );
    return b64u([...iv, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<String> open(List<int> key, String d, String aad) async {
    final raw = unb64u(d);
    if (raw.length < 28) throw const Sbx1Exception('short');
    final box = SecretBox(
      raw.sublist(12, raw.length - 16),
      nonce: raw.sublist(0, 12),
      mac: Mac(raw.sublist(raw.length - 16)),
    );
    final plain = await _gcm.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: utf8.encode(aad),
    );
    return utf8.decode(plain);
  }

  static Future<Sbx1Request> buildRequest({
    required List<int> secret,
    required String token,
    required Map<String, Object?> params,
    required int ts,
    required List<int> nonce,
    required List<int> iv,
  }) async {
    final k = await deriveKeys(secret, nonce);
    final n = b64u(nonce);
    final d = await seal(k.enc, jsonEncode({'p': params}), '$token|$ts|$n', iv);
    final s = await hmac(k.mac, '1|$token|$ts|$n|$d');
    return Sbx1Request(t: ts, n: n, d: d, s: s);
  }

  /// Verifies the MAC and decrypts a response envelope. Returns `{s, b}`.
  /// Throws [Sbx1Exception] on any failure.
  static Future<Map<String, dynamic>> parseResponse({
    required List<int> secret,
    required String nonceB64,
    required Object? body,
  }) async {
    try {
      if (body is! Map ||
          body['v'] != 1 ||
          body['d'] is! String ||
          body['s'] is! String) {
        throw const Sbx1Exception('shape');
      }
      final k = await deriveKeys(secret, unb64u(nonceB64));
      final d = body['d'] as String;
      if (!constEq(
        await hmac(k.resMac, '1|res|$nonceB64|$d'),
        body['s'] as String,
      )) {
        throw const Sbx1Exception('mac');
      }
      final out = jsonDecode(await open(k.res, d, 'res|$nonceB64'));
      if (out is! Map<String, dynamic>) throw const Sbx1Exception('payload');
      return out;
    } on Sbx1Exception {
      rethrow;
    } catch (_) {
      throw const Sbx1Exception('decrypt');
    }
  }

  /// Server side (used by tests' in-process server).
  static Future<({Map<String, dynamic> params, String nonceB64, Sbx1Keys keys})>
  parseRequest({
    required List<int> secret,
    required String token,
    required Map<String, dynamic> body,
  }) async {
    final n = body['n'] as String, d = body['d'] as String, t = body['t'];
    final nonce = unb64u(n);
    final k = await deriveKeys(secret, nonce);
    if (!constEq(await hmac(k.mac, '1|$token|$t|$n|$d'), body['s'] as String)) {
      throw const Sbx1Exception('mac');
    }
    final plain =
        jsonDecode(await open(k.enc, d, '$token|$t|$n'))
            as Map<String, dynamic>;
    return (
      params: (plain['p'] as Map?)?.cast<String, dynamic>() ?? {},
      nonceB64: n,
      keys: k,
    );
  }

  static Future<Map<String, Object>> buildResponse({
    required Sbx1Keys keys,
    required String nonceB64,
    required Object payload,
    List<int>? iv,
  }) async {
    final d = await seal(
      keys.res,
      jsonEncode(payload),
      'res|$nonceB64',
      iv ?? randomBytes(12),
    );
    return {'v': 1, 'd': d, 's': await hmac(keys.resMac, '1|res|$nonceB64|$d')};
  }
}
