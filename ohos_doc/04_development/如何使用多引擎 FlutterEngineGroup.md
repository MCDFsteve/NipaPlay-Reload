# 如何使用多引擎 FlutterEngineGroup

## 1. EntryAbility 修改为继承自 UIAbility

```ts
export default class EntryAbility extends UIAbility implements ExclusiveAppComponent<UIAbility>{
  detachFromFlutterEngine(): void {
    // throw new Error('Method not implemented.');
  }

  getAppComponent(): UIAbility {
    return this;
  }

  static app?: EntryAbility;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    FlutterManager.getInstance().pushUIAbility(this);
    EntryAbility.app = this;
  }

  onDestroy(): void | Promise<void> {
    FlutterManager.getInstance().popUIAbility(this);
    EntryAbility.app = undefined;
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    FlutterManager.getInstance().pushWindowStage(this, windowStage);
    windowStage.loadContent('pages/MainPage');
  }

  onWindowStageDestroy() {
    FlutterManager.getInstance().popWindowStage(this);
  }
}
```

## 2. 封装 FlutterEngine 的 attach 和 detach 操作

```ts
export class EngineBindings implements DataModelObserver {
  private engine?: FlutterEngine;
  private channel?: MethodChannel;
  private context: common.Context;
  private delegate: EngineBindingsDelegate;
  private flutterView: FlutterView;

  constructor(context: common.Context, delegate: EngineBindingsDelegate) {
    this.context = context;
    this.delegate = delegate;
    this.flutterView = FlutterManager.getInstance().createFlutterView(context);
  }

  getFlutterViewId() {
    return this.flutterView.getId();
  }

  async attach() {
    if (this.engine) {
      Log.i("Multi->attach", "engine is ");
      return;
    }
    DataModel.instance.addObserver(this);
    // 建议按以下代码顺序，依次执行 1、2、3、4、5
    // 1.
    await engines.checkLoader(this.context, []);
    let options: Options = new Options(this.context).setDartEntrypoint(DartEntrypoint.createDefault());
    // 2. 
    this.engine = await engines.createAndRunEngineByOptions(options) ?? undefined;
    if (!this.engine) {
      throw new Error("Create engine failed.");
    }
    // 3.
    this.engine.getLifecycleChannel()?.appIsResumed();
    if (EntryAbility.app) {
      // 4.
      this.engine.getAbilityControlSurface()?.attachToAbility(EntryAbility.app);
    }
    // 5.
    this.flutterView.attachToFlutterEngine(this.engine);
    GeneratedPluginRegistrant.registerWith(this.engine);

    // ...
  }

  detach() {
    this.flutterView.detachFromFlutterEngine();
    this.engine?.destroy();
    DataModel.instance.removeObserver(this);
    this.channel?.setMethodCallHandler(null);
  }

  // ...
}
```

## 3. 调用 FlutterEngine 的 attach 和 detach 操作

```ts
@Entry()
@Component
struct SingleFlutterPage {
  @State viewId: string = "";
  private context = getContext(this) as common.UIAbilityContext
  private engineBindings: EngineBindings = new EngineBindings(this.context, this);

  onNext() {
    router.pushUrl({ "url": "pages/MainPage" });
  }

  aboutToAppear() {
    Log.i("Multi->aboutToAppear", "SingleFlutterPage");
    this.viewId = this.engineBindings.getFlutterViewId();
    Log.i("Multi->aboutToAppear", "SingleFlutterPage, id=" + this.viewId);
    this.engineBindings.attach();
  }

  aboutToDisappear(): void {
    this.engineBindings.detach();
  }

  build() {
    Column() {
      FlutterPage({ viewId: this.viewId, xComponentType: XComponentType.TEXTURE }).backgroundColor(Color.Transparent)
    }
  }
}
```

完整的demo请参考 [multiple_flutters_ohos](https://gitcode.com/openharmony-tpc/flutter_samples/tree/master/add_to_app/multiple_flutters/multiple_flutters_ohos)。
