## 准备工作

### 一、Flutter开发环境配置

[参考](https://gitcode.com/openharmony-tpc/flutter_flutter/blob/master/README.md)

### 二、创建项目

1. 执行 `flutter create --platforms ohos platform_demo` 创建项目。

2. `cd` 到 `platform_demo` 目录下，执行 `flutter pub get` 下载依赖。

## 代码实现

### 一、Native侧

1. 使用 `DevEco Studio` 工具打开 `platform_demo\ohos` 项目。

2. 在 `platform_demo\ohos\entry\src\main\ets\entryability` 目录下实现代码。

3. 新建 `CustomView.ets` 文件，`CustomView` 用于在Flutter Widget里显示。 

    1. 定义一个`Component`，代表ohos的`PlatformView`的定义。

        ```ts
        @Component
        struct ButtonComponent {
            @Prop params: Params
            customView: CustomView = this.params.platformView as CustomView
            @StorageLink('numValue') storageLink: string = "first"
            @State bkColor: Color = Color.Red

            build() {
              Column() {
                Button("发送数据给Flutter")
                  .border({ width: 2, color: Color.Blue})
                  .backgroundColor(this.bkColor)
                  .onTouch((event: TouchEvent) => {
                    console.log("nodeController button on touched")
                  })
                  .onClick((event: ClickEvent) => {
                    this.customView.sendMessage();
                    console.log("nodeController button on click")
                  })

                Text(`来自Flutter的数据 : ${this.storageLink}`)
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
  
    2. 定义一个builder方法，放入自定义Component组件。

        ```ts
        @Builder
        function ButtonBuilder(params: Params) {
          ButtonComponent({ params: params })
            .backgroundColor(Color.Yellow)
        }
        ```
  
    3. 继承PlatformView实现一个自定义的Customview，实现getView接口，返回`WrappedBuilder(ButtonBuilder)`，放入builder方法。

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
                // 注册消息通道，消息通道根据具体需求添加，代码仅作为示例
                this.methodChannel = new MethodChannel(message, `com.rex.custom.ohos/customView${viewId}`, StandardMethodCodec.INSTANCE);
                this.methodChannel.setMethodCallHandler(this);
            }

            onMethodCall(call: MethodCall, result: MethodResult): void {
                // 接受Dart侧发来的消息
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
                //向Dart侧发送消息
                this.methodChannel.invokeMethod('getMessageFromOhosView', 'natvie - ' + this.index++);
            }

            getView(): WrappedBuilder<[Params]> {
                return new WrappedBuilder(ButtonBuilder);
            }

            dispose(): void {
            }
        }
        ```

    4. 实现一个自定义的`PlatformViewFactory`，在其`create`方法中创建自定义的`PlatformView`的实例。

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

    5. 新建一个继承于`FlutterPlugin`的CustomPlugin插件，在`onAttachedToEngine`中，注册自定义的`PlatformViewFactory`

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

    6. 打开`EntryAbility.ets`文件，添加Plugin(也可以把自定义PlatformView写在一个OpenHarmony插件中，在应用中沿用，就不用在此显式添加插件)

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

### 二、Dart侧

1. 使用 `Android Studio`工具打开 `platform_demo`项目。

2. 在`platform_demo\lib`目录下实现代码。

3. 新建`CustomOhosView`，用于显示`Native`侧的`CustomView的Widget`
OhosView组件就是桥接PlatformView的关键。

   * viewType：传递给Native侧，告知插件需要创建那个PlatformView，这个PlatformView需要在插件初始化时注册。
   * onPlatformViewCreated：PlatformView创建成功时的回调。
   * creationParams：传递给PlatformView的初始化参数。

   实现`CustomOhosView`，使用`OhosView`组件，`viewType`需要和ets侧`FlutterPlugin`做`registerViewFactory`操作时指定的`viewType`一致。
   
    ```dart
    import 'dart:async';

    import 'package:flutter/material.dart';
    import 'package:flutter/services.dart';

    typedef OnViewCreated = Function(CustomViewController);

    ///自定义OhosView
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


4. 在`CustomOhosView`所在文件中新建`CustomViewController`，用于实现Dart侧与Native侧的交互。

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
                // 从native端获取数据
                final result = call.arguments as String;
                _controller.sink.add(result);
                break;
            }
          },
        );
      }

      Stream<String> get customDataStream => _controller.stream;

      // 发送数据给native
      Future<void> sendMessageToOhosView(String message) async {
        await _channel.invokeMethod(
          'getMessageFromFlutterView',
          message,
        );
      }
    }
    ```

5. 修改`platform_demo\lib\main.dart`文件中的代码。

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
          //接收到来自OHOS端的数据
          setState(() {
            receivedData = '来自ohos的数据：$data';
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
                    child: const Text('发送数据给ohos'),
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

## 编译运行

### 一、签名

1. 使用 `DevEco Studio` 工具打开 `platform_demo\ohos` 目录。

2. 单击 `File > Project Structure > Project > Signing Configs` 界面勾选 `Automatically generate signature`，等待自动签名完成，点击OK。

### 二、编译运行

1. `cd` 到 `platform_demo` 目录下。

2. 打开 终端，执行下面指令进行编译运行：

    ```cmd
    flutter run -d <device-id>
    ```

## demo

请参考 [platform_demo](../../platform_demo/)。
