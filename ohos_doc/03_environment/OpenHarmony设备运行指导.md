## OpenHarmony设备运行指导

1. 挂载磁盘：`hdc target mount`。

2. 修改沙箱文件 `/system/ets/sandbox/appdata-sanbox.json`，搜索 `/system/lib` 关键字，在相同位置加上 `/system/lib64` 配置。
   ```
   {
      "src-path": "/system/lib64",
      "sandbox-path": "/system/lib64",
      "sandbox-flags": [
         "bind",
         "rec"
      ],
      "check-action-status": "false"
   }
   ```   

3. 创建工程：`flutter create --platforms ohos <projectName>`。

4. 编译运行。

   编译release包：`flutter build hap –no-tree-shake-icons`，使用deveco工具打开ohos工程，找到文件`oh_modules\.ohpm\@ohos+flutter_ohos@xxx\oh_modules\@ohos\flutter_ohos\src\main\ets\view\FlutterView.ets`， 注释以下代码后，安装运行到设备中。
      
   ```
   // this.mainWindow?.on('windowStatusChange', this.windowStatusChangeCallback);
   ```
