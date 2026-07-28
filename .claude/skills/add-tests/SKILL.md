---
name: add-tests
description: Writing or updating Dart tests in the OTPLESS Flutter plugin. Use when adding tests, after changing lib/ marshalling or parsing logic (a test is required in the same PR), or when asked to write a test — covers the fake-channel recipe, what is genuinely testable from Dart, and what only an example-app run can prove.
---

# Adding tests to flutter-headless-sdk

Tests live in `test/` and run with `flutter test`. Existing files: `test/otpless_flutter_test.dart`, `test/otpless_flutter_method_channel_test.dart`.

## What is and isn't testable — read this first

`flutter test` runs pure Dart. There is **no** Android, no iOS, no native SDK, no real method channel.

| Testable from Dart | NOT testable from Dart |
|---|---|
| That a Dart method invokes the right channel method name | That a native handler for that name exists |
| The exact argument map/JSON Dart sends | That either native reads those keys |
| Platform guards (`Platform.isAndroid`) routing | Any Kotlin or Swift behavior |
| Response decoding from an `otpless_callback_event` payload | That native ever sends that shape |
| Return-value coercion (`(res as bool?) ?? false`) | Real SDK responses |

So a Dart test proves **our side of the contract**. The other side is covered by `docs-verify.sh` check 3 (a handler exists) and the example builds (it compiles). Never describe a passing Dart test as proof a bridge change works — see the **verify** skill.

## The recipe: faking the method channel

Use `TestDefaultBinaryMessengerBinding` to intercept outgoing calls and record them:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otpless_headless_flutter/otpless_flutter_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('otpless_headless_flutter');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'isSdkReady':
          return true;
        case 'getActiveSession':
          return <Object?, Object?>{'isActive': true, 'jwtToken': 'jwt'};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);   // ALWAYS clear
  });

  test('setMfaEnabled sends the enabled flag', () async {
    await MethodChannelOtplessFlutter().setMfaEnabled(true);
    expect(calls.single.method, 'setMfaEnabled');
    expect(calls.single.arguments, {'enabled': true});
  });
}
```

Rules:
- **Always clear the handler in `tearDown`.** A leaked mock handler makes later tests pass for the wrong reason — the worst failure mode in a suite this small.
- Assert on the **exact argument map**, not just the method name. The argument keys are the contract; a typo in a key is precisely the bug worth catching.
- For payloads sent as JSON strings (`start`, `startOnetap`, `startInBackground`), decode before asserting:
  ```dart
  final sent = jsonDecode((calls.single.arguments as Map)['arg'] as String);
  expect(sent['phone'], '9999999999');
  ```

## Testing the reverse direction (responses)

Responses arrive as a **JSON string** through `otpless_callback_event`, handled by `setMethodCallHandler` on the same channel. Drive it by sending a platform message:

```dart
Future<void> emit(String json) async {
  const codec = StandardMethodCodec();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'otpless_headless_flutter',
    codec.encodeMethodCall(MethodCall('otpless_callback_event', json)),
    (_) {},
  );
}
```

This is the seam that catches a real live defect: the handler force-unwraps the callback (`_callback!`), so emitting a response **before** any callback is registered throws. A regression test for that is worth writing.

## What a test is required for

Per the constitution, a test in the same PR is required when you change:
- any argument map or key sent over the channel
- response decoding or return-value coercion
- a platform guard (`Platform.isAndroid` routing)
- anything in `models.dart`'s `toMap()` — those maps are wire format

No Dart test is required (or possible) for a change confined to Kotlin or Swift. Use the example builds instead and say so.

## Traps

- **`setMockMethodCallHandler` is per-channel.** `EventChannel('otpless_callback_event')` is a *different* channel name from the method channel; the plugin actually delivers responses over the **method** channel via `setMethodCallHandler`, despite declaring an unused `eventChannel` field. Mock the method channel.
- **Enum `.name` is wire format.** When testing `models.dart`, assert the literal string (`'authInitiated'`), not `AuthEvent.authInitiated.name` — otherwise a rename passes the test and breaks the bridge.
- **`MethodChannelOtplessFlutter()`'s constructor registers a handler** as a side effect. Constructing several instances in one test file cross-wires them; construct once per test.
- Keep tests hermetic: no network, no timers, no `Platform` overrides beyond what `debugDefaultTargetPlatformOverride` supports.
