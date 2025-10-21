# Using FlutterPage

## 1. Adding a Page to Your OpenHarmony Application

1. Use DevEco Studio to open the ohos project.
2. Right-click **ohos/entry/src/main/ets/pages** directory and choose **New** > **Page** > **Empty Page** from the shortcut menu.
3. Edit **Page Name** and click **Finish**.

## 2. Making the EntryAbility to Inherit from the FlutterAbility

```ts
export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }
}
```

## 3. Using FlutterPage in the OpenHarmony Application

```ts
let storage = LocalStorage.getShared()

@Entry(storage)
@Component
struct Page1 {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";

  build() {
    Stack({ alignContent: Alignment.Top }) {
      FlutterPage({ viewId: this.viewId })
      Text('Components overlaid above FlutterPage').margin(30)
    }
  }
}
```

For details about the complete demo, see [flutter_page_sample1](https://gitcode.com/openharmony-tpc/flutter_samples/tree/master/ohos/flutter_page_sample1).
