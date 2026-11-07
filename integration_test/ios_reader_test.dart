import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fqapp/main.dart' as app;
import 'package:fqapp/pages/reader_page.dart';
import 'package:fqapp/services/book_txt_export.dart';

/// Opens the first spotlight novel from the real feed, reads a chapter, and
/// verifies the TXT export channel writes into the app's Documents directory.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS reader and TXT export', (tester) async {
    app.main();
    await tester.pump();
    for (var i = 0; i < 60 && find.text('首页').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('首页'), findsWidgets);

    // The shell mounts before the network feed does; wait for the spotlight
    // card's action label so this test exercises a real novel.
    for (var i = 0;
        i < 180 && find.text('立即阅读').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('立即阅读'), findsWidgets,
        reason: 'home feed must load a novel spotlight');

    await tester.tap(find.text('立即阅读').first);
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0;
        i < 120 &&
            find.text('开始阅读').evaluate().isEmpty &&
            find.text('继续阅读').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    final start = find.text('开始阅读').evaluate().isNotEmpty
        ? find.text('开始阅读')
        : find.text('继续阅读');
    expect(start, findsWidgets, reason: 'detail page must offer reading');
    await tester.tap(start.first);
    await tester.pump(const Duration(seconds: 2));

    for (var i = 0; i < 120 && find.byType(ReaderPage).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(ReaderPage), findsOneWidget,
        reason: 'reader page must open');
    // The surface key appears only after the first chapter has loaded and been
    // paginated, so it proves text rendering rather than just the route.
    for (var i = 0;
        i < 120 &&
            find.byKey(const ValueKey('reader-page-surface')).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byKey(const ValueKey('reader-page-surface')), findsOneWidget,
        reason: 'first chapter must render');

    await tester.runAsync(() async {
      final target = await const PlatformTxtSink().saveText(
        fileName: 'ios-smoke.txt',
        text: 'fqapp iOS export smoke test',
      );
      expect(target.path, contains('Downloads'));
      final file = File(target.path);
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), 'fqapp iOS export smoke test');
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
