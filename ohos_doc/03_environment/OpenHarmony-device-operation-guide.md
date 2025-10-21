## OpenHarmony Device Operation Guide

1. Mount the Disk:`hdc target mount`.

2. Modify the Sandbox Configuration `/system/ets/sandbox/appdata-sanbox.json`,search for the keyword `/system/lib` ,and add the following configuration for `/system/lib64` in the same section.
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

3. Create a Project：`flutter create --platforms ohos <projectName>`.

4. Compile and Run.

   Compile a Release Package：`flutter build hap –no-tree-shake-icons`,open the OHOS project in DevEco Studio,navigate to the file `oh_modules\.ohpm\@ohos+flutter_ohos@xxx\oh_modules\@ohos\flutter_ohos\src\main\ets\view\FlutterView.ets`, comment out the specified code section,install and run the project on the device.
      
   ```
   // this.mainWindow?.on('windowStatusChange', this.windowStatusChangeCallback);
   ```