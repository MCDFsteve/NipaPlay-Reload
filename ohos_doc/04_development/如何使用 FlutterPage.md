# 如何使用 FlutterPage

## 如何在OpenHarmony应用中添加新页面

1. 使用 DevEco-Studio 打开 ohos 工程
2. 鼠标右键点击 ohos/entry/src/main/ets/pages 目录，依次选择 New->Page->Empty Page
3. 修改 Page Name，鼠标左键点击Finish

## 1. EntryAbility 需要继承自 FlutterAbility

```ts
export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }
}
```

## 2. 在OpenHarmony的页面中使用 FlutterPage

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

完整demo请参考 [flutter_page_sample1](../../flutter_page_sample1/)。
