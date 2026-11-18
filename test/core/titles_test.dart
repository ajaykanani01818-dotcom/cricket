import 'package:crickbex/core/widgets/titles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ScreenTitle band spans the full width even inside a centered Column', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Column(children: [ScreenTitle(title: 'CrickBex')])),
    ));
    final band = tester.getSize(find.byType(ScreenTitle));
    expect(band.width, tester.view.physicalSize.width / tester.view.devicePixelRatio);
  });
}
