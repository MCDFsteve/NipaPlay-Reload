import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/pages/media_library_page.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/dandanplay_remote_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/library_management_tab.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';

class MaterialMediaLibraryTabs extends StatefulWidget {
  final int initialIndex;
  final ValueChanged<WatchHistoryItem> onPlayEpisode;
  final int mediaLibraryVersion;

  const MaterialMediaLibraryTabs({
    super.key,
    this.initialIndex = 0,
    required this.onPlayEpisode,
    required this.mediaLibraryVersion,
  });

  @override
  State<MaterialMediaLibraryTabs> createState() =>
      _MaterialMediaLibraryTabsState();
}

class _MaterialTabSpec {
  final String label;
  final Widget child;

  const _MaterialTabSpec({
    required this.label,
    required this.child,
  });
}

class _MaterialMediaLibraryTabsState extends State<MaterialMediaLibraryTabs>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  TabChangeNotifier? _tabChangeNotifierRef;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabController.addListener(_handleTabChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setupSubTabListener();
      _applyPendingSubTabChange();
    });
  }

  @override
  void dispose() {
    try {
      _tabChangeNotifierRef?.removeListener(_onSubTabChangeRequested);
    } catch (_) {}
    _tabChangeNotifierRef = null;

    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) return;
    if (_currentIndex == _tabController.index) return;
    setState(() {
      _currentIndex = _tabController.index;
    });
  }

  void _setupSubTabListener() {
    try {
      _tabChangeNotifierRef =
          Provider.of<TabChangeNotifier>(context, listen: false);
      _tabChangeNotifierRef?.addListener(_onSubTabChangeRequested);
    } catch (_) {
      _tabChangeNotifierRef = null;
    }
  }

  void _onSubTabChangeRequested() {
    final notifier = _tabChangeNotifierRef;
    if (notifier == null) return;
    final targetIndex = notifier.targetMediaLibrarySubTabIndex;
    if (targetIndex == null) return;

    final int clampedIndex =
        targetIndex.clamp(0, _tabController.length - 1);
    if (clampedIndex != _tabController.index) {
      _tabController.animateTo(clampedIndex);
    }

    notifier.clearSubTabIndex();
  }

  void _applyPendingSubTabChange() {
    final notifier = _tabChangeNotifierRef;
    if (notifier?.targetMediaLibrarySubTabIndex == null) return;
    _onSubTabChangeRequested();
  }

  void _replaceTabController(int length) {
    final safeLength = length.clamp(1, 99);
    if (_tabController.length == safeLength) return;

    final nextIndex = _currentIndex.clamp(0, safeLength - 1);

    final old = _tabController;
    old.removeListener(_handleTabChange);

    _tabController = TabController(
      length: safeLength,
      vsync: this,
      initialIndex: nextIndex,
    );
    _tabController.addListener(_handleTabChange);
    old.dispose();

    _currentIndex = nextIndex;
  }

  List<_MaterialTabSpec> _buildTabs({
    required bool isJellyfinConnected,
    required bool isEmbyConnected,
    required bool hasSharedRemoteHosts,
    required bool isDandanConnected,
  }) {
    final tabs = <_MaterialTabSpec>[
      _MaterialTabSpec(
        label: '本地媒体库',
        child: RepaintBoundary(
          child: MediaLibraryPage(
            key: ValueKey('mediaLibrary_${widget.mediaLibraryVersion}'),
            onPlayEpisode: widget.onPlayEpisode,
          ),
        ),
      ),
      _MaterialTabSpec(
        label: '库管理',
        child: RepaintBoundary(
          child: LibraryManagementTab(onPlayEpisode: widget.onPlayEpisode),
        ),
      ),
    ];

    if (hasSharedRemoteHosts) {
      tabs.add(
        _MaterialTabSpec(
          label: '共享媒体',
          child: RepaintBoundary(
            child: SharedRemoteLibraryView(onPlayEpisode: widget.onPlayEpisode),
          ),
        ),
      );
    }

    if (isDandanConnected) {
      tabs.add(
        _MaterialTabSpec(
          label: '弹弹play',
          child: RepaintBoundary(
            child: DandanplayRemoteLibraryView(
              onPlayEpisode: widget.onPlayEpisode,
            ),
          ),
        ),
      );
    }

    if (isJellyfinConnected) {
      tabs.add(
        _MaterialTabSpec(
          label: 'Jellyfin',
          child: RepaintBoundary(
            child: NetworkMediaLibraryView(
              serverType: NetworkMediaServerType.jellyfin,
              onPlayEpisode: widget.onPlayEpisode,
            ),
          ),
        ),
      );
    }

    if (isEmbyConnected) {
      tabs.add(
        _MaterialTabSpec(
          label: 'Emby',
          child: RepaintBoundary(
            child: NetworkMediaLibraryView(
              serverType: NetworkMediaServerType.emby,
              onPlayEpisode: widget.onPlayEpisode,
            ),
          ),
        ),
      );
    }

    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<JellyfinProvider, EmbyProvider, SharedRemoteLibraryProvider,
        DandanplayRemoteProvider>(
      builder: (context, jellyfinProvider, embyProvider, sharedProvider,
          dandanProvider, _) {
        final tabs = _buildTabs(
          isJellyfinConnected: jellyfinProvider.isConnected,
          isEmbyConnected: embyProvider.isConnected,
          hasSharedRemoteHosts: sharedProvider.hasReachableActiveHost,
          isDandanConnected: dandanProvider.isConnected,
        );

        _replaceTabController(tabs.length);

        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 1,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: tabs.map((t) => Tab(text: t.label)).toList(),
              ),
            ),
            Expanded(
              child: SwitchableView(
                // 媒体库页面较重，强制禁用 TabBarView 动画以避免多页同时渲染。
                enableAnimation: false,
                currentIndex: _currentIndex,
                controller: _tabController,
                children: tabs.map((t) => t.child).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}
