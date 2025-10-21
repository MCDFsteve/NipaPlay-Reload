# 调试dart代码

- ets 代码使用 DevEco-Studio 进行调试。
- dart 代码可以使用 vscode 和 Android Studio 进行调试，点击运行按钮启动调试即可。

# 指定本地引擎调试 dart 代码

  调试时需要加上参数，如： `--local-engine=/Users/xxx/ohos/engine/src/out/ohos_debug_unopt_arm64`。

## 使用 vscode 调试 dart 代码

在项目目录下创建文件 `.vscode/launch.json`，并添加参数，如下所示：

```
{
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [
        {
            "name": "flutter_sample",
            "request": "launch",
            "type": "dart",
            "args": [
                "--local-engine=/Users/xxx/work/engine_build/engine/src/out/ohos_debug_unopt_arm64"
            ]
        },
        {
            "name": "flutter_sample (profile mode)",
            "request": "launch",
            "type": "dart",
            "flutterMode": "profile",
            "args": [
                "--local-engine=/Users/xxx/work/engine_build/engine/src/out/ohos_profile_arm64"
            ]
        },
        {
            "name": "flutter_sample (release mode)",
            "request": "launch",
            "type": "dart",
            "flutterMode": "release",
            "args": [
                "--local-engine=/Users/xxx/work/engine_build/engine/src/out/ohos_release_arm64"
            ]
        }
    ]
}
```

修改完成后，就可以调试dart代码了。

## 使用 Android Studio 调试 dart 代码

![](../media/06/06_android_run_config.png)

参数设置完成后，就可以调试dart代码了。
