# ohos运行相关问题

## 编译OpenHarmony后运行出现运行时错误/data/storage/el1/bundle/entry/ets/modules.abc
问题现象：flutter编译OpenHarmony后运行出现运行时错误

报错信息：
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
可能原因：
/data/storage/el1/bundle/entry/ets/modules.abc 可能是SDK与镜像不匹配导致abc文件无法正常运行，该现象根本原因是SDK工具与镜像版本不匹配，推荐使用匹配的SDK与手机镜像版本；请提供当前手机版本 和 ide版本截图。
若版本是匹配的，请提供完整日志来。

## app包安装成功后，运行闪退

日志信息:

```log
#20 at attachToNative (entry|@ohos/flutter_ohos|1.0.0-115ba6b8be|src/main/ets/embedding/engine/FlutterNapi.ts:60:1)
#21 at attachToNapi (entry|@ohos/flutter_ohos|1.0.0-115ba6b8be|src/main/ets/embedding/engine/FlutterEngine.ts:97:1)
#22 at init (entry|@ohos/flutter_ohos|1.0.0-115ba6b8be|src/main/ets/embedding/engine/FlutterEngine.ts:88:1)
```

问题分析：上线包使用了debug版本的flutter.har，这种情况下就会出现这个报错信息。

解决方案：建议上线前重新打包release版本的flutter.har，执行命令 `flutter build hap --release`。
