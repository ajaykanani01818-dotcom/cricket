import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/api/route_map.g.dart';
import 'package:crickbex/core/api/sbx1.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/sbx1_server.dart';

const base = 'http://test/api/x';

ApiClient client(http.Client mock,
        {Duration timeout = const Duration(seconds: 5), List<int>? secret, DateTime Function()? clock}) =>
    ApiClient(
        client: mock,
        baseUrl: base,
        secret: secret ?? kTestSecret,
        timeout: timeout,
        clock: clock,
        retryDelays: const [Duration.zero, Duration.zero]);

({int status, Object? body}) ok([Object? data]) => (status: 200, body: {'message': 'ok', 'data': data ?? []});

void main() {
  test('POSTs to the opaque token; no plaintext params or route leak in the raw request', () async {
    late http.Request seen;
    late Map<String, dynamic> got;
    final c = client(sbx1Server((t, p) {
      got = p;
      return ok();
    }, onRaw: (r) => seen = r));
    await c.call(RouteMap.matchLiveById, {'matchId': 'abc123SECRETid', 'page': 2, 'status': null});
    expect(seen.method, 'POST');
    expect(seen.url.toString(), '$base/${RouteMap.matchLiveById}');
    expect(seen.headers['x-kid'], '1');
    expect(seen.body, isNot(contains('abc123SECRETid')));
    expect(seen.body, isNot(contains('matchId')));
    expect(seen.body, isNot(contains('live')));
    expect((jsonDecode(seen.body) as Map).keys.toSet(), {'v', 't', 'n', 'd', 's'});
    expect(got, {'matchId': 'abc123SECRETid', 'page': 2});
  });

  test('every request uses a fresh nonce', () async {
    final ns = <String>{};
    final c = client(sbx1Server((t, p) => ok(), onRaw: (r) => ns.add(jsonDecode(r.body)['n'] as String)));
    for (var i = 0; i < 5; i++) {
      await c.call(RouteMap.matchLive);
    }
    expect(ns.length, 5);
  });

  group('in-flight sharing', () {
    test('identical concurrent calls share one request; different params do not', () async {
      var hits = 0;
      final gate = Completer<void>();
      final c = client(sbx1Server((t, p) {
        hits++;
        return ok();
      }, onRaw: (_) {}));
      // The first call is still pending when the others start.
      final a = c.call(RouteMap.matchLive);
      final b = c.call(RouteMap.matchLive);
      final x = c.call(RouteMap.matchLiveById, {'matchId': 'A'});
      final y = c.call(RouteMap.matchLiveById, {'matchId': 'B'});
      final z = c.call(RouteMap.matchLiveById, {'matchId': 'A', 'page': null}); // null params are ignored
      expect(identical(a, b), isTrue);
      expect(identical(x, z), isTrue);
      expect(identical(x, y), isFalse);
      gate.complete();
      await Future.wait([a, b, x, y, z]);
      expect(hits, 3, reason: 'matchLive once, matchLiveById A once, B once');
    });

    test('after completion (success or failure) the next call goes out again', () async {
      var hits = 0;
      var fail = true;
      final c = client(sbx1Server((t, p) {
        hits++;
        return fail ? (status: 404, body: {'message': 'nope'}) : ok();
      }));
      await expectLater(c.call(RouteMap.matchLive), throwsA(isA<ApiException>()));
      expect(hits, 1);
      fail = false;
      await c.call(RouteMap.matchLive);
      expect(hits, 2, reason: 'a failed call is never cached or shared later');
      await c.call(RouteMap.matchLive);
      expect(hits, 3, reason: 'a finished call is not cached either (only in-flight sharing)');
    });
  });

  test('parses data, pageInfo and pagination', () async {
    final c = client(sbx1Server((t, p) => (
          status: 200,
          body: {'message': 'm', 'data': [{'a': 1}], 'pagination': {'total': 41, 'perPage': 20, 'page': 1}}
        )));
    final res = await c.call(RouteMap.matchLive);
    expect(res.dataList.single['a'], 1);
    expect(res.pageInfo!.totalPages, 3);
  });

  for (final code in [404, 422, 400, 429]) {
    test('inner $code throws at once with inner status/message', () async {
      var calls = 0;
      final c = client(sbx1Server((t, p) {
        calls++;
        return (status: code, body: {'message': 'Player not found!!'});
      }));
      await expectLater(
          c.call(RouteMap.playerInfo, {'playerId': 'x'}),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'status', code)
              .having((e) => e.message, 'message', 'Player not found!!')
              .having((e) => e.isNotFound, 'isNotFound', code == 404 || code == 400)));
      expect(calls, 1);
    });
  }

  test('inner 500 is retried and then surfaces', () async {
    var calls = 0;
    final c = client(sbx1Server((t, p) {
      calls++;
      return (status: 500, body: {'message': 'Boom'});
    }));
    await expectLater(c.call(RouteMap.matchLive), throwsA(isA<ApiException>().having((e) => e.message, 'm', 'Boom')));
    expect(calls, 3);
  });

  test('generic gateway 404 becomes ApiException(404, Not Found) without retry', () async {
    var calls = 0;
    final c = client(MockClient((r) async {
      calls++;
      return http.Response('{"message":"Not Found"}', 404);
    }));
    await expectLater(c.call(RouteMap.matchLive),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 404).having((e) => e.message, 'm', 'Not Found')));
    expect(calls, 1);
  });

  test('wrong secret: server answers generic 404', () async {
    final c = client(sbx1Server((t, p) => ok(), secret: List.filled(32, 9)));
    await expectLater(c.call(RouteMap.matchLive), throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 404)));
  });

  group('response tampering', () {
    // a server that returns a valid envelope, then mutated by [mutate]
    ApiClient tampering(FutureOr<Map<String, dynamic>> Function(Map<String, dynamic> env) mutate, {List<int>? resSecret}) {
      return client(MockClient((req) async {
        final token = req.url.pathSegments.last;
        final r = await Sbx1.parseRequest(secret: kTestSecret, token: token, body: jsonDecode(req.body));
        final env = await Sbx1.buildResponse(keys: r.keys, nonceB64: r.nonceB64, payload: {'s': 200, 'b': {'message': 'ok', 'data': []}});
        return http.Response(jsonEncode(await mutate(env)), 200);
      }));
    }

    Matcher invalid() => throwsA(isA<ApiException>().having((e) => e.statusCode, 's', -1).having((e) => e.message, 'm', 'Invalid response from server.'));

    // Always change the first character (a fixed replacement is a no-op 1 time in 64).
    String flip(String v) => '${v.startsWith('A') ? 'B' : 'A'}${v.substring(1)}';
    test('bad MAC', () => expectLater(tampering((e) => {...e, 's': flip(e['s'] as String)}).call(RouteMap.matchLive), invalid()));
    test('modified ciphertext', () => expectLater(tampering((e) => {...e, 'd': flip(e['d'] as String)}).call(RouteMap.matchLive), invalid()));
    test('truncated d (MAC no longer matches)', () => expectLater(tampering((e) => {...e, 'd': (e['d'] as String).substring(0, 20)}).call(RouteMap.matchLive), invalid()));
    test('truncated d with recomputed MAC (too short)', () async {
      // A server that knows the secret but sends a too-short ciphertext.
      final c = client(MockClient((req) async {
        final r = await Sbx1.parseRequest(secret: kTestSecret, token: req.url.pathSegments.last, body: jsonDecode(req.body));
        final d = Sbx1.b64u([1, 2, 3, 4, 5]);
        return http.Response(jsonEncode({'v': 1, 'd': d, 's': await Sbx1.hmac(r.keys.resMac, '1|res|${r.nonceB64}|$d')}), 200);
      }));
      await expectLater(c.call(RouteMap.matchLive), invalid());
    });
    test('response replayed from another request (wrong nonce)', () async {
      Map<String, dynamic>? first;
      final c = client(MockClient((req) async {
        if (first != null) return http.Response(jsonEncode(first), 200);
        final r = await Sbx1.parseRequest(secret: kTestSecret, token: req.url.pathSegments.last, body: jsonDecode(req.body));
        first = Map<String, dynamic>.from(await Sbx1.buildResponse(keys: r.keys, nonceB64: r.nonceB64, payload: {'s': 200, 'b': {'message': 'ok'}}));
        return http.Response(jsonEncode(first), 200);
      }));
      await c.call(RouteMap.matchLive);
      await expectLater(c.call(RouteMap.matchLive), invalid());
    });
    test('response sealed with another secret', () async {
      final c = client(MockClient((req) async {
        final r = await Sbx1.parseRequest(secret: kTestSecret, token: req.url.pathSegments.last, body: jsonDecode(req.body));
        final other = await Sbx1.deriveKeys(List.filled(32, 7), Sbx1.unb64u(r.nonceB64));
        return http.Response(jsonEncode(await Sbx1.buildResponse(keys: other, nonceB64: r.nonceB64, payload: {'s': 200, 'b': {}})), 200);
      }));
      await expectLater(c.call(RouteMap.matchLive), invalid());
    });
    test('missing fields / non-object JSON', () async {
      await expectLater(tampering((e) => {'v': 1}).call(RouteMap.matchLive), invalid());
      await expectLater(client(MockClient((r) async => http.Response('[1,2]', 200))).call(RouteMap.matchLive), invalid());
    });
  });

  test('malformed JSON and empty body on 200 are reported, not crashed on', () async {
    await expectLater(client(MockClient((r) async => http.Response('<html>', 200))).call(RouteMap.matchLive),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 's', -1)));
    await expectLater(client(MockClient((r) async => http.Response('', 200))).call(RouteMap.matchLive),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 's', -1)));
  });

  test('5xx gateway failure is retried and then succeeds', () async {
    var calls = 0;
    final inner = sbx1Server((t, p) => ok({'x': 1}));
    final c = client(MockClient((r) async {
      calls++;
      return calls < 3 ? http.Response('', 503) : replay(inner, r);
    }));
    final res = await c.call(RouteMap.matchLive);
    expect(res.message, 'ok');
    expect(calls, 3);
  });

  test('persistent 502 surfaces a friendly message after all retries', () async {
    var calls = 0;
    final c = client(MockClient((r) async {
      calls++;
      return http.Response('not json', 502);
    }));
    await expectLater(c.call(RouteMap.matchLive), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('temporarily unavailable'))));
    expect(calls, 3);
  });

  test('network error and timeout become ApiException(0)', () async {
    final net = client(MockClient((r) async => throw const SocketException('refused')));
    await expectLater(net.call(RouteMap.matchLive), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)));
    final slow = client(MockClient((r) => Completer<http.Response>().future), timeout: const Duration(milliseconds: 20));
    await expectLater(slow.call(RouteMap.matchLive), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('timed out'))));
  });

  group('clock skew', () {
    test('device clock far off: learns offset from Date header and retries once with corrected t', () async {
      final serverNow = DateTime.utc(2026, 11, 18, 12);
      final deviceNow = serverNow.subtract(const Duration(days: 3));
      final seenTs = <int>[];
      var calls = 0;
      final c = client(MockClient((req) async {
        calls++;
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        seenTs.add(body['t'] as int);
        final stale = ((body['t'] as int) - serverNow.millisecondsSinceEpoch).abs() > 120000;
        final date = HttpDate.format(serverNow);
        if (stale) return http.Response('{"message":"Not Found"}', 404, headers: {'date': date});
        final r = await Sbx1.parseRequest(secret: kTestSecret, token: req.url.pathSegments.last, body: body);
        final env = await Sbx1.buildResponse(keys: r.keys, nonceB64: r.nonceB64, payload: {'s': 200, 'b': {'message': 'ok', 'data': []}});
        return http.Response(jsonEncode(env), 200, headers: {'date': date});
      }), clock: () => deviceNow);
      final res = await c.call(RouteMap.matchLive);
      expect(res.message, 'ok');
      expect(calls, 2);
      expect(seenTs[0], deviceNow.millisecondsSinceEpoch);
      expect((seenTs[1] - serverNow.millisecondsSinceEpoch).abs(), lessThan(1000));
      expect(c.clockOffset.inDays, 3);

      // later calls use the offset right away
      await c.call(RouteMap.matchLive);
      expect(calls, 3);
    });

    test('small skew (<60s) is ignored', () async {
      final now = DateTime.utc(2026, 11, 18, 12);
      final inner = sbx1Server((t, p) => ok());
      final c = client(MockClient((r) async {
        final res = await replay(inner, r);
        return http.Response(res.body, 200, headers: {'date': HttpDate.format(now.add(const Duration(seconds: 30)))});
      }), clock: () => now);
      await c.call(RouteMap.matchLive);
      expect(c.clockOffset, Duration.zero);
    });

    test('gateway 404 without clock change is not retried more than once', () async {
      var calls = 0;
      final c = client(MockClient((r) async {
        calls++;
        return http.Response('{}', 404, headers: {'date': HttpDate.format(DateTime.now().toUtc().add(const Duration(days: 1)))});
      }));
      await expectLater(c.call(RouteMap.matchLive), throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 404)));
      expect(calls, 2);
    });
  });

  test('unconfigured client refuses to call anything', () async {
    final c = ApiClient(client: MockClient((r) async => fail('should not be called')), baseUrl: '', secret: kTestSecret);
    await expectLater(c.call(RouteMap.matchLive), throwsA(isA<ApiException>()));
    final c2 = ApiClient(client: MockClient((r) async => fail('should not be called')), baseUrl: base, secret: null);
    await expectLater(c2.call(RouteMap.matchLive), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'n', true)));
  });

  test('friendlyError hides internals', () {
    expect(friendlyError(const ApiException(0, 'x')), contains('Unable to reach the server'));
    expect(friendlyError(const ApiException(404, 'Match not found!!')), 'Match not found!!');
    expect(friendlyError(StateError('boom')), contains('Something went wrong'));
  });
}
