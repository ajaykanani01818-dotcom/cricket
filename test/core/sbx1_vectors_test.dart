import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crickbex/core/api/sbx1.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List hex(String h) => Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
String toHex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final v = jsonDecode(File('../docs/sbx1_vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final secret = hex(v['secretHex']), nonce = hex(v['nonceHex']);

  test('derived keys match', () async {
    final k = await Sbx1.deriveKeys(secret, nonce);
    final d = v['derived'] as Map;
    expect(toHex(k.enc), d['encKeyHex']);
    expect(toHex(k.mac), d['macKeyHex']);
    expect(toHex(k.res), d['resKeyHex']);
    expect(toHex(k.resMac), d['resMacKeyHex']);
  });

  test('request envelope matches byte for byte', () async {
    final params = Map<String, Object?>.from(v['params']);
    expect(jsonEncode({'p': params}), v['plaintextRequest']);
    final r = await Sbx1.buildRequest(
        secret: secret, token: v['token'], params: params, ts: v['ts'], nonce: nonce, iv: hex(v['ivHex']));
    expect(r.toJson(), v['request']);
  });

  test('response envelope parses and rebuilds identically', () async {
    final payload = await Sbx1.parseResponse(secret: secret, nonceB64: Sbx1.b64u(nonce), body: v['response']);
    expect(payload, v['responsePayload']);
    final k = await Sbx1.deriveKeys(secret, nonce);
    final rebuilt = await Sbx1.buildResponse(keys: k, nonceB64: Sbx1.b64u(nonce), payload: v['responsePayload'], iv: hex(v['resIvHex']));
    expect(rebuilt, v['response']);
  });

  test('tampered response is rejected', () async {
    final resp = Map<String, dynamic>.from(v['response']);
    final n = Sbx1.b64u(nonce);
    resp['d'] = 'A${(resp['d'] as String).substring(1)}';
    expect(Sbx1.parseResponse(secret: secret, nonceB64: n, body: resp), throwsA(isA<Sbx1Exception>()));
    expect(Sbx1.parseResponse(secret: secret, nonceB64: n, body: 'x'), throwsA(isA<Sbx1Exception>()));
  });
}
