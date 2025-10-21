# Using FlutterEntry in Hybrid Development

## 1. Making the EntryAbility to Inherit from the UIAbility

```ts
export default class EntryAbility extends UIAbility implements ExclusiveAppComponent<UIAbility> {

  detachFromFlutterEngine(): void {
    // throw new Error('Method not implemented.');
  }

  getAppComponent(): UIAbility {
    return this;
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    FlutterManager.getInstance().pushUIAbility(this);
  }

  onDestroy(): void | Promise<void> {
    FlutterManager.getInstance().popUIAbility(this);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindowSync().setWindowLayoutFullScreen(true);
    FlutterManager.getInstance().pushWindowStage(this, windowStage);
    windowStage.loadContent('pages/Index');
  }

  onWindowStageDestroy() {
    FlutterManager.getInstance().popWindowStage(this);
  }
}
```

## 2. Making the MyFlutterEntry to Inherit from the FlutterEntry and Registering the Plugin

```ts
export default class MyFlutterEntry extends FlutterEntry {
  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    this.delegate?.addPlugin(new BatteryPlugin());
  }
}
```

## 3. Using the FlutterEntry Together with the FlutterView

```ts
@Entry
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  private flutterEntry: FlutterEntry | null = null;
  private flutterView?: FlutterView

  aboutToAppear() {
    Log.d("Flutter", "Index aboutToAppear===");
    this.flutterEntry = new MyFlutterEntry(getContext(this))
    this.flutterEntry.aboutToAppear()
    this.flutterView = this.flutterEntry.getFlutterView()
  }

  aboutToDisappear() {
    Log.d("Flutter", "Index aboutToDisappear===");
    this.flutterEntry?.aboutToDisappear()
  }

  onPageShow() {
    Log.d("Flutter", "Index onPageShow===");
    this.flutterEntry?.onPageShow()
  }

  onPageHide() {
    Log.d("Flutter", "Index onPageHide===");
    this.flutterEntry?.onPageHide()
  }

  build() {
    Stack() {
      FlutterPage({ viewId: this.flutterView?.getId() })
    }
  }

  onBackPress(): boolean {
    this.context.eventHub.emit('EVENT_BACK_PRESS')
    return true
  }
}
```

## Using the FlutterEntry with Navigation

```ts
@Builder
export function PageThreeBuilder() {
  PageThree()
}

@Component
export struct PageThree {
  private context = getContext(this) as common.UIAbilityContext
  private flutterEntry: FlutterEntry | null = null;
  private flutterView?: FlutterView
  pathStack: NavPathStack = new NavPathStack()

  build() {
    NavDestination() {
      FlutterPage({ viewId: this.flutterView?.getId() })
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.init(context)
    })
    .onDisAppear(() => {
      this.flutterEntry?.aboutToDisappear()
    })
    .onShown(() => {
      this.flutterEntry?.onPageShow()
    })
    .onHidden(() => {
      this.flutterEntry?.onPageHide()
    })
    .onBackPressed(() => {
      this.context.eventHub.emit('EVENT_BACK_PRESS')
      return true
    })
  }

  init(context: NavDestinationContext) {
    let pathStack = context.pathStack
    this.pathStack = pathStack;
    let array = pathStack.getParamByName('pageThree') as Array<Record<string, Object>>;
    let params: Record<string, Object> = array.length > 0 ? array[0] : {};
    this.flutterEntry = new NavFlutterEntry(getContext(this), params, pathStack)
    this.flutterEntry.aboutToAppear()
    this.flutterView = this.flutterEntry.getFlutterView()
  }
}

class NavFlutterEntry extends FlutterEntry {
  pathStack?: NavPathStack;

  constructor(context: Context, params: Record<string, Object> = {}, pathStack?: NavPathStack) {
    super(context, params)
    this.pathStack = pathStack;
  }

  popSystemNavigator(): boolean {
    if (this.pathStack) {
      this.pathStack.pop();
      return true;
    }
    return false;
  }
}
```

For details about the complete demo, see [flutter_page_sample2](https://gitcode.com/openharmony-tpc/flutter_samples/tree/master/ohos/flutter_page_sample2).
