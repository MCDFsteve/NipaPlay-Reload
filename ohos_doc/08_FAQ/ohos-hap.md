# ohos Application Compilation

## Configure aliases to simplify compilation instructions during routine development.

Configure aliases in the configuration file of the environment variables to simplify the instructions used for OpenHarmony Flutter.

- For Windows, use `Git Bash` to execute common Linux instructions. (How to use: Right-click the blank area in the file manager and choose **Git Bash Here** from the shortcut menu.)
- For Linux, modify `~/.bash_profile`.
- For macOS, modify `~/.bash_profile` and add `source ~/.bash_profile` to `~/.zshrc`.

```sh
# --The --local-engine parameter is optional and points to the self-compiled engine product. You are advised to use this parameter in the Linux or macOS environment.
export ENGINE_DIR=~/ohos/engine
export ENGINE_DEBUG=$ENGINE_DIR/src/out/ohos_debug_unopt_arm64
export ENGINE_PROFILE=$ENGINE_DIR/src/out/ohos_profile_arm64
export ENGINE_RELEASE=$ENGINE_DIR/src/out/ohos_release_arm64

alias fbuildD="flutter build hap --local-engine=$ENGINE_DEBUG --debug"
alias fbuildP="flutter build hap --local-engine=$ENGINE_PROFILE --profile"
alias fbuildR="flutter build hap --local-engine=$ENGINE_RELEASE --release"
alias frunD="flutter run -d $(hdc list targets) --local-engine=$ENGINE_DEBUG --debug"
alias frunP="flutter run -d $(hdc list targets) --local-engine=$ENGINE_PROFILE --profile"
alias frunR="flutter run -d $(hdc list targets) --local-engine=$ENGINE_RELEASE --release"
```

How to use:

After the configuration, reopen the terminal window. Now you can use the aliases when compiling or running the project.

```sh
flutter create hello --platforms ohos
cd hello
# Compile the debug version.
fbuildD
# Run the debug version.
frunD
```

## A Flutter application crashes in the release mode, but performs properly in the dev mode.

Problem analysis:

The **flutter.har** file of the debug version is used.

Solution:

Repackage the **flutter.har** file of the release version.

## White screen occurs after the application is compiled and installed.

Error log:

```log
Reason:Signal:SIGSEGV(SEGV_MAPERR)@0x00000086e3272bf8
LastFatalMessage:Thread:547846269584[FATAL:flutter/runtime/dart_vm_initializer.cc] Error while initializing the Dart VM: Wrong full snapshot version, expected '8af474944053df1f0a3be6e6165fa7cf' found 'adb4292f3ec25074ca70abcd2d5c7251'
```

Problem analysis:

Engine products mismatch the running mode, causing a white screen.

Solution:

In the running or compilation instructions, make sure the engine products match the running mode. Reference:

```sh
flutter run -d --debug
flutter run -d --release
flutter run -d --profile
```

## A Flutter plugin before reconstruction uses the reconstructed plugin library, causing an error in compiling applications.

Error log:

```log
Oops; flutter has exited unexpectedly: "type 'Null' is not a subtype of type 'List<dynamic>' in type cast".
```

Solution:
Update **flutter_flutter** to the latest version of master or dev.(45bd5e627e1f1e5f4d335f205781565f576acc60, 2024-05-10)

## Dependency conflicts are reported during the running of flutter pub get.

Error log:

```log
Resolving dependencies...
Because flutter_cache_manager >=3.0.0-nullsafety.0 <3.3.2 depends on path_provider from hosted and flutter_cache_manager depends on path_provider from git, flutter_cache_manager >=3.0.0-nullsafety.0 <3.3.2 forbidden.
So bedause xxx depends on flutter_cache_manager 3.3.1, version solving failed.
pub get failed
...
exit code: 1
```

Solution:

Use `dependency_overrides` to eliminate dependency conflicts.

```yaml
dependencies:
  flutter:
    sdk: flutter
dependency_overrides:
  path_provider:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/path_provider/path_provider
  path_provider_ohos:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/path_provider/path_provider_ohos
```

## The SDK license agreement is not accepted.

Error log:

```log
hvigor install success.
> hvigor ERROR: Cause: The SDK license agreement is not accepted.
```

Problem analysis:<br>The structure of the ohos project is in API version 11, but the SDK used is in API version 12.

Solution:<br>Upgrade the ohos project structure to API version 12.

Steps:
1. DevEco Studio -> Migrate Assistant -> 5.0.0 -> Migrate
2. DevEco Studio -> File -> Project Structure -> Compatible SDK -> 5.0.0(12)

## The versionName field in the app.json file is reset when the flutter build hap -release command is used to compile the version.
Background:
Check the **versionName** field in the **app.json** file and execute the **flutter build hap -release** command to generate a package.

Symptom:<br>The secondary field is reset to **1.0.0** again.

Cause:<br>This version number is used by default in build.

Solution:<br>Specify **versionName** and **versionCode** in build.

Reference:<br>flutter build hap --build-name=4.0.3 --build-number=10000
