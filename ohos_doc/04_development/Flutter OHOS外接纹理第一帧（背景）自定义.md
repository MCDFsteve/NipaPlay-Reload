
# Flutter OHOS外接纹理第一帧（背景）自定义

## 概述
在这个 Flutter 插件中，`flutterRenderer.setTextureBackGroundColor` 和 `flutterRenderer.setTextureBackGroundPixelMap` 方法用于设置视频播放器纹理的背景颜色和纹理内容。背景颜色和纹理图像可以在视频加载或播放之前设置，确保用户在等待视频渲染时看到合适的背景。

## `flutterRenderer` 类型
`flutterRenderer` 是 `TextureRegistry` 类型的实例，它是通过 `FlutterState` 类获取的。`FlutterState` 类包含两个重要成员：
- **`binaryMessenger`** (`BinaryMessenger`): 用于与 Flutter 引擎之间进行消息传递。
- **`textureRegistry`** (`TextureRegistry`): 用于管理纹理和注册新纹理。

### `FlutterState` 类
```typescript
export class FlutterState {
  private binaryMessenger: BinaryMessenger;
  private textureRegistry: TextureRegistry;

  constructor(binaryMessenger: BinaryMessenger, textureRegistry: TextureRegistry) {
    this.binaryMessenger = binaryMessenger;
    this.textureRegistry = textureRegistry;
  }

  getBinaryMessenger(): BinaryMessenger {
    return this.binaryMessenger;
  }

  getTextureRegistry(): TextureRegistry {
    return this.textureRegistry;
  }
}
```

通过 `FlutterState.getTextureRegistry()` 方法，你可以访问 `flutterRenderer`，它是 `TextureRegistry` 的一个实例，并且可以使用它来管理和注册视频播放器的纹理。

## 方法签名

### `flutterRenderer.setTextureBackGroundColor`
```dart
flutterRenderer.setTextureBackGroundColor(int textureId, int color)
```

- **`textureId`** (`int`): 纹理的 ID，用于标识要设置背景颜色的纹理。
- **`color`** (`int`): 背景颜色的值，采用 32 位十六进制格式 `0xAABBGGRR`。

### `flutterRenderer.setTextureBackGroundPixelMap`
```dart
flutterRenderer.setTextureBackGroundPixelMap(int textureId, image.PixelMap pixelMap)
```

- **`textureId`** (`int`): 纹理的 ID，用于标识要设置图像纹理的纹理。
- **`pixelMap`** (`image.PixelMap`): 包含图像数据的 `PixelMap` 对象，用作纹理的背景图像。

## 主要功能
1. **设置背景颜色**  
   `setTextureBackGroundColor` 方法用于设置纹理的背景颜色。在视频加载之前，它为纹理提供一个预设颜色，通常用于显示纯色背景。

2. **设置背景图像**  
   `setTextureBackGroundPixelMap` 方法则允许你将一帧视频图像或任何图像设置为纹理的背景，通常在视频文件加载时，用第一帧图像填充纹理。

## 示例代码

### 设置背景颜色为红色
```dart
flutterRenderer.setTextureBackGroundColor(textureId, 0xFF0000FF);
```

在此示例中，背景颜色被设置为红色 (`0xFF0000FF`)，这意味着：
- `FF` 是 Alpha 值，表示完全不透明。
- `00` 是蓝色分量，表示没有蓝色。
- `00` 是绿色分量，表示没有绿色。
- `FF` 是红色分量，表示最大红色。

### 设置背景图像为视频的第一帧
```dart
let avImageGenerator = await media.createAVImageGenerator();
let pixelMap = await avImageGenerator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, {
  width: -1,
  height: -1
});
flutterRenderer.setTextureBackGroundPixelMap(textureId, pixelMap);
```

这段代码中：
1. 使用 `AVImageGenerator` 获取视频的第一帧图像。
2. 使用 `flutterRenderer.setTextureBackGroundPixelMap` 方法将这帧图像设置为纹理的背景图像。

### 设置纹理的背景颜色和背景图像
在创建视频播放器时，可以同时设置纹理的背景颜色和背景图像，确保视频加载之前有一个合适的显示效果。

```dart
flutterRenderer.setTextureBackGroundColor(textureId, 0xFF0000FF);  // 红色背景
flutterRenderer.setTextureBackGroundPixelMap(textureId, pixelMap);  // 第一帧图像
```

## 常见用例

1. **视频加载前的占位背景**  
   在视频播放器初始化时，使用背景颜色或背景图像填充纹理，以确保用户在视频加载期间不会看到空白界面。

2. **显示加载状态**  
   在等待视频加载和渲染时，可以使用预设的背景颜色或图像表示加载状态，提升用户体验。

3. **自定义视频背景**  
   可以通过背景图像或颜色定制播放器的外观，增强视觉效果。

## 代码使用示例

在三方库[video_player_ohos](https://gitcode.com/openharmony-tpc/flutter_packages/tree/master/packages/video_player/video_player_ohos)中的[`VideoPlayerApiImpl.ets`](https://gitcode.com/openharmony-tpc/flutter_packages/blob/master/packages/video_player/video_player_ohos/ohos/src/main/ets/components/videoplayer/VideoPlayerApiImpl.ets)中，`create` 方法中创建了 `AVImageGenerator` 和 `AVMetadataExtractor` 来获取视频的元数据和图像数据。如果视频资源来自资产或本地文件，则第一帧会作为背景设置。

```dart
if (asset != null) {
  Log.i(TAG, "asset create called, asset is" + asset);
  let avMetaExtractor = await media.createAVMetadataExtractor();
  avMetaExtractor.fdSrc = await this.getContext().resourceManager.getRawFd("flutter_assets/" + asset);
  let mateData = await avMetaExtractor.fetchMetadata();
  if (mateData.hasVideo == CommonConstants.YES) {
    let avImageGenerator = await media.createAVImageGenerator();
    Log.i(TAG, "asset video create");
    avImageGenerator.fdSrc = await this.getContext().resourceManager.getRawFd("flutter_assets/" + asset);
    let pixelMap = await avImageGenerator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, {
      width: -1,
      height: -1
    });
    this.pixelMaps.set(JSON.stringify(arg), pixelMap);
    avImageGenerator.release();
    flutterRenderer.setTextureBackGroundPixelMap(textureId, this.pixelMaps.get(JSON.stringify(arg)));
  }
  avMetaExtractor.release();
} else if (uri != null && uri.startsWith("fd://")) {
  Log.i(TAG, "local create called, file is" + uri);
  let avMetaExtractor = await media.createAVMetadataExtractor();
  avMetaExtractor.fdSrc = {
    fd: Number.parseInt(uri.replace("fd://", ""))
  };
  let mateData = await avMetaExtractor.fetchMetadata();
  if (mateData.hasVideo == CommonConstants.YES) {
    let avImageGenerator = await media.createAVImageGenerator();
    Log.i(TAG, "local video create");
    avImageGenerator.fdSrc = {
      fd: Number.parseInt(uri.replace("fd://", ""))
    };
    let pixelMap = await avImageGenerator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, {
      width: -1,
      height: -1
    });
    this.pixelMaps.set(JSON.stringify(arg), pixelMap);
    avImageGenerator.release();
    flutterRenderer.setTextureBackGroundPixelMap(textureId, this.pixelMaps.get(JSON.stringify(arg)));
  }
  avMetaExtractor.release();
}
flutterRenderer.setTextureBackGroundColor(textureId, 0xFF0000FF); // 新增代码，展示setTextureBackGroundColor用法，设置红色背景
```

在这里`flutterRenderer.setTextureBackGroundPixelMap(textureId, pixelMap)` 会将从视频资源中提取的第一帧图像设置为纹理的背景。
新增的`flutterRenderer.setTextureBackGroundColor(textureId, 0xFF0000FF)` 会将从红色设置为纹理的背景色。

## 注意事项
- **纹理 ID**: 确保在调用这些方法之前已经为纹理分配了有效的 `textureId`。
- **内存管理**: 使用 `setTextureBackGroundPixelMap` 设置图像后，确保适当管理内存，避免内存泄漏。
- **视频资源**: 确保资源路径（如资产路径或本地路径）正确，确保能够成功加载视频文件并提取图像。

## 总结
`flutterRenderer.setTextureBackGroundColor` 和 `flutterRenderer.setTextureBackGroundPixelMap` 方法是 Flutter 视频播放器插件中非常实用的功能，它们允许开发者在视频加载期间自定义纹理的显示效果。通过设置背景颜色或图像，开发者能够提升用户体验，确保在视频内容渲染之前显示合适的界面。

## 功能需求背景和困难
目前 Flutter 外接纹理默认第一帧固定为白色背景，但对于视频等内容，默认白色背景不符合需求。具体来说，有些业务需要白色背景显示，但其他业务可能需要黑色或者其它颜色的背景显示。因此，固定为白色背景的实现无法满足所有业务场景，尤其是视频类业务。

## 预期
为了支持更多场景，应允许通过 Texture 容器的背景色控制或者提供一个设置背景色的接口。这样，开发者可以根据需求动态设置纹理的背景颜色。

## iOS 和安卓对标方案
目前，iOS 和安卓默认第一帧的背景色为黑色。不过，考虑到先前的更改是将第一帧的背景色从黑色改为白色，提供一个用户可自定义背景颜色的能力显得更加合理。这样不仅保留了对旧版的兼容性，也为业务需求提供了更多的灵活性。
