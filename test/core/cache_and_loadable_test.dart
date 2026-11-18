import 'dart:async';

import 'package:crickbex/core/api/api_cache.dart';
import 'package:crickbex/core/api/api_client.dart';
import 'package:crickbex/core/widgets/async_value.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cache returns fresh values and drops expired ones', () async {
    await ApiCache.set('/a', {'p': 1}, {'x': 1}, const Duration(minutes: 1));
    expect(await ApiCache.get('/a', {'p': 1}), {'x': 1});
    expect(await ApiCache.get('/a', {'p': 2}), isNull);
    await ApiCache.set('/b', null, [1], Duration.zero);
    expect(await ApiCache.get('/b'), isNull);
    await ApiCache.clear();
    expect(await ApiCache.get('/a', {'p': 1}), isNull);
  });

  test('Loadable keeps old data on refresh error and ignores stale responses', () async {
    final completers = <Completer<int>>[];
    final l = Loadable<int>(() {
      final c = Completer<int>();
      completers.add(c);
      return c.future;
    });
    final first = l.load();
    completers[0].complete(1);
    await first;
    expect(l.data, 1);

    // Two overlapping refreshes: the older one resolves last and must be ignored.
    final a = l.load(silent: true);
    final b = l.load(silent: true);
    completers[2].complete(3);
    await b;
    completers[1].complete(2);
    await a;
    expect(l.data, 3);

    final c = l.load(silent: true);
    completers[3].completeError(const ApiException(503, 'down'));
    await c;
    expect(l.data, 3, reason: 'previous data is kept');
    expect(l.errorMessage, 'down');
  });

  test('Loadable does not notify after dispose', () async {
    final c = Completer<int>();
    final l = Loadable<int>(() => c.future);
    final f = l.load();
    l.dispose();
    c.complete(1);
    await f; // must not throw "used after dispose"
  });
}
