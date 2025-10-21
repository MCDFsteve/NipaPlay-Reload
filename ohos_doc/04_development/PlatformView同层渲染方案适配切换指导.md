## PlatformView同层渲染方案适配切换指导  
  
## PlatformView旧方案

### 简述

在Flutter适配层定义DynamicView和DVModel。

```java
@Observed
export class DVModel {
  id_: number;
  compType: string;
  params: DVModelParameters;
  events: DVModelEvents;
  children: DVModelChildren;
  builder: Any;

  public getLayoutParams(): DVModelParameters {
    return this.params;
  }
}
```
```java
@Component
export struct DynamicView{
  @ObjectLink model:DVModel;
  @ObjectLink children:DVModelChildren;
  @ObjectLink params:DVModelParameters;
  @ObjectLink events:DVModelEvents;
  @BuilderParam customBuilder?:($$:BuilderParams)=>void;
}
```

开发者使用json字符串来定义生成DVModel模型，实现PlatformView的定义，将FlutterView置于底层，DynamicView实现的PlatformView置于顶层，DynamicView使用ArkUI实现，所以是通过OpenHarmony的原生渲染的。

```java
  build() {
    Stack() {
      XComponent({ id: this.viewId, type: this.xComponentType, libraryname: 'flutter' })
        .focusable(true)
        .focusOnTouch(true)
        .onLoad((context) => {
          this.flutterView?.onSurfaceCreated()
          Log.d(TAG, "XComponent onLoad ");
        })
        .onDestroy(() => {
          Log.d(TAG, "XComponent onDestroy ");
          this.flutterView?.onSurfaceDestroyed()
        })
        .backgroundColor(Color.Transparent)

      ForEach(this.rootDvModel!!, (child: Any) => {
        DynamicView({
          model: child as DVModel,
          params: child.params,
          events: child.events,
          children: child.children,
          customBuilder: child.builder
        })
      })
  }
```
Flutter页面嵌入PlatformView时会有下面两个严重缺陷： 

1. PlatformView覆盖在FlutterView上面出现遮挡问题。
2. 页面切换时，FlutterView和PlatformView动画不一致。 

## PlatformView新方案

### 简述

采用NodeContainer同层渲染功能，将原生平台组件的纹理导出注册到Flutter Engine，由Flutter统一渲染。可以解决旧方案的固有缺陷，并且PlatformView使用自定义ArkUI的Component组件，符合OpenHarmony原生应用开发习惯，不用按照DVModel来定义，同时避免写json没有代码提示的困扰。

```java
  build() {
    Stack() {
      NodeContainer(this.nodeController)
         .width(this.storageLinkWidth)
         .height(this.storageLinkHeight)

      XComponent({ id: this.viewId, type: this.xComponentType, libraryname: 'flutter' })
        .focusable(true)
        .focusOnTouch(true)
        .onLoad((context) => {
          this.flutterView?.onSurfaceCreated()
          Log.d(TAG, "XComponent onLoad ");
        })
        .onDestroy(() => {
          Log.d(TAG, "XComponent onDestroy ");
          this.flutterView?.onSurfaceDestroyed()
        })
        .backgroundColor(Color.Transparent)
    }
  }
```
  
## 新旧方案实现关键区别

旧方案：

```java
private model: DVModel = createDVModelFromJson(
  {
    compType: "Column",
    attributes: { height: '200%'},
    children: [
      {
        compType: "Text",
        attributes: { value: "Native:发送数据给Dart111111111111111", fontColor: Color.Orange,backgroundColor: Color.Black,height: 100},
        events: { onClick: this.sendMessage },
      },
      {
        compType: "Text",
        attributes: { value: "Native:来自Dart的数据", marginTop: 20 },
      }
    ],
  }
);
``` 

```java
/// 自定义PlatformView实体类的实现的接口
getView(): DVModel {
  return this.model;
}
```

新方案： 

```java
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

```java
/// 自定义PlatformView实体类的实现的接口
getView(): WrappedBuilder<[Params]> {
  return new WrappedBuilder(ButtonBuilder);
}
```