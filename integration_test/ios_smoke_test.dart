import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fqapp/main.dart' as app;
import 'package:fqapp/services/native_player.dart';
import 'package:fqapp/services/reader_device.dart';
import 'package:fqapp/services/system_tts.dart';

/// End-to-end smoke test for the iOS host: tabs, native player/texture, system
/// TTS and the reader-device bridge all run on the simulator against real
/// content and the real Rust core.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS host channels work end to end', (tester) async {
    app.main();
    await tester.pump();

    // Backend startup + first feed load are network-bound; poll for the shell.
    for (var i = 0; i < 60 && find.text('首页').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('首页'), findsWidgets, reason: 'app shell must mount');

    await tester.tap(find.text('短剧').last);
    await tester.pump(const Duration(seconds: 2));
    // The first feed card starts inline playback. A texture key means the CENC
    // preparation + AVPlayer + Flutter texture path all succeeded; a retry key
    // means playback failed and the card is showing its error state.
    bool hasKey(String fragment) => find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey &&
              (widget.key! as ValueKey).value
                  .toString()
                  .contains(fragment),
        )
        .evaluate()
        .isNotEmpty;
    for (var i = 0;
        i < 240 && !hasKey('drama_inline_texture_') && !hasKey('drama_inline_retry_');
        i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      hasKey('drama_inline_retry_'),
      isFalse,
      reason: 'inline drama playback reported an error',
    );
    expect(
      hasKey('drama_inline_texture_'),
      isTrue,
      reason: 'inline drama never produced a video texture',
    );
    await tester.tap(find.text('书架').last);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('首页').last);
    await tester.pump(const Duration(seconds: 2));

    // Native player: a plain MP4 exercises AVPlayer + the Flutter texture path
    // without depending on upstream CENC data.
    await tester.runAsync(() async {
      final player = NativePlayer();
      final frames = <bool>[];
      final sizes = <Size>[];
      final errors = <Object>[];
      final sub1 = player.firstFrameStream.listen(frames.add);
      final sub2 = player.videoSizeStream.listen(sizes.add);
      final sub3 = player.errorStream.listen(errors.add);
      try {
        await player.create(
          'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
          '',
        );
        await player.play();
        for (var i = 0; i < 40 && frames.isEmpty && errors.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        expect(errors, isEmpty, reason: 'player error: $errors');
        expect(sizes, isNotEmpty, reason: 'video size event expected');
        expect(frames, isNotEmpty, reason: 'first frame event expected');
      } finally {
        await sub1.cancel();
        await sub2.cancel();
        await sub3.cancel();
        await player.dispose();
        await NativePlayer.setKeepScreenOn(false);
      }
    });

    // System TTS bridge: report an engine, initialize, speak and shut down.
    await tester.runAsync(() async {
      final engines = await SystemTts.engines();
      expect(engines.engines, isNotEmpty);
      final maxLength = await SystemTts.initialize(
        const SystemTtsPreferences(rate: 1),
      );
      expect(maxLength, greaterThan(0));
      final done = Completer<void>();
      final subscription = SystemTts.events.listen((event) {
        if (event is Map &&
            event['type'] == 'done' &&
            event['id'] == 'ios-smoke' &&
            !done.isCompleted) {
          done.complete();
        }
      });
      await SystemTts.speak('这是 iOS 系统朗读测试。', 'ios-smoke');
      await done.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw StateError('TTS done event not received'),
      );
      await subscription.cancel();
      await SystemTts.stop();
      await SystemTts.shutdown();
    });

    // Reader device bridge: brightness session, keep-awake, immersive no-op.
    await tester.runAsync(() async {
      final device = ReaderDevice();
      final status = await device.start(
        followSystem: true,
        brightness: -1,
      );
      expect(status, isNotNull);
      expect(status!.systemBrightness, isNotNull);
      expect(await device.setBrightness(followSystem: false, brightness: 0.5),
          isTrue);
      await device.keepScreenOn(true);
      await device.keepScreenOn(false);
      await device.setImmersive(true);
      await device.setImmersive(false);
      await device.close();
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
