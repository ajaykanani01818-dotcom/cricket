import 'package:crickbex/features/search/recent_searches.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('RecentSearches.clear removes every stored query', () async {
    SharedPreferences.setMockInitialValues({});
    await RecentSearches.add('Pakistan');
    await RecentSearches.add('Ashes');
    expect(await RecentSearches.load(), isNotEmpty);
    await RecentSearches.clear();
    expect(await RecentSearches.load(), isEmpty);
  });
}
