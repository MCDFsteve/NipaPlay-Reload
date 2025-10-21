# Harmony 播放内核对接说明

本文档记录 Flutter 侧新增加的 `OhosPlayerAdapter` 与 OpenHarmony 原生 AVPlayer 的通道协议，便于 ArkTS 团队按照统一接口完成桥接。

## MethodChannel

Flutter 端使用的 MethodChannel 基于 `nipaplay/ohos_player/<playerId>` 命名空间，`playerId` 由 Dart 侧自动生成。

| 方法名 | 入参 | 说明 |
| --- | --- | --- |
| `create` | `{ playerId }` | 创建/复用原生播放器实例，应返回 `textureId` 与 `eventChannel` 名称 |
| `setMedia` | `{ playerId, path, type }` | 绑定媒体资源，`type` 取值 `video/audio/subtitle/unknown` |
| `prepare` | `{ playerId }` | 预加载媒体，完成后可返回最新媒体信息 |
| `ensureTexture` | `{ playerId }` | 确保纹理有效，返回 `textureId`（可选） |
| `play` / `pause` / `stop` | `{ playerId }` | 播放控制 |
| `seek` | `{ playerId, position }` | 毫秒 seek |
| `setVolume` | `{ playerId, value }` | 音量 0-1 |
| `setPlaybackRate` | `{ playerId, rate }` | 播放速度 |
| `setVideoSurfaceSize` | `{ playerId, width?, height? }` | 纹理尺寸变化 |
| `setDecoders` | `{ playerId, type, decoders }` | 预留给解码器策略 |
| `selectAudioTracks` / `selectSubtitleTracks` | `{ playerId, tracks }` | 切换音轨/字幕 |
| `setProperty` | `{ playerId, key, value }` | 通用属性设置 |
| `snapshot` | `{ playerId, width, height }` | 可选实现，返回 `{ width, height, bytes }` |
| `dispose` | `{ playerId }` | 释放资源 |

返回 `textureId` 时需保证已经在原生端注册到 Flutter `SurfaceTexture`。未实现的方法可以返回 `null`，Flutter 端会采用安全兜底。

## EventChannel

`create` 方法期望返回 `eventChannel` 名称（字符串），若未返回则默认 `nipaplay/ohos_player/events/<playerId>`。事件标准化如下：

| type | payload | 说明 |
| --- | --- | --- |
| `state` | `{ value: 'playing / paused / stopped' }` | 播放状态变更 |
| `position` | `{ position: number }` | 毫秒进度更新 |
| `texture` | `{ textureId: number }` | 纹理 ID 变化 |
| `mediaInfo` | `{ info: {...} }` | 媒体信息（见下文数据结构） |
| `volume` | `{ value: number }` | 音量反馈 |
| `playbackRate` | `{ value: number }` | 播放速度反馈 |
| `subtitleTracks` | `{ tracks: number[] }` | 当前字幕轨道 |
| `audioTracks` | `{ tracks: number[] }` | 当前音轨 |

### 媒体信息结构

```json
{
  "duration": number, // 毫秒
  "video": [
    {
      "codec": { "width": number, "height": number, "name": string },
      "codecName": string
    }
  ],
  "audio": [
    {
      "codec": { "name": string, "bitRate": number, "channels": number, "sampleRate": number },
      "title": string,
      "language": string,
      "metadata": { "key": "value" },
      "rawRepresentation": string
    }
  ],
  "subtitle": [
    {
      "title": string,
      "language": string,
      "metadata": { "key": "value" },
      "rawRepresentation": string
    }
  ],
  "error": string? // 可选，返回友好错误信息
}
```

原生侧按需填充即可，缺失字段 Dart 会保留旧值。

## 平台特性

- Flutter 分支会在 OpenHarmony 环境下强制选择 `Harmony Player` 内核，设置页已隐藏其他内核选项。
- Anime4K 着色器仅对 MediaKit 开放，Harmony 平台已自动屏蔽。
- 若 `create` 抛出 `MissingPluginException`，Dart 端会保持安全状态并记录日志。

## 开发建议

1. ArkTS 侧推荐使用 `AVPlayer` + `SurfaceTexture` 输出。
2. 结合 `flutter/packages` 提供的 `MethodChannel`/`Texture` 示例，可快速搭建桥接。
3. 建议实现基础事件（state/position/texture），其它事件可按功能迭代补充。
4. 如需逐帧截图，可使用 `PixelMap` 转 `Uint8Array` 后通过 `ByteData` 回传。

完成原生实现后无需修改 Flutter 端代码，只需确保 MethodChannel 契约保持一致。
