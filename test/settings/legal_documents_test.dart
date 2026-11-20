import 'dart:io';

import 'package:crickbex/features/settings/legal_documents.dart';
import 'package:crickbex/features/settings/simple_html.dart';
import 'package:flutter_test/flutter_test.dart';

/// The in-app privacy policy and terms must match the hosted pages word for
/// word. The hosted source lives in Y/legal-site/ next to the app; when it is
/// checked out, compare block by block (text and link targets).
void main() {
  final site = Directory('../legal-site');
  final hasSite = site.existsSync();

  for (final (file, bundled) in [
    ('privacy-policy.html', privacyPolicyHtml),
    ('terms.html', termsOfUseHtml),
  ]) {
    test(
      '$file: bundled copy matches the hosted page',
      () {
        final hosted = parseSimpleHtml(
          File('${site.path}/$file').readAsStringSync(),
        );
        final ours = parseSimpleHtml(bundled);
        expect(ours, isNotEmpty);
        expect(
          [for (final b in ours) '${b.type.name}: ${b.text}'],
          [for (final b in hosted) '${b.type.name}: ${b.text}'],
        );
        expect(
          [for (final b in ours) b.spans],
          [for (final b in hosted) b.spans],
        );
      },
      skip: hasSite ? false : 'legal-site/ not checked out next to the app',
    );
  }

  test('no legacy brand or contact in the bundled documents', () {
    for (final s in [privacyPolicyHtml, termsOfUseHtml]) {
      expect(RegExp('crick\\s?bex', caseSensitive: false).hasMatch(s), isFalse);
      expect(s, contains('ajaykanani01818@gmail.com'));
    }
  });
}
