import 'dart:ffi';

import 'package:flutter/foundation.dart';

typedef LibraryLoader = DynamicLibrary Function();

DynamicLibrary loadOhosSqlite() {
  try {
    final processLib = DynamicLibrary.process();
    if (processLib.providesSymbol('sqlite3_version')) {
      debugPrint('[SQLite Loader] 使用 DynamicLibrary.process() 提供的内置 sqlite3');
      return processLib;
    }
  } catch (_) {
    // 忽略，继续尝试候选路径
  }

  try {
    final execLib = DynamicLibrary.executable();
    if (execLib.providesSymbol('sqlite3_version')) {
      debugPrint('[SQLite Loader] 使用 DynamicLibrary.executable() 提供的 sqlite3');
      return execLib;
    }
  } catch (_) {
    // 忽略
  }

  const candidates = <String>[
    'libsqlite3z.so',
    'libsqlite3.so',
    'libsqlite3_ndk.z.so',
    'libsqlite3_ndk.so',
    'libsqlite.z.so',
    'libsqlite.so',
    '/system/lib64/libsqlite3z.so',
    '/system/lib/libsqlite3z.so',
    '/system/lib64/libsqlite3.so',
    '/system/lib/libsqlite3.so',
    '/system/lib64/libsqlite3_ndk.z.so',
    '/system/lib/libsqlite3_ndk.z.so',
    '/system/lib64/libsqlite3_ndk.so',
    '/system/lib/libsqlite3_ndk.so',
    '/system/lib64/libsqlite.so',
    '/system/lib/libsqlite.so',
  ];

  for (final path in candidates) {
    try {
      debugPrint('[SQLite Loader] 尝试加载: $path');
      return DynamicLibrary.open(path);
    } catch (_) {
      continue;
    }
  }

  throw UnsupportedError('未找到可用的 SQLite 动态库 (HarmonyOS)');
}
