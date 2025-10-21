## Platform View Same-Layer Rendering Adaptation and Switching 

  
## Old Solution

### Overview
Define DynamicView and DVModel at the Flutter adaptation layer.
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
Use JSON strings to define and generate a DVModel and implement the PlatformView. Place the FlutterView at the bottom layer and the PlatformView implemented by the DynamicView at the top layer. The DynamicView, implemented using ArkUI, is a native rendering product of OpenHarmony.
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
There are two major defects when a Flutter page is embedded into the PlatformView: 
    1. The PlatformView blocks the FlutterView. 
    2. The FlutterView and PlatformView animations are inconsistent during page switching. 
  
  
  
## New Solution

### Overview
The NodeContainer is introduced for same-layer rendering, so that textures of native components can be registered with the Flutter engine and rendered by Flutter. The solution can solve the inherent defects of the old solution. In addition, the PlatformView uses the custom ArkUI component, which complies with the native OpenHarmony application development habits. You are no longer restricted by the DVModel and can get prompts when compiling JSON strings.
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

  
## Key Solution Differences
Old solution
```java
private model: DVModel = createDVModelFromJson(
  {
    compType: "Column",
    attributes: { height: '200%'},
    children: [
      {
        compType: "Text",
        attributes: { value: "Native: send data to Dart111111111111111", fontColor: Color.Orange,backgroundColor: Color.Black,height: 100},
        events: { onClick: this.sendMessage },
      },
      {
        compType: "Text",
        attributes: { value: "Native: data from dart", marginTop: 20 },
      }
    ],
  }
);
``` 
```java
/// Customize the APIs of the PlatformView entity class.
getView(): DVModel {
  return this.model;
}
```
New solution 
```java
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
```java
/// Customize the APIs of the PlatformView entity class.
getView(): WrappedBuilder<[Params]> {
  return new WrappedBuilder(ButtonBuilder);
}
```
