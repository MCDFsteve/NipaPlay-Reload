# Using a Flutter Channel for Communication Between Flutter and OpenHarmony

This topic describes how to use a Flutter channel in the OpenHarmony Flutter project.

The following are the key implementation codes. For details about the complete demo, see [channel_demo](https://gitcode.com/openharmony-tpc/flutter_samples/tree/master/ohos/channel_demo).

## MethodChannel

Dart code

```dart
// Create an instance.
final _platform = const MethodChannel('samples.flutter.dev/battery');
// Call the getBatteryLevel method.
final result = await _platform.invokeMethod<int>('getBatteryLevel');
```

ets code

```ts
onAttachedToEngine(binding: FlutterPluginBinding): void {
    let that = this;
    // Create an instance.
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "samples.flutter.dev/battery");
    // Set the callback and call the implementation.
    this.channel.setMethodCallHandler({
        onMethodCall(call: MethodCall, result: MethodResult) {
        switch (call.method) {
            case "getBatteryLevel":
                that.api.getBatteryLevel(result);
            break;
            default:
                result.notImplemented();
            break;
        }
        }
    })
}
```

## BasicMessageChannel

Dart code

```dart
int count = 0;
// Create an instance.
final _basicChannel = const BasicMessageChannel(
      "samples.flutter.dev/basic_channel", StandardMessageCodec());
// Call a method to obtain the return value from the platform.
String result = await _basicChannel.send(++count) as String;
```

ets code

```ts
onAttachedToEngine(binding: FlutterPluginBinding): void {
    // Create an instance.
    this.basicChannel = new BasicMessageChannel(binding.getBinaryMessenger(), "samples.flutter.dev/basic_channel", new StandardMessageCodec());
    // Set the callback and call the implementation.
    this.basicChannel.setMessageHandler({
        onMessage(message: Any, reply: Reply<Any>) {
        Log.i(TAG, "message=" + message);
        if (message % 2 == 0) {
            reply.reply("run with if case.");
        } else {
            reply.reply("run with else case");
        }
        }
    })
}
```

## EventChannel

Dart code

```dart
// Create an instance.
final _eventChannel = const EventChannel('samples.flutter.dev/event_channel');
// Enable listening for events.
_eventChannel.receiveBroadcastStream().listen((event) {
    setState(() {
        message = "EventChannel event=$event";
    });
});
```

ets code

```ts
private eventSink?: EventSink;

onAttachedToEngine(binding: FlutterPluginBinding): void {
    let that = this;
    // Create an instance.
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "samples.flutter.dev/event_channel");
    // Set the callback to obtain EventSink.
    this.eventChannel.setStreamHandler({
        onListen(args: Any, events: EventSink): void {
            that.eventSink = events;
            Log.i(TAG, "onListen: " + args);
        },
        onCancel(args: Any): void {
            that.eventSink = undefined;
            Log.i(TAG, "onCancel: " + args);
        }
    });
}

// ...
// After EventSink sends the data, the event listener at the dart layer can receive the sent data.
that.eventSink?.success("Success at " + new Date());
```
