import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crickbex/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiClient client(MockClient mock, {Duration timeout = const Duration(seconds: 5)}) =>
    ApiClient(client: mock, baseUrl: 'http://test/api/cricbex', apiKey: 'secret', timeout: timeout, retryDelays: const [Duration.zero, Duration.zero]);

void main() {
  test('sends the API key header and query params; skips null params', () async {
    late http.Request seen;
    final c = client(MockClient((r) async {
      seen = r;
      return http.Response(jsonEncode({'message': 'ok', 'data': []}), 200);
    }));
    await c.get('/match/completed', {'page': 2, 'perPage': 10, 'status': null});
    expect(seen.headers['sb-live-score-api-key'], 'secret');
    expect(seen.url.toString(), 'http://test/api/cricbex/match/completed?page=2&perPage=10');
  });

  test('parses data, pageInfo and pagination', () async {
    final c = client(MockClient((r) async => http.Response(
        jsonEncode({'message': 'm', 'data': [{'a': 1}], 'pagination': {'total': 41, 'perPage': 20, 'page': 1}}), 200)));
    final res = await c.get('/x');
    expect(res.dataList.single['a'], 1);
    expect(res.pageInfo!.totalPages, 3);
  });

  test('4xx throws immediately without retry and exposes isNotFound', () async {
    var calls = 0;
    final c = client(MockClient((r) async {
      calls++;
      return http.Response(jsonEncode({'message': 'Player not found!!'}), 404);
    }));
    await expectLater(c.get('/players/x/info'), throwsA(isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', true)));
    expect(calls, 1);
  });

  test('5xx is retried and then succeeds', () async {
    var calls = 0;
    final c = client(MockClient((r) async {
      calls++;
      return calls < 3 ? http.Response('{}', 503) : http.Response(jsonEncode({'message': 'ok', 'data': {}}), 200);
    }));
    final res = await c.get('/x');
    expect(res.message, 'ok');
    expect(calls, 3);
  });

  test('persistent 5xx surfaces a friendly message after all retries', () async {
    var calls = 0;
    final c = client(MockClient((r) async {
      calls++;
      return http.Response('not json', 502);
    }));
    await expectLater(c.get('/x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('temporarily unavailable'))));
    expect(calls, 3);
  });

  test('network error and timeout become ApiException(0)', () async {
    final net = client(MockClient((r) async => throw const SocketException('refused')));
    await expectLater(net.get('/x'), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)));

    final slow = client(MockClient((r) => Completer<http.Response>().future), timeout: const Duration(milliseconds: 20));
    await expectLater(slow.get('/x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('timed out'))));
  });

  test('invalid JSON body on 200 is reported, not crashed on', () async {
    final c = client(MockClient((r) async => http.Response('<html>', 200)));
    await expectLater(c.get('/x'), throwsA(isA<ApiException>()));
  });

  test('unconfigured client refuses to call anything', () async {
    final c = ApiClient(client: MockClient((r) async => fail('should not be called')), baseUrl: '', apiKey: '');
    await expectLater(c.get('/x'), throwsA(isA<ApiException>()));
  });

  test('friendlyError hides internals', () {
    expect(friendlyError(const ApiException(0, 'x')), contains('Unable to reach the server'));
    expect(friendlyError(const ApiException(404, 'Match not found!!')), 'Match not found!!');
    expect(friendlyError(StateError('boom')), contains('Something went wrong'));
  });
}
