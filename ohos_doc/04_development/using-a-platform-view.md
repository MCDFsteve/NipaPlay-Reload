## Preparations

### 1. Configuring the Flutter Development Environment

For details, see https://gitcode.com/openharmony-tpc/flutter_flutter/blob/master/README.en.md.

### 2. Creating a Project

1. Execute `flutter create --platforms ohos platform_demo` to create a project.

2. Execute `cd` to switch to `platform_demo `. Execute `flutter pub get` to download the dependency.

## Code Implementation

### 1. At the Native Layer

1. Use DevEco Studio to open the `platform_demo\ohos` project.

2. Implement the code in the `platform_demo\ohos\entry\src\main\ets\entryability` directory.

3. Create a `CustomView.ets` file, which is displayed in the Flutter widget. 

   3.1 Define a `Component` to represent the platform view of ohos. 

```ts
@Component
struct ButtonComponent {
    @Prop params: Params
    customView: CustomView = this.params.platformView as CustomView
    @StorageLink('numValue') storageLink: string = "first"
    @State bkColor: Color = Color.Red

    build() {
      Column() {
        Button("Send data to Flutter")
          .border({ width: 2, color: Color.Blue})
          .backgroundColor(this.bkColor)
          .onTouch((event: TouchEvent) => {
            console.log("nodeController button on touched")
          })
          .onClick((event: ClickEvent) => {
            this.customView.sendMessage();
            console.log("nodeController button on click")
           })

        Text(`Data from Flutter: ${this.storageLink}`)
          .onTouch((event: TouchEvent) => {
            console.log("nodeController text on touched")
          })

        }.alignItems(HorizontalAlign.Center)
         .justifyContent(FlexAlign.Center)
         .direction(Direction.Ltr)
         .width('100%')
         .height('100%')
    }
}
```

​      3.2 Define a **builder** method and implement it in the previously mentioned custom **Component**.
```ts
@Builder
function ButtonBuilder(params: Params) {
   ButtonComponent({ params: params })
     .backgroundColor(Color.Yellow)
}
```

​      3.3 Inherit **PlatformView** to implement a custom view. Implement the **getView** API to return `WrappedBuilder(ButtonBuilder)` and place it in the previously mentioned **builder** method.
```ts
import MethodChannel, {
        MethodCallHandler,
        MethodResult
        } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import common from '@ohos.app.ability.common';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';

@Observed
export class CustomView extends PlatformView implements MethodCallHandler {
    numValue: string = "test";

    methodChannel: MethodChannel;
    index: number = 1;

    constructor(context: common.Context, viewId: number, args: ESObject, message: BinaryMessenger) {
        super();
        console.log("nodeController viewId:" + viewId)
        // Register a message channel based on the requirements. This code is only an example.
        this.methodChannel = new MethodChannel(message, `com.rex.custom.ohos/customView${viewId}`, StandardMethodCodec.INSTANCE);
        this.methodChannel.setMethodCallHandler(this);
    }

    onMethodCall(call: MethodCall, result: MethodResult): void {
        // Receive messages from the dart layer.
        let method: string = call.method;
        let link1: SubscribedAbstractProperty<number> = AppStorage.link('numValue');
        switch (method) {
            case 'getMessageFromFlutterView':
                let value: ESObject = call.args;
                this.numValue = value;
                link1.set(value)
                console.log("nodeController receive message from dart: " + this.numValue);
                result.success(true);
                break;
        }
    }

    public sendMessage = () => {
        console.log("nodeController sendMessage")
        // Send messages to the dart layer.
        this.methodChannel.invokeMethod('getMessageFromOhosView', 'natvie - ' + this.index++);
    }

    getView(): WrappedBuilder<[Params]> {
        return new WrappedBuilder(ButtonBuilder);
    }

    dispose(): void {
    }
}
```

​      3.4 Implement a custom `PlatformViewFactory` and use its `create` method to create a custom `PlatformView` instance.

```ts
import common from '@ohos.app.ability.common';
import MessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/MessageCodec';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import PlatformView from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { CustomView } from './CustomView';

export class CustomFactory extends PlatformViewFactory {
  message: BinaryMessenger;

  constructor(message: BinaryMessenger, createArgsCodes: MessageCodec<Object>) {
    super(createArgsCodes);
    this.message = message;
  }

  public create(context: common.Context, viewId: number, args: Object): PlatformView {
    return new CustomView(context, viewId, args, this.message);
  }
}
```

​      3.5 Create a Custom plugin inherited from the Flutter plugin. Register the custom `PlatformViewFactory` in `onAttachedToEngine`.

```ts
import  { FlutterPlugin,
  FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import { CustomFactory } from './CustomFactory';

export class CustomPlugin implements FlutterPlugin {
  getUniqueClassName(): string {
    return 'CustomPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    binding.getPlatformViewRegistry()?.
    registerViewFactory('com.rex.custom.ohos/customView', new CustomFactory(binding.getBinaryMessenger(), StandardMessageCodec.INSTANCE));
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {}
}
```

​      3.6 Open the EntryAbility.ets file and add the plugin. (Alternatively, implement the custom platform view in a OpenHarmony plugin and use it in the application. If this is the case, you do not need to add the plugin explicitly.)

```ts
import { FlutterAbility } from '@ohos/flutter_ohos'
import FlutterEngine from '@ohos/flutter_ohos/src/main/ets/embedding/engine/FlutterEngine';
import { CustomPlugin } from './CustomPlugin';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    this.addPlugin(new CustomPlugin());
  }
}
```

### 2. At the Dart Layer

1. Use the Android Studio to open the `platform_demo` project.

2. Implement the code in the `platform_demo\lib` directory.

3. Create a `CustomOhosView` to show the custom view widget on the native side.
The **OhosView** component is the key to bridging the platform view.

- **viewType**: The value is passed to the native side to notify the plugin for creating the platform view. The platform view should be registered during plugin initialization.
- **onPlatformViewCreated**: a callback when the platform view is successfully created.
- **creationParams**: initialization parameters passed to the platform view.

Use the `OhosView` component to implement a custom ohos view. `viewType` should be the same as the one specified when the Flutter plugin executes `registerViewFactory` on the ets side.
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef OnViewCreated = Function(CustomViewController);

/// Customize the OhosView
class CustomOhosView extends StatefulWidget {
  final OnViewCreated onViewCreated;

  const CustomOhosView(this.onViewCreated, {Key? key}) : super(key: key);

  @override
  State<CustomOhosView> createState() => _CustomOhosViewState();
}

class _CustomOhosViewState extends State<CustomOhosView> {
  late MethodChannel _channel;

  @override
  Widget build(BuildContext context) {
    return _getPlatformFaceView();
  }

  Widget _getPlatformFaceView() {
    return OhosView(
      viewType: 'com.rex.custom.ohos/customView',
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: const <String, dynamic>{'initParams': 'hello world'},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel('com.rex.custom.ohos/customView$id');
    final controller = CustomViewController._(
      _channel,
    );
    widget.onViewCreated(controller);
  }
}
```

4. Create a `CustomViewController` in the file where the `CustomOhosView` is located to implement the interaction between the dart layer and native layer.

```dart
class CustomViewController {
  final MethodChannel _channel;
  final StreamController<String> _controller = StreamController<String>();

  CustomViewController._(
    this._channel,
  ) {
    _channel.setMethodCallHandler(
      (call) async {
        switch (call.method) {
          case 'getMessageFromOhosView':
            // Obtain data from the native layer.
            final result = call.arguments as String;
            _controller.sink.add(result);
            break;
        }
      },
    );
  }

  Stream<String> get customDataStream => _controller.stream;

  // Send data to the native layer.
  Future<void> sendMessageToOhosView(String message) async {
    await _channel.invokeMethod(
      'getMessageFromFlutterView',
      message,
    );
  }
}
```

5. Modify the code in the `platform_demo\lib\main.dart` file.

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'custom_ohos_view.dart';

void main() {
  runApp(const MaterialApp(home: MyHome()));
}

class MyHome extends StatelessWidget {
  const MyHome({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: CustomExample(),
    );
  }
}

class CustomExample extends StatefulWidget {
  const CustomExample({Key? key}) : super(key: key);

  @override
  State<CustomExample> createState() => _CustomExampleState();
}

class _CustomExampleState extends State<CustomExample> {
  String receivedData = '';
  CustomViewController? _controller;

  void _onCustomOhosViewCreated(CustomViewController controller) {
    _controller = controller;
    _controller?.customDataStream.listen((data) {
      // Receive data from the ohos device.
      setState(() {
        receivedData = 'Data from ohos: $data';
      });
    });
  }

  Widget _buildOhosView() {
    return Expanded(
      child: Container(
        color: Colors.blueAccent.withAlpha(60),
        child: CustomOhosView(_onCustomOhosViewCreated),
      ),
      flex: 1,
    );
  }

  Widget _buildFlutterView() {
    return Expanded(
      child: Stack(
        alignment: AlignmentDirectional.bottomCenter,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              TextButton(
                onPressed: () {
                  final randomNum = Random().nextInt(10);
                  _controller
                      ?.sendMessageToOhosView('flutter - $randomNum ');
                },
                child: const Text('Send data to ohos'),
              ),
              const SizedBox(height: 10),
              Text(receivedData),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 15),
            child: Text(
              'Flutter - View',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      flex: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildOhosView(),
        _buildFlutterView(),
      ],
    );
  }
}
```

## Building and Running

### 1. Signature

1. Use DevEco Studio to open the `platform_demo\ohos` directory.

2. Choose `File > Project Structure > Project > Signing Configs`, select `Automatically generate signature`, wait until the automatic signing is complete, and click **OK**.

### 2. Build and Run

1. Execute `cd` to switch to the `platform_demo ` directory.

2. Open the terminal and execute the following instruction to build and run the project:

```cmd
flutter run -d <device-id>
```

## Demo

For details, see [platform_demo](https://gitcode.com/openharmony-tpc/flutter_samples/tree/master/ohos/platform_demo).

<!--no_check-->