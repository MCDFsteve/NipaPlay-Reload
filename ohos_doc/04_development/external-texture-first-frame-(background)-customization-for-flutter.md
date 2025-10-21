
# External Texture First Frame (Background) Customization for Flutter

## Overview
In this Flutter plugin, the `flutterRenderer.setTextureBackGroundColor` and `flutterRenderer.setTextureBackGroundPixelMap` methods are used to set the background color and content of the video player texture. The background color and texture image can be set before the video is loaded or played, ensuring that the user sees an appropriate background while waiting for the video to render.

## `flutterRenderer` Type
`flutterRenderer` is an instance of `TextureRegistry`, which is obtained through the `FlutterState` class. The `FlutterState` class contains two important members:
- **`binaryMessenger`** (`BinaryMessenger`): Used for message passing between Flutter and the engine.
- **`textureRegistry`** (`TextureRegistry`): Used to manage textures and register new textures.

### `FlutterState` Class
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

Through the `FlutterState.getTextureRegistry()` method, you can access `flutterRenderer`, which is an instance of `TextureRegistry`, and it can be used to manage and register video player textures.

## Method Signatures

### `flutterRenderer.setTextureBackGroundColor`
```dart
flutterRenderer.setTextureBackGroundColor(int textureId, int color)
```

- **`textureId`** (`int`): The ID of the texture used to identify which texture to set the background color for.
- **`color`** (`int`): The background color value, using the 32-bit hexadecimal format `0xAABBGGRR`.

### `flutterRenderer.setTextureBackGroundPixelMap`
```dart
flutterRenderer.setTextureBackGroundPixelMap(int textureId, image.PixelMap pixelMap)
```

- **`textureId`** (`int`): The ID of the texture used to identify which texture to set the image for.
- **`pixelMap`** (`image.PixelMap`): A `PixelMap` object containing image data to be used as the background image for the texture.

## Key Features
1. **Set Background Color**  
   The `setTextureBackGroundColor` method is used to set the background color of the texture. Before the video is loaded, it provides a preset color for the texture, typically used for displaying a solid color background.

2. **Set Background Image**  
   The `setTextureBackGroundPixelMap` method allows you to set a video frame image or any image as the background of the texture, typically filling the texture with the first frame image when the video file is loaded.

## Example Code

### Set Background Color to Red
```dart
flutterRenderer.setTextureBackGroundColor(textureId, 0xFF0000FF);
```

In this example, the background color is set to red (`0xFF0000FF`), meaning:
- `FF` is the Alpha value, indicating fully opaque.
- `00` is the blue component, indicating no blue.
- `00` is the green component, indicating no green.
- `FF` is the red component, indicating maximum red.

### Set Background Image to the First Frame of the Video
```dart
let avImageGenerator = await media.createAVImageGenerator();
let pixelMap = await avImageGenerator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, {
  width: -1,
  height: -1
});
flutterRenderer.setTextureBackGroundPixelMap(textureId, pixelMap);
```

In this code:
1. Use `AVImageGenerator` to get the first frame image of the video.
2. Use `flutterRenderer.setTextureBackGroundPixelMap` to set this frame image as the texture background.

### Set Both Background Color and Image for the Texture
When creating the video player, you can set both the background color and the background image for the texture to ensure an appropriate display before the video loads.

```dart
flutterRenderer.setTextureBackGroundColor(textureId, 0xFF0000FF);  // Red background
flutterRenderer.setTextureBackGroundPixelMap(textureId, pixelMap);  // First frame image
```

## Common Use Cases

1. **Placeholder Background Before Video Loads**  
   Use the background color or image to fill the texture while the video player initializes, ensuring that users do not see a blank screen during video loading.

2. **Displaying Loading Status**  
   While waiting for the video to load and render, you can use a preset background color or image to indicate the loading state, enhancing the user experience.

3. **Custom Video Background**  
   You can customize the appearance of the player by using background images or colors, enhancing the visual effect.

## Code Usage Example

In the third-party library [video_player_ohos](https://gitcode.com/openharmony-tpc/flutter_packages/tree/master/packages/video_player/video_player_ohos), in the [`VideoPlayerApiImpl.ets`](https://gitcode.com/openharmony-tpc/flutter_packages/blob/master/packages/video_player/video_player_ohos/ohos/src/main/ets/components/videoplayer/VideoPlayerApiImpl.ets) class, the `create` method uses `AVImageGenerator` and `AVMetadataExtractor` to fetch video metadata and image data. If the video resource is from assets or a ...

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
flutterRenderer.setTextureBackGroundColor(textureId, 0xFF0000FF); // New code, demonstrating the usage to set the red background
```

Here, `flutterRenderer.setTextureBackGroundPixelMap(textureId, pixelMap)` sets the first frame image extracted from the video resource as the background of the texture.
The newly added `flutterRenderer.setTextureBackGroundColor(textureId, 0xFF0000FF)` sets the background color of the texture to red.

## Notes
- **Texture ID**: Ensure that the texture has a valid `textureId` before calling these methods.
- **Memory Management**: After setting the image with `setTextureBackGroundPixelMap`, ensure proper memory management to avoid memory leaks.
- **Video Resources**: Ensure that the resource paths (e.g., asset or local path) are correct and the video file can be successfully loaded and extracted.

## Summary
The `flutterRenderer.setTextureBackGroundColor` and `flutterRenderer.setTextureBackGroundPixelMap` methods are very useful in the Flutter video player plugin. They allow developers to customize the display effect of the texture during video loading, ensuring a proper interface before the video content is rendered.

## Functional Requirements Background and Challenges
Currently, Flutter external textures default to a white background for the first frame. However, for video and other content, the default white background does not meet the needs. Specifically, some business scenarios require a white background, but others may need black or different colored backgrounds. Therefore, the fixed white background implementation cannot meet all business scenarios, especially for video-based applications.

## Expected Outcome
To support more scenarios, it is expected to control the background color of the texture container or provide an interface to set the background color. This allows developers to dynamically set the texture's background color based on their needs.

## iOS and Android Benchmarking
Currently, iOS and Android default to a black background for the first frame. However, considering the previous change from black to white, it is more reasonable to provide users with the ability to customize the background color. This not only preserves compatibility with older versions but also offers more flexibility for business requirements.
