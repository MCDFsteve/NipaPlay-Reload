# 如何使用Flutter与OpenHarmony通信 FlutterChannel

本文介绍在Flutter OpenHarmony化工程中，如何使用 Flutter Channel 能力。

以下是关键实现代码，完整的demo请参考 [channel_demo](../../channel_demo/)。

## MethodChannel

dart代码：

```dart
// 创建实例
final _platform = const MethodChannel('samples.flutter.dev/battery');
// 调用方法 getBatteryLevel
final result = await _platform.invokeMethod<int>('getBatteryLevel');
```

ets代码：

```ts
onAttachedToEngine(binding: FlutterPluginBinding): void {
    let that = this;
    // 创建实例
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "samples.flutter.dev/battery");
    // 设置回调，调用具体的实现
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

dart代码：

```dart
int count = 0;
// 创建实例
final _basicChannel = const BasicMessageChannel(
      "samples.flutter.dev/basic_channel", StandardMessageCodec());
// 调用方法，获取平台侧的返回值
String result = await _basicChannel.send(++count) as String;
```

ets代码：

```ts
onAttachedToEngine(binding: FlutterPluginBinding): void {
    // 创建实例
    this.basicChannel = new BasicMessageChannel(binding.getBinaryMessenger(), "samples.flutter.dev/basic_channel", new StandardMessageCodec());
    // 设置回调，调用具体的实现
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

dart代码：

```dart
// 创建实例
final _eventChannel = const EventChannel('samples.flutter.dev/event_channel');
// 注册事件监听
_eventChannel.receiveBroadcastStream().listen((event) {
    setState(() {
        message = "EventChannel event=$event";
    });
});
```

ets代码：

```ts
private eventSink?: EventSink;

onAttachedToEngine(binding: FlutterPluginBinding): void {
    let that = this;
    // 创建实例
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "samples.flutter.dev/event_channel");
    // 设置回调，获取EventSink
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
// 使用 EventSink 发送数据后，dart断的事件监听回调会收到发送的数据。
that.eventSink?.success("Success at " + new Date());
```
