# ohos Running


## Runtime Error Occurs After a OpenHarmony Flutter Application Is Compiled
Symptom:<br>A runtime error occurs after an OpenHarmony Flutter application is compiled.

Error:
```
com.wit.appzoo_flutter_v2 is about to exit due to RuntimeError
Error type:ReferenceError
Error name:ReferenceError
Error message:cannot find record 'pkg_modules/.ohpm/connectivity_plus@fhy6p0gmf3puymhvkbu4hxvnutt4mn48tk2kirtanmi=/pkg_modules/connectivity_plus/index', please check the request path.'/data/storage/el1/bundle/entry/ets/modules.abc'.
Stacktrace:
SourceMap is not initialized yet
#00 pc 00000000005fcc0c /system/lib64/platformsdk/libark_jsruntime.so(5144aa99644b9dba57555adfb9e0ede6)
#01 pc 00000000005fd128 /system/lib64/platformsdk/libark_jsruntime.so(5144aa99644b9dba57555adfb9e0ede6)
#02 pc 00000000002ac540 /system/lib64/platformsdk/libark_jsruntime.so(5144aa99644b9dba57555adfb9e0ede6)
```
Possible causes:
**/data/storage/el1/bundle/entry/ets/modules.abc** may not run properly due to SDK and image version mismatch. In this case, you are advised to use the SDK that matches the mobile phone image version. Provide the current mobile phone version and DevEco Studio version to us so that we can help you fix this issue.
If the versions are matched, provide the complete logs.

## After the app package is successfully installed, the app crashes when open it
Log information:
```
#20 at attachToNative (entry|@ohos/flutter_ohos|1.0.0-115ba6b8be|src/main/ets/embedding/engine/FlutterNapi.ts:60:1)
#21 at attachToNapi (entry|@ohos/flutter_ohos|1.0.0-115ba6b8be|src/main/ets/embedding/engine/FlutterEngine.ts:97:1)
#22 at init (entry|@ohos/flutter_ohos|1.0.0-115ba6b8be|src/main/ets/embedding/engine/FlutterEngine.ts:88:1)
```
Problem analysis: The online package uses the debug version of flutter.har, in which case this error message will appear.

Solution: It is recommended to repackage the release version of flutter.har before going live. Execute the following command：
```
flutter build hap --release
```