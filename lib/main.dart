import 'dart:async';
import 'package:socks5_proxy/socks_client.dart';
import 'package:flutter/physics.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/scheduler.dart' show Ticker;
import 'dart:ui'; // Used for ImageFilter
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Used for Clipboard
import 'package:macos_ui/macos_ui.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'harbor_ui.dart';
part 'mapping_interactions.dart';
part 'key_management.dart';
part 'settings.dart';
part 'updates.dart';
part 'proxy.dart';
part 'ssh_activity.dart';
part 'advanced_options.dart';

// ----------------------
// 1. App Entry Point
// ----------------------
void main() {
  runApp(const AppRoot());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!Platform.isMacOS) return;
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    await const MethodChannel(
      'harbor/files',
    ).invokeMethod<void>('firstFrameReady');
  });
}

// A scroll behavior that never renders a scrollbar.
class NoScrollbarBehavior extends MacosScrollBehavior {
  const NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // Return the child as-is, without wrapping it in a Scrollbar.
  }
}

/// A lightweight resizable sidebar that does **not** create its own scrollable.
/// This avoids the extra (and hard-to-remove) scrollbar that `Sidebar` from
/// macos_ui can introduce when you also scroll your own list.
class ResizableSidebar extends StatefulWidget {
  final double minWidth;
  final double startWidth;
  final double maxWidth;
  final Widget child;
  final ValueChanged<double>? onWidthChanged;

  const ResizableSidebar({
    super.key,
    required this.minWidth,
    required this.startWidth,
    required this.maxWidth,
    required this.child,
    this.onWidthChanged,
  });

  @override
  State<ResizableSidebar> createState() => _ResizableSidebarState();
}

class _ResizableSidebarState extends State<ResizableSidebar> {
  late double _width;

  @override
  void initState() {
    super.initState();
    _width = widget.startWidth.clamp(widget.minWidth, widget.maxWidth);
  }

  @override
  void didUpdateWidget(covariant ResizableSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep width within new constraints if they changed.
    _width =
        (oldWidget.startWidth != widget.startWidth ? widget.startWidth : _width)
            .clamp(widget.minWidth, widget.maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: HarborColors.of(context).sidebar,
      child: SizedBox(
        width: _width,
        child: Row(
          children: [
            Expanded(child: widget.child),
            // Drag handle
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () {
                  setState(
                    () =>
                        _width = 240.0.clamp(widget.minWidth, widget.maxWidth),
                  );
                  widget.onWidthChanged?.call(_width);
                },
                onHorizontalDragEnd: (_) => widget.onWidthChanged?.call(_width),
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _width = (_width + details.delta.dx).clamp(
                      widget.minWidth,
                      widget.maxWidth,
                    );
                  });
                },
                child: const SizedBox(
                  key: ValueKey('sidebar-resize-handle'),
                  width: 10,
                  height: double.infinity,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => SSHStore(),
    child: const HarborApplication(),
  );
}

class HarborApplication extends StatelessWidget {
  final Widget home;
  const HarborApplication({super.key, this.home = const MainWindow()});
  @override
  Widget build(BuildContext context) {
    final preferences = context.select<SSHStore, HarborPreferences>(
      (store) => store.preferences,
    );
    return MacosApp(
      title: 'Harbor SSH',
      scrollBehavior: const NoScrollbarBehavior(),
      theme: MacosThemeData.light().copyWith(
        canvasColor: const Color(0xFFF5F2ED),
        primaryColor: HarborColors(
          false,
          accentName: preferences.accent,
        ).accent,
      ),
      darkTheme: MacosThemeData.dark().copyWith(
        canvasColor: const Color(0xFF111B28),
        primaryColor: HarborColors(true, accentName: preferences.accent).accent,
      ),
      themeMode: preferences.theme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            disableAnimations:
                media.disableAnimations || preferences.reduceMotion,
          ),
          child: CupertinoTheme(
            data: CupertinoThemeData(
              brightness: MacosTheme.of(context).brightness,
              primaryColor: MacosTheme.of(context).primaryColor,
            ),
            child: home is MainWindow
                ? _HarborLaunchTransition(
                    child: _HarborUpdateNotice(
                      child: _HarborResourceWarmup(child: child!),
                    ),
                  )
                : child!,
          ),
        );
      },
      home: home,
    );
  }
}

class _HarborUpdateNotice extends StatelessWidget {
  final Widget child;
  const _HarborUpdateNotice({required this.child});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final update = store.availableUpdate;
    final colors = HarborColors.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (update != null &&
            (store.updateBusy ||
                store.updateError ||
                (update.build != store.preferences.ignoredUpdateBuild &&
                    update.build != store.skippedUpdateBuild)))
          Positioned(
            top: 44,
            right: 24,
            child: IgnorePointer(
              child: Container(
                width: 290,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  store.updateBusy || store.updateError
                      ? store.updateStatus
                      : '${update.version} is available.\nInstall from Settings → About.',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Keep the real interface visible behind the launch mark, including its theme.
class _HarborLaunchTransition extends StatefulWidget {
  final Widget child;
  const _HarborLaunchTransition({required this.child});
  @override
  State<_HarborLaunchTransition> createState() =>
      _HarborLaunchTransitionState();
}

class _HarborLaunchTransitionState extends State<_HarborLaunchTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) {
        await _controller.forward();
      }
      if (mounted) setState(() => _finished = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final remaining = _finished
            ? 0.0
            : 1 -
                  const Interval(
                    0.5,
                    1,
                    curve: Curves.easeInOut,
                  ).transform(_controller.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              enabled: !_finished,
              imageFilter: ImageFilter.blur(
                sigmaX: 14 * remaining,
                sigmaY: 14 * remaining,
              ),
              child: widget.child,
            ),
            if (!_finished)
              Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: colors.background.withValues(
                      alpha: 0.55 * remaining,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// Warm common panel layouts, painting and image decoding after the first window frame,
// rather than doing this work on the first keyboard shortcut.
class _HarborResourceWarmup extends StatefulWidget {
  final Widget child;
  const _HarborResourceWarmup({required this.child});
  @override
  State<_HarborResourceWarmup> createState() => _HarborResourceWarmupState();
}

class _HarborResourceWarmupState extends State<_HarborResourceWarmup> {
  bool warming = false;
  bool scheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (scheduled) return;
    scheduled = true;
    precacheImage(const AssetImage(_harborMarkAsset), context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => warming = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => warming = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // Paint behind the opaque main window: Offstage warms layout only,
      // leaving the first visible blur and glyph rasterization cold.
      if (warming)
        const IgnorePointer(
          child: ExcludeFocus(
            child: ExcludeSemantics(
              child: TickerMode(
                enabled: false,
                child: Row(
                  children: [
                    SizedBox(width: 240),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          HarborSettingsPage(),
                          Center(
                            child: RepaintBoundary(
                              child: QuickConnectSheet(autofocus: false),
                            ),
                          ),
                          Center(
                            child: HarborQuickConnectTransition(
                              animation: AlwaysStoppedAnimation(0.15),
                              child: QuickConnectSheet(autofocus: false),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      KeyedSubtree(
        key: const ValueKey('harbor-main-view'),
        child: widget.child,
      ),
    ],
  );
}

// ----------------------
// 2. Data Model
// ----------------------

class SSHHost {
  String hostAlias;
  String hostName;
  String user;
  String port;
  String identityFile;
  String proxyJump;

  List<String> localForwards;
  List<String> remoteForwards;
  String dynamicForward; // SOCKS5

  Map<String, String> advancedOptions;

  SSHHost({
    required this.hostAlias,
    this.hostName = '',
    this.user = '',
    this.port = '22',
    this.identityFile = '',
    this.proxyJump = '',
    this.dynamicForward = '',
    List<String>? localForwards,
    List<String>? remoteForwards,
    Map<String, String>? advancedOptions,
  }) : localForwards = localForwards ?? [],
       remoteForwards = remoteForwards ?? [],
       advancedOptions = advancedOptions ?? {};

  String toConfigBlock() {
    final buffer = StringBuffer();
    buffer.writeln('Host $hostAlias');
    if (hostName.isNotEmpty) buffer.writeln('  HostName $hostName');
    if (user.isNotEmpty) buffer.writeln('  User $user');
    if (port != '22' && port.isNotEmpty) buffer.writeln('  Port $port');
    if (identityFile.isNotEmpty) buffer.writeln('  IdentityFile $identityFile');
    if (proxyJump.isNotEmpty) buffer.writeln('  ProxyJump $proxyJump');
    if (dynamicForward.isNotEmpty) {
      buffer.writeln('  DynamicForward $dynamicForward');
    }

    for (var fwd in localForwards) {
      final parts = fwd.split(':');
      if (parts.length >= 2) {
        buffer.writeln('  LocalForward ${fwd.replaceFirst(':', ' ')}');
      } else {
        buffer.writeln('  LocalForward $fwd');
      }
    }

    for (final forward in remoteForwards) {
      buffer.writeln('  RemoteForward ${forward.replaceFirst(':', ' ')}');
    }

    advancedOptions.forEach((k, v) {
      buffer.writeln('  $k $v');
    });

    return buffer.toString();
  }

  String getPreviewCommand({
    List<String> networkArguments = const [],
    List<String> additionalArguments = const [],
  }) {
    String quote(String value) =>
        RegExp(r'^[A-Za-z0-9_./:@=,+-]+$').hasMatch(value)
        ? value
        : "'${value.replaceAll("'", "'\"'\"'")}'";
    final args = <String>[
      ...networkArguments,
      ...additionalArguments,
      if (port != '22') ...['-p', port],
      if (identityFile.isNotEmpty) ...[
        '-i',
        identityFile.startsWith('~/')
            ? '${Platform.environment['HOME']}/${identityFile.substring(2)}'
            : identityFile,
      ],
      if (proxyJump.isNotEmpty && networkArguments.isEmpty) ...[
        '-J',
        proxyJump,
      ],
      if (dynamicForward.isNotEmpty) ...['-D', dynamicForward],
      for (final forward in localForwards) ...['-L', forward],
      for (final forward in remoteForwards) ...['-R', forward],
      for (final entry in advancedOptions.entries) ...[
        '-o',
        '${entry.key}=${entry.value}',
      ],
      '--',
      '${user.isEmpty ? '' : '$user@'}${hostName.isEmpty ? hostAlias : hostName}',
    ];
    return 'ssh ${args.map(quote).join(' ')}';
  }
}

// ----------------------
// 3. Logic Core (Store)
// ----------------------

class ManagedMapping {
  final String id;
  String serverAlias;
  String type;
  String value;
  String group;
  List<String> tags;
  ManagedMapping({
    required this.id,
    required this.serverAlias,
    required this.type,
    required this.value,
    String group = '',
    Iterable<String> tags = const [],
  }) : group = group.trim(),
       tags = normalizeTags(tags);

  static List<String> normalizeTags(Iterable<String> tags) =>
      tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  Map<String, dynamic> toJson() => {
    'id': id,
    'server': serverAlias,
    'type': type,
    'value': value,
    'group': group,
    'tags': tags,
  };
  factory ManagedMapping.fromJson(Map<String, dynamic> data) => ManagedMapping(
    id: data['id'] as String,
    serverAlias: data['server'] as String,
    type: data['type'] as String,
    value: data['value'] as String,
    group: data['group'] is String ? data['group'] as String : '',
    tags: data['tags'] is List
        ? (data['tags'] as List).whereType<String>()
        : const [],
  );
}

/// Folder of timestamped config copies, kept beside the SSH config itself.
const _configArchiveFolder = 'config_bk';

/// Total size the archive folder may reach before the oldest copies are dropped.
const _configArchiveBudget = 10 * 1024 * 1024;

class SSHStore extends ChangeNotifier {
  HarborPreferences preferences = const HarborPreferences();
  bool preferencesLoaded = false;
  String applicationVersion = '1.0.5';
  void notifyUpdateListeners() => notifyListeners();
  HarborUpdate? availableUpdate;
  int? pendingUpdatePrompt;
  int? skippedUpdateBuild;
  void skipUpdatePrompt() {
    skippedUpdateBuild = pendingUpdatePrompt;
    pendingUpdatePrompt = null;
    notifyListeners();
  }

  Future<void> ignoreUpdatePrompt() async {
    final build = pendingUpdatePrompt;
    pendingUpdatePrompt = null;
    if (build != null) {
      await updatePreferences(preferences.copyWith(ignoredUpdateBuild: build));
    }
  }

  bool get shouldPromptForUpdate =>
      pendingUpdatePrompt != null &&
      pendingUpdatePrompt != skippedUpdateBuild &&
      pendingUpdatePrompt != preferences.ignoredUpdateBuild;

  Future<HttpClient> Function(Uri)? updateHttpClientFactory;
  bool updateBusy = false;
  bool updateError = false;
  String updateStatus = 'Check for new versions of Harbor.';
  String applicationBuild = '1';
  Future<void> updatePreferences(HarborPreferences value) {
    preferences = value;
    notifyListeners();
    return saveMetadata();
  }

  Future<void> clearRecentHosts() {
    recentHosts.clear();
    notifyListeners();
    return saveMetadata();
  }

  void recordRecentHost(SSHHost host) {
    if (!preferences.recordRecent) return;
    recentHosts.remove(host.hostAlias);
    recentHosts.insert(0, host.hostAlias);
    if (recentHosts.length > 12) {
      recentHosts.removeRange(12, recentHosts.length);
    }
  }

  List<String> terminalOpenArguments(String path) => [
    if (preferences.terminal != 'system') ...[
      '-a',
      preferences.terminal == 'iterm' ? 'iTerm' : 'Terminal',
    ],
    path,
  ];
  Future<void> loadApplicationInfo() async {
    try {
      final info = await const MethodChannel(
        'harbor/files',
      ).invokeMapMethod<String, String>('applicationInfo');
      if (info != null) {
        applicationVersion = info['version'] ?? applicationVersion;
        applicationBuild = info['build'] ?? applicationBuild;
        notifyListeners();
      }
    } on MissingPluginException {
      /* Widget previews use the source defaults. */
    }
  }

  Future<void> revealDataFile({bool sshConfig = false}) async {
    File? file = sshConfig
        ? configFile ?? File('${Platform.environment['HOME']}/.ssh/config')
        : _metadataFile;
    if (!sshConfig && (file == null || !await file.exists())) {
      await saveMetadata();
      file = _metadataFile;
    }
    if (file == null || !await file.exists()) {
      throw const FileSystemException('The file does not exist yet.');
    }
    final result = await Process.run('/usr/bin/open', ['-R', file.path]);
    if (result.exitCode != 0) throw Exception(result.stderr.toString().trim());
  }

  final List<ManagedMapping> mappings = [];
  final Set<String> mappingGroups = {};
  List<String> get mappingGroupNames => {
    ...mappingGroups,
    ...mappings.map((mapping) => mapping.group),
  }.where((name) => name.isNotEmpty).toList()..sort();

  Future<void> createMappingGroup(String name) async {
    final group = name.trim();
    if (group.isEmpty || group == 'Ungrouped') return;
    mappingGroups.add(group);
    notifyListeners();
    await saveMetadata();
  }

  Future<void> setMappingGroup(ManagedMapping mapping, String name) async {
    if (mapping.group.isNotEmpty) mappingGroups.add(mapping.group);
    mapping.group = name.trim();
    if (mapping.group.isNotEmpty) mappingGroups.add(mapping.group);
    notifyListeners();
    await saveMetadata();
  }

  /// Move the existing objects, preserving their processes, IDs and tags.
  Future<void> moveMappings(
    Iterable<ManagedMapping> selection,
    String group, {
    ManagedMapping? target,
    bool after = false,
  }) async {
    final wanted = selection.toSet();
    final moving = mappings.where(wanted.contains).toList();
    if (moving.isEmpty || wanted.contains(target)) return;
    if (target != null && !mappings.contains(target)) return;
    for (final rule in moving) {
      if (rule.group.isNotEmpty) mappingGroups.add(rule.group);
      rule.group = group.trim();
    }
    if (group.trim().isNotEmpty) mappingGroups.add(group.trim());
    mappings.removeWhere(wanted.contains);
    final index = target == null
        ? mappings.lastIndexWhere((rule) => rule.group == group.trim()) + 1
        : mappings.indexOf(target) + (after ? 1 : 0);
    mappings.insertAll(index, moving);
    notifyListeners();
    await saveMetadata();
  }

  Future<List<String>> startMappings(Iterable<ManagedMapping> selection) async {
    final rules = selection
        .where(
          (rule) =>
              mappings.contains(rule) &&
              !mappingRunning(rule) &&
              !mappingLoading(rule),
        )
        .toSet()
        .toList();
    final results = await Future.wait(
      rules.map((rule) async {
        final error = await toggleMapping(rule);
        return error == null
            ? null
            : '${rule.serverAlias} · ${rule.value}: $error';
      }),
    );
    return results.whereType<String>().toList();
  }

  String mappingKey(ManagedMapping mapping) => 'mapping:${mapping.id}';
  bool mappingRunning(ManagedMapping mapping) =>
      _activeProxies.containsKey(mappingKey(mapping)) &&
      !mappingLoading(mapping);
  bool mappingLoading(ManagedMapping mapping) =>
      _loadingStates[mappingKey(mapping)] ?? false;
  Future<void> addMapping(
    String server,
    String type,
    String value, {
    String group = '',
    Iterable<String> tags = const [],
  }) async {
    if (group.trim().isNotEmpty) mappingGroups.add(group.trim());
    mappings.add(
      ManagedMapping(
        id: '${DateTime.now().microsecondsSinceEpoch}-${mappings.length}',
        serverAlias: server,
        type: type,
        value: value,
        group: group,
        tags: tags,
      ),
    );
    notifyListeners();
    await saveMetadata();
  }

  Future<void> updateMapping(
    ManagedMapping mapping,
    String server,
    String type,
    String value, {
    String group = '',
    Iterable<String> tags = const [],
  }) async {
    if (mapping.serverAlias != server ||
        mapping.type != type ||
        mapping.value != value) {
      await stopMapping(mapping);
    }
    mapping.serverAlias = server;
    mapping.type = type;
    mapping.value = value;
    mapping.group = group.trim();
    if (mapping.group.isNotEmpty) mappingGroups.add(mapping.group);
    mapping.tags = ManagedMapping.normalizeTags(tags);
    notifyListeners();
    await saveMetadata();
  }

  Future<void> renameMappingGroup(String group, String next) async {
    final name = next.trim();
    if (name == 'Ungrouped') return;
    mappingGroups.remove(group);
    if (name.isNotEmpty) mappingGroups.add(name);
    for (final mapping in mappings.where((mapping) => mapping.group == group)) {
      mapping.group = name;
    }
    notifyListeners();
    await saveMetadata();
  }

  Future<List<String>> startMappingGroup(String group) async {
    return startMappings(mappings.where((rule) => rule.group == group));
  }

  Future<void> stopMappingGroup(String group) async {
    for (final mapping
        in mappings.where((mapping) => mapping.group == group).toList()) {
      await stopMapping(mapping);
    }
  }

  Future<void> stopMapping(ManagedMapping mapping) async {
    _loadingStates[mappingKey(mapping)] = false;
    _activeProxies.remove(mappingKey(mapping))?.kill();
    notifyListeners();
  }

  Future<void> removeMapping(ManagedMapping mapping) async {
    await stopMapping(mapping);
    mappings.remove(mapping);
    notifyListeners();
    await saveMetadata();
  }

  Future<String?> toggleMapping(ManagedMapping mapping) async {
    if (mappingLoading(mapping)) return null;
    if (mappingRunning(mapping)) {
      await stopMapping(mapping);
      return null;
    }
    if (!hosts.any(
      (host) =>
          host.hostAlias == mapping.serverAlias && host.hostName.isNotEmpty,
    )) {
      return 'The server is missing or has no hostname.';
    }
    final port = mapping.value.split(':').first;
    if (mappings.any(
      (other) =>
          other.id != mapping.id &&
          (mapping.type == 'R'
              ? other.type == 'R' && other.serverAlias == mapping.serverAlias
              : other.type != 'R') &&
          other.value.split(':').first == port &&
          (mappingRunning(other) || mappingLoading(other)),
    )) {
      return mapping.type == 'R'
          ? 'Server port $port is already used by another running mapping on this server.'
          : 'Local port $port is already used by another running mapping.';
    }
    return startProxy(
      mapping.serverAlias,
      forwardType: mapping.type,
      forwardValue: mapping.value,
      processKey: mappingKey(mapping),
    );
  }

  List<SSHHost> hosts = [];
  List<SSHHost> filteredHosts = [];
  int _selectedIndex = 0;
  String _searchQuery = "";

  final Map<String, Process> _activeProxies = {};
  final Set<Future<Process>> _spawningProxies = {};
  bool _shuttingDown = false;

  Future<Process> _spawnProxy(List<String> arguments) async {
    final pending = processStarter('ssh', arguments);
    _spawningProxies.add(pending);
    try {
      return await pending;
    } finally {
      _spawningProxies.remove(pending);
    }
  }

  Future<void> shutdownProxies() async {
    _shuttingDown = true;
    _loadingStates.updateAll((_, _) => false);
    final processes = _activeProxies.values.toSet();
    _activeProxies.clear();
    for (final process in processes) {
      process.kill();
    }
    // Include starts in flight so quitting cannot orphan a newly spawned SSH.
    await Future.wait(
      _spawningProxies.toList().map((pending) async {
        try {
          final process = await pending;
          process.kill();
          processes.add(process);
        } catch (_) {
          // Failed starts have no process to stop.
        }
      }),
    );
    await Future.wait(
      processes.map((process) async {
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
      }),
    );
  }

  final Map<String, bool> _loadingStates = {};
  final Set<String> _dirtyHosts = {};
  final Map<SSHHost, String> _savedHostStates = {};

  String _hostState(SSHHost host) {
    final keys = host.advancedOptions.keys.toList()..sort();
    return jsonEncode([
      host.hostAlias,
      host.hostName,
      host.user,
      host.port,
      host.identityFile,
      host.proxyJump,
      host.dynamicForward,
      host.localForwards,
      host.remoteForwards,
      {for (final key in keys) key: host.advancedOptions[key]},
    ]);
  }

  int get selectedIndex => _selectedIndex;

  SSHHost? get currentHost {
    if (filteredHosts.isEmpty) return null;
    if (_selectedIndex < 0) return filteredHosts.first;
    if (_selectedIndex >= filteredHosts.length) return filteredHosts.last;
    return filteredHosts[_selectedIndex];
  }

  final List<String> recentHosts = [];
  final Set<String> favorites = {};
  final Map<String, String> hostGroups = {};
  final Map<String, List<String>> hostTags = {};
  final Map<String, ConnectionProxyPreferences> connectionProxies = {};
  ConnectionProxyPreferences proxyFor(SSHHost host) =>
      connectionProxies[host.hostAlias] ?? const ConnectionProxyPreferences();
  Future<void> updateConnectionProxy(
    SSHHost host,
    ConnectionProxyPreferences value,
  ) {
    connectionProxies[host.hostAlias] = value;
    notifyListeners();
    return saveMetadata();
  }

  final Set<String> explicitGroups = {};
  final List<String> sectionOrder = [];
  final Map<String, List<String>> hostOrder = {};
  List<SSHHost> orderedHosts(String section, List<SSHHost> entries) {
    final order = hostOrder[section] ?? [];
    return List<SSHHost>.from(entries)..sort((a, b) {
      final first = order.indexOf(a.hostAlias);
      final second = order.indexOf(b.hostAlias);
      final result = (first < 0 ? 999999 : first).compareTo(
        second < 0 ? 999999 : second,
      );
      return result != 0
          ? result
          : entries.indexOf(a).compareTo(entries.indexOf(b));
    });
  }

  Future<void> moveHosts(
    List<SSHHost> moving,
    String section, {
    SSHHost? target,
    bool after = false,
  }) {
    if (moving.isEmpty || (target != null && moving.contains(target))) {
      return Future.value();
    }
    for (final host in moving) {
      if (section == 'Favorites') {
        favorites.add(host.hostAlias);
      } else {
        final group = section == 'Group · Favorites' ? 'Favorites' : section;
        if (group == 'Ungrouped' || group.isEmpty) {
          hostGroups.remove(host.hostAlias);
        } else {
          hostGroups[host.hostAlias] = group;
          explicitGroups.add(group);
        }
      }
    }
    final members = hosts
        .where(
          (host) => section == 'Favorites'
              ? isFavorite(host)
              : groupFor(host) ==
                    (section == 'Group · Favorites'
                        ? 'Favorites'
                        : section.isEmpty
                        ? 'Ungrouped'
                        : section),
        )
        .toList();
    final aliases = orderedHosts(section, members)
        .where((host) => !moving.contains(host))
        .map((host) => host.hostAlias)
        .toList();
    final index = target == null ? -1 : aliases.indexOf(target.hostAlias);
    aliases.insertAll(
      index < 0 ? aliases.length : index + (after ? 1 : 0),
      moving.map((host) => host.hostAlias),
    );
    hostOrder[section] = aliases;
    notifyListeners();
    return saveMetadata();
  }

  Future<void> moveHostBefore(SSHHost source, SSHHost target, String section) =>
      moveHosts([source], section, target: target);

  Future<void> moveSection(
    String source,
    String target,
    Iterable<String> visible, {
    bool after = true,
  }) {
    if (source == 'Ungrouped' || source == target) return Future.value();
    final visibleSections = visible.toList();
    final order = [
      ...sectionOrder.where((name) => name != 'Ungrouped'),
      ...visibleSections.where(
        (name) => name != 'Ungrouped' && !sectionOrder.contains(name),
      ),
    ];
    if (!order.contains(source)) return Future.value();
    if (target != 'Ungrouped' && !order.contains(target)) return Future.value();
    order.remove(source);
    final targetIndex = target == 'Ungrouped'
        ? order.length
        : order.indexOf(target) + (after ? 1 : 0);
    order.insert(targetIndex.clamp(0, order.length), source);
    sectionOrder
      ..clear()
      ..addAll(order);
    notifyListeners();
    return saveMetadata();
  }

  double sidebarWidth = 240;
  Future<void> setSidebarWidth(double value) {
    sidebarWidth = value.clamp(220, 320);
    return saveMetadata();
  }

  List<String> get groupNames =>
      ({...explicitGroups, ...hostGroups.values}.toList()..sort());
  bool get isSearching => _searchQuery.isNotEmpty;
  Future<void> renameGroup(String oldName, String newName) {
    final name = newName.trim();
    if (name.isEmpty || name == 'Ungrouped' || name == oldName) {
      return Future.value();
    }
    explicitGroups.remove(oldName);
    explicitGroups.add(name);
    final oldKey = oldName == 'Favorites' ? 'Group · Favorites' : oldName;
    final newKey = name == 'Favorites' ? 'Group · Favorites' : name;
    final sectionIndex = sectionOrder.indexOf(oldKey);
    if (sectionIndex >= 0) sectionOrder[sectionIndex] = newKey;
    final order = hostOrder.remove(oldKey);
    if (order != null) hostOrder[newKey] = order;
    hostGroups.updateAll((_, value) => value == oldName ? name : value);
    final groupIcon = groupIcons.remove(oldName);
    if (groupIcon != null) groupIcons[name] = groupIcon;
    final groupColor = groupColors.remove(oldName);
    if (groupColor != null) groupColors[name] = groupColor;
    notifyListeners();
    return saveMetadata();
  }

  Future<void> removeGroup(String name) {
    explicitGroups.remove(name);
    final key = name == 'Favorites' ? 'Group · Favorites' : name;
    sectionOrder.remove(key);
    hostOrder.remove(key);
    groupIcons.remove(name);
    groupColors.remove(name);
    hostGroups.removeWhere((_, value) => value == name);
    notifyListeners();
    return saveMetadata();
  }

  Future<void> createGroup(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && trimmed != "Ungrouped") {
      explicitGroups.add(trimmed);
    }
    notifyListeners();
    return saveMetadata();
  }

  final Map<String, String> hostIcons = {};
  final Map<String, String> groupIcons = {};
  final Map<String, String> groupColors = {};
  final File? configFile;
  final Future<Process> Function(String, List<String>) processStarter;
  File? _metadataFile;
  Future<void> _pendingMetadata = Future.value();
  String? metadataError;
  String? configError;
  final List<File>? legacyMetadataFiles;
  final bool _usesDefaultMetadata;

  /// Bytes the `config_bk` folder may occupy before the oldest copies are
  /// dropped. Tests set this low; the application uses the default.
  final int archiveBudget;

  SSHStore({
    bool load = true,
    File? metadataFile,
    this.legacyMetadataFiles,
    this.configFile,
    this.archiveBudget = _configArchiveBudget,
    Future<Process> Function(String, List<String>)? processStarter,
  }) : processStarter =
           processStarter ??
           ((executable, arguments) => Process.start(executable, arguments)),
       _usesDefaultMetadata = metadataFile == null,
       _metadataFile = metadataFile {
    if (load) {
      initialize();
    } else {
      preferencesLoaded = true;
    }
  }

  Future<void> initialize() async {
    await loadMetadata();
    await Future.wait([loadConfig(), loadApplicationInfo()]);
    if (_legacySshProxy != null && configError == null) {
      for (final host in hosts) {
        connectionProxies.putIfAbsent(host.hostAlias, () => _legacySshProxy!);
      }
      _legacySshProxy = null;
      await saveMetadata();
    }
    if (Platform.isMacOS && preferences.autoCheckUpdates) {
      unawaited(checkForUpdates(automatic: true));
    }
  }

  /// Copies the current config into `<config folder>/config_bk` before a write,
  /// naming each copy after the moment it was taken.
  ///
  /// The folder is trimmed to [archiveBudget] bytes, oldest first, so a config fed
  /// by hand can be walked back through its own history.
  Future<void> _archiveConfig(File configPath) async {
    try {
      if (!await configPath.exists()) return;
      final bytes = await configPath.readAsBytes();
      final directory = Directory(
        p.join(configPath.parent.path, _configArchiveFolder),
      );
      await directory.create(recursive: true);
      final archives = await _configArchives(directory);
      if (archives.isNotEmpty &&
          _sameBytes(await archives.last.readAsBytes(), bytes)) {
        // Nothing changed since the previous copy; do not spend budget on it.
        return;
      }
      final stamp = _archiveStamp(DateTime.now());
      final prefix = 'config-$stamp-';
      final taken = archives
          .where((archive) => p.basename(archive.path).startsWith(prefix))
          .length;
      final archive = File(
        p.join(
          directory.path,
          '$prefix${(taken + 1).toString().padLeft(3, '0')}.bak',
        ),
      );
      await archive.writeAsBytes(bytes, flush: true);
      await _trimConfigArchives(directory, archives..add(archive));
    } catch (e) {
      // A failed archive must not block the save it precedes.
      debugPrint('Could not archive the SSH config: $e');
    }
  }

  /// Archives in chronological order. The fixed-width timestamp in the name keeps
  /// lexicographic order equal to the order they were taken.
  Future<List<File>> _configArchives(Directory directory) async {
    final archives = <File>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('config-') && name.endsWith('.bak')) {
        archives.add(entity);
      }
    }
    return archives..sort((a, b) => a.path.compareTo(b.path));
  }

  Future<void> _trimConfigArchives(
    Directory directory,
    List<File> archives,
  ) async {
    var total = 0;
    for (final archive in archives) {
      total += await archive.length();
    }
    // Always keep the newest copy, even when it alone exceeds the budget.
    for (
      var index = 0;
      total > archiveBudget && index < archives.length - 1;
      index++
    ) {
      final size = await archives[index].length();
      await archives[index].delete();
      total -= size;
    }
  }

  String _archiveStamp(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}${two(at.second)}';
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  String groupFor(SSHHost host) => hostGroups[host.hostAlias] ?? 'Ungrouped';
  List<String> tagsFor(SSHHost host) =>
      List.unmodifiable(hostTags[host.hostAlias] ?? const <String>[]);

  Future<void> setHostTags(SSHHost host, Iterable<String> tags) async {
    final normalized = ManagedMapping.normalizeTags(tags);
    if (normalized.isEmpty) {
      hostTags.remove(host.hostAlias);
    } else {
      hostTags[host.hostAlias] = normalized;
    }
    search(_searchQuery);
    await saveMetadata();
  }

  bool matchesHost(SSHHost host, String query) {
    final value = query.trim().toLowerCase();
    if (value.startsWith('#')) {
      return tagsFor(
        host,
      ).any((tag) => tag.toLowerCase() == value.substring(1));
    }
    return '${host.hostAlias} ${host.hostName} ${host.user} ${groupFor(host)} ${tagsFor(host).join(' ')}'
        .toLowerCase()
        .contains(value);
  }

  bool isFavorite(SSHHost host) => favorites.contains(host.hostAlias);

  ConnectionProxyPreferences? _legacySshProxy;

  Future<void> loadMetadata() async {
    try {
      _metadataFile ??= File(
        p.join(
          (await getApplicationSupportDirectory()).path,
          'host-library.json',
        ),
      );
      if (!await _metadataFile!.exists()) {
        final legacyFiles =
            legacyMetadataFiles ??
            (_usesDefaultMetadata
                ? [
                    File(
                      p.join(
                        _metadataFile!.parent.parent.path,
                        'com.example.macosSshTool',
                        'host-library.json',
                      ),
                    ),
                  ]
                : <File>[]);
        for (final legacy in legacyFiles) {
          if (!await legacy.exists()) continue;
          final contents = await legacy.readAsString();
          // Validate before copying; never replace the user's old library.
          final decoded = jsonDecode(contents);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Old host library is not an object.');
          }
          // Validate the shape of collections before adopting old data.
          HarborPreferences.fromJson(decoded['preferences']);
          for (final key in [
            'mappings',
            'mappingGroups',
            'favorites',
            'sectionOrder',
            'groupNames',
            'recent',
          ]) {
            if (decoded[key] != null && decoded[key] is! List) {
              throw FormatException('Invalid old library field: $key');
            }
          }
          for (final key in [
            'hostOrder',
            'hostTags',
            'groups',
            'icons',
            'groupIcons',
            'groupColors',
          ]) {
            if (decoded[key] != null && decoded[key] is! Map) {
              throw FormatException('Invalid old library field: $key');
            }
          }
          await _metadataFile!.parent.create(recursive: true);
          final temporary = File('${_metadataFile!.path}.migration.tmp');
          try {
            await temporary.writeAsString(contents, flush: true);
            if (!await _metadataFile!.exists()) {
              await temporary.rename(_metadataFile!.path);
            }
          } finally {
            if (await temporary.exists()) await temporary.delete();
          }
          break;
        }
      }
      if (await _metadataFile!.exists()) {
        final data =
            jsonDecode(await _metadataFile!.readAsString())
                as Map<String, dynamic>;
        preferences = HarborPreferences.fromJson(data['preferences']);
        final savedProxies = data['connectionProxies'];
        if (savedProxies is Map) {
          savedProxies.forEach((alias, value) {
            if (alias is String && value is Map) {
              connectionProxies[alias] = ConnectionProxyPreferences.fromJson(
                value,
              );
            }
          });
        } else if (data['preferences'] is Map &&
            data['preferences']['sshUseProxy'] == true) {
          _legacySshProxy = ConnectionProxyPreferences.fromJson(
            data['preferences'],
          );
        }
        mappings.addAll(
          (data['mappings'] as List? ?? []).map(
            (value) =>
                ManagedMapping.fromJson(Map<String, dynamic>.from(value)),
          ),
        );
        mappingGroups.addAll(
          mappings
              .map((mapping) => mapping.group)
              .where((group) => group.isNotEmpty),
        );
        mappingGroups.addAll(
          List<String>.from(
            data['mappingGroups'] ?? [],
          ).map((name) => name.trim()).where((name) => name.isNotEmpty),
        );
        favorites.addAll(List<String>.from(data['favorites'] ?? []));
        final width = data['sidebarWidth'];
        if (width is num) sidebarWidth = width.toDouble().clamp(220, 320);
        final orders = Map<String, dynamic>.from(data['hostOrder'] ?? {});
        orders.forEach(
          (key, value) => hostOrder[key] = List<String>.from(value),
        );
        sectionOrder.addAll(List<String>.from(data['sectionOrder'] ?? []));
        explicitGroups.addAll(List<String>.from(data['groupNames'] ?? []));
        hostGroups.addAll(Map<String, String>.from(data['groups'] ?? {}));
        final savedTags = data['hostTags'];
        if (savedTags is Map) {
          savedTags.forEach((alias, tags) {
            if (alias is String && tags is List) {
              hostTags[alias] = ManagedMapping.normalizeTags(
                tags.whereType<String>(),
              );
            }
          });
        }
        hostIcons.addAll(Map<String, String>.from(data['icons'] ?? {}));
        groupIcons.addAll(Map<String, String>.from(data['groupIcons'] ?? {}));
        groupColors.addAll(Map<String, String>.from(data['groupColors'] ?? {}));
        recentHosts.addAll(List<String>.from(data['recent'] ?? []));
      }
    } catch (e) {
      metadataError = 'Could not load your host library: $e';
    }
    preferencesLoaded = true;
    notifyListeners();
  }

  Future<void> saveMetadata() {
    final contents = jsonEncode({
      'preferences': {
        ...preferences.toJson(),
        if (_legacySshProxy != null) 'sshUseProxy': true,
      },
      'mappings': mappings.map((mapping) => mapping.toJson()).toList(),
      'mappingGroups': mappingGroups.toList()..sort(),
      'favorites': favorites.toList(),
      'groups': hostGroups,
      'hostTags': hostTags,
      if (_legacySshProxy == null)
        'connectionProxies': connectionProxies.map(
          (alias, value) => MapEntry(alias, value.toJson()),
        ),
      'groupNames': explicitGroups.toList(),
      'sectionOrder': sectionOrder,
      'hostOrder': hostOrder,
      'sidebarWidth': sidebarWidth,
      'icons': hostIcons,
      'groupIcons': groupIcons,
      'groupColors': groupColors,
      'recent': recentHosts,
    });
    _pendingMetadata = _pendingMetadata.then((_) async {
      try {
        _metadataFile ??= File(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'host-library.json',
          ),
        );
        await _metadataFile!.parent.create(recursive: true);
        final temporary = File('${_metadataFile!.path}.tmp');
        await temporary.writeAsString(contents, flush: true);
        await temporary.rename(_metadataFile!.path);
        metadataError = null;
      } catch (e) {
        metadataError = 'Could not save your host library: $e';
      }
      notifyListeners();
    });
    return _pendingMetadata;
  }

  Future<void> toggleFavorite(SSHHost host) {
    if (!favorites.remove(host.hostAlias)) favorites.add(host.hostAlias);
    notifyListeners();
    return saveMetadata();
  }

  Future<void> setGroup(SSHHost host, String group) {
    final name = group.trim();
    if (name.isEmpty || name == 'Ungrouped') {
      hostGroups.remove(host.hostAlias);
    } else {
      hostGroups[host.hostAlias] = name;
    }
    notifyListeners();
    return saveMetadata();
  }

  Future<void> setHostIcon(SSHHost host, String? icon) {
    if (icon == null) {
      hostIcons.remove(host.hostAlias);
    } else {
      hostIcons[host.hostAlias] = icon;
    }
    notifyListeners();
    return saveMetadata();
  }

  Future<void> setGroupIcon(String group, String? icon) {
    if (icon == null) {
      groupIcons.remove(group);
    } else {
      groupIcons[group] = icon;
    }
    notifyListeners();
    return saveMetadata();
  }

  Future<void> setGroupColor(String group, String? color) {
    if (color == null) {
      groupColors.remove(group);
    } else {
      groupColors[group] = color;
    }
    notifyListeners();
    return saveMetadata();
  }

  Color colorForGroup(String name) => groupColor(name, palette: groupColors);

  IconData? iconForGroup(String name) => harborGroupIcons[groupIcons[name]];

  String? validateHostAlias(SSHHost host, String alias) {
    if (alias.isEmpty) return 'Enter a connection name.';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(alias)) {
      return 'Use letters, numbers, dots, underscores or hyphens.';
    }
    if (hosts.any(
      (other) => !identical(other, host) && other.hostAlias == alias,
    )) {
      return 'A connection with this name already exists.';
    }
    if (alias != host.hostAlias &&
        (isConnected(host.hostAlias) || isLoading(host.hostAlias))) {
      return 'Stop this connection’s tunnels before renaming.';
    }
    return null;
  }

  void renameHost(SSHHost host, String alias) {
    if (validateHostAlias(host, alias) != null || alias == host.hostAlias) {
      return;
    }
    final old = host.hostAlias;
    for (final order in hostOrder.values) {
      final index = order.indexOf(old);
      if (index >= 0) order[index] = alias;
    }
    final recentIndex = recentHosts.indexOf(old);
    if (recentIndex >= 0) recentHosts[recentIndex] = alias;
    for (final mapping in mappings) {
      if (mapping.serverAlias == old) mapping.serverAlias = alias;
    }
    host.hostAlias = alias;
    if (favorites.remove(old)) favorites.add(alias);
    final proxy = connectionProxies.remove(old);
    if (proxy != null) connectionProxies[alias] = proxy;
    final tags = hostTags.remove(old);
    if (tags != null) hostTags[alias] = tags;
    final icon = hostIcons.remove(old);
    if (icon != null) hostIcons[alias] = icon;
    final group = hostGroups.remove(old);
    if (group != null) hostGroups[alias] = group;
    _dirtyHosts.remove(old);
    markDirty(alias);
    saveMetadata();
  }

  void selectHost(SSHHost host) {
    _searchQuery = '';
    filteredHosts = List.from(hosts);
    _selectedIndex = filteredHosts.indexOf(host);
    notifyListeners();
  }

  void selectIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  void search(String query) {
    final selected = currentHost;
    _searchQuery = query;
    _applyFilter();
    _selectedIndex = selected == null ? 0 : filteredHosts.indexOf(selected);
    if (_selectedIndex < 0) _selectedIndex = 0;
    notifyListeners();
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      filteredHosts = List.from(hosts);
    } else {
      filteredHosts = hosts
          .where((host) => matchesHost(host, _searchQuery))
          .toList();
    }
    notifyListeners();
  }

  String forwardKey(String alias, String type, String value) =>
      '$alias\u001f$type\u001f$value';
  bool isConnected(String hostAlias) => _activeProxies.keys.any(
    (key) =>
        (key == hostAlias || key.startsWith('$hostAlias\u001f')) &&
        !(_loadingStates[key] ?? false),
  );
  bool isLoading(String hostAlias) => _loadingStates.entries.any(
    (entry) =>
        (entry.key == hostAlias || entry.key.startsWith('$hostAlias\u001f')) &&
        entry.value,
  );
  bool isForwardRunning(SSHHost host, String type, String value) =>
      _activeProxies.containsKey(forwardKey(host.hostAlias, type, value)) &&
      !isForwardLoading(host, type, value);
  bool isForwardLoading(SSHHost host, String type, String value) =>
      _loadingStates[forwardKey(host.hostAlias, type, value)] ?? false;
  Future<String?> toggleForward(SSHHost host, String type, String value) async {
    final key = forwardKey(host.hostAlias, type, value);
    if (_activeProxies.containsKey(key)) {
      await stopForward(host, type, value);
      return null;
    }
    return startProxy(host.hostAlias, forwardType: type, forwardValue: value);
  }

  Future<void> stopForward(SSHHost host, String type, String value) async {
    final key = forwardKey(host.hostAlias, type, value);
    _activeProxies.remove(key)?.kill();
    _loadingStates[key] = false;
    notifyListeners();
  }

  bool isDirty(String hostAlias) {
    final host = hosts.where((host) => host.hostAlias == hostAlias).firstOrNull;
    if (host == null) return false;
    final saved = _savedHostStates[host];
    return saved == null
        ? _dirtyHosts.contains(hostAlias)
        : _hostState(host) != saved;
  }

  void markDirty(String hostAlias) {
    _dirtyHosts.add(hostAlias);
    notifyListeners();
  }

  Future<void> loadConfig() async {
    final home = Platform.environment['HOME'];
    final configPath = configFile ?? File('$home/.ssh/config');

    try {
      if (!await configPath.exists()) {
        hosts = [];
        _dirtyHosts.clear();
        _savedHostStates.clear();
        configError = null;
        _applyFilter();
        return;
      }

      final lines = await configPath.readAsLines();
      hosts = [];
      SSHHost? current;

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;

        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;

        final key = parts[0].toLowerCase();
        final value = parts.sublist(1).join(' ');

        if (key == 'host') {
          if (current != null) hosts.add(current);
          current = SSHHost(hostAlias: value);
        } else if (current != null) {
          switch (key) {
            case 'hostname':
              current.hostName = value;
              break;
            case 'user':
              current.user = value;
              break;
            case 'port':
              current.port = value;
              break;
            case 'identityfile':
              current.identityFile = value;
              break;
            case 'proxyjump':
              current.proxyJump = value;
              break;
            case 'dynamicforward':
              current.dynamicForward = value;
              break;
            case 'remoteforward':
              current.remoteForwards.add(
                value.replaceFirst(RegExp(r'\s+'), ':'),
              );
              break;
            case 'localforward':
              String normalized = value;
              if (value.contains(' ') && !value.contains(':')) {
                normalized = value.replaceFirst(' ', ':');
              } else if (value.contains(' ')) {
                normalized = value.replaceFirst(' ', ':');
              }
              current.localForwards.add(normalized);
              break;
            default:
              if (harborSSHOption(key) != null) {
                current.advancedOptions[parts[0]] = value;
              }
              break;
          }
        }
      }
      if (current != null) hosts.add(current);
      _dirtyHosts.clear();
      _savedHostStates
        ..clear()
        ..addEntries(hosts.map((host) => MapEntry(host, _hostState(host))));
      configError = null;
      _applyFilter();
    } catch (e) {
      configError = 'Could not load SSH config: $e';
      notifyListeners();
    }
  }

  Future<bool> saveConfig() async {
    final home = Platform.environment['HOME'];
    final configPath = configFile ?? File('$home/.ssh/config');

    final buffer = StringBuffer();
    final savedStates = <SSHHost, String>{};
    for (var host in hosts) {
      buffer.writeln(host.toConfigBlock());
      savedStates[host] = _hostState(host);
    }

    try {
      if (!await configPath.parent.exists()) {
        await configPath.parent.create(recursive: true);
      }
      await _archiveConfig(configPath);
      await configPath.writeAsString(buffer.toString());

      _savedHostStates
        ..clear()
        ..addAll(savedStates);
      // Hosts created during the write still have no saved baseline.
      _dirtyHosts.removeWhere(
        (alias) => savedStates.keys.any((host) => host.hostAlias == alias),
      );
      configError = null;
      notifyListeners();
      return true;
    } catch (e) {
      configError = 'Could not save SSH config: $e';
      notifyListeners();
      return false;
    }
  }

  SSHHost addHost({String? group}) {
    var alias = 'NewHost';
    var suffix = 2;
    while (hosts.any((host) => host.hostAlias == alias)) {
      alias = 'NewHost-$suffix';
      suffix++;
    }
    final newHost = SSHHost(hostAlias: alias);
    hosts.add(newHost);
    if (group != null && group != 'Ungrouped') {
      hostGroups[alias] = group;
      explicitGroups.add(group);
      saveMetadata();
    }
    _searchQuery = '';
    _applyFilter();
    _selectedIndex = filteredHosts.indexOf(newHost);
    markDirty(alias);
    return newHost;
  }

  void deleteCurrentHost() {
    final host = currentHost;
    if (host != null) deleteHost(host);
  }

  void deleteHost(SSHHost host) {
    final selected = currentHost;
    for (final mapping in mappings.where(
      (mapping) => mapping.serverAlias == host.hostAlias,
    )) {
      stopMapping(mapping);
    }
    stopProxy(host.hostAlias);
    hosts.remove(host);
    favorites.remove(host.hostAlias);
    hostIcons.remove(host.hostAlias);
    hostTags.remove(host.hostAlias);
    connectionProxies.remove(host.hostAlias);
    final group = hostGroups.remove(host.hostAlias);
    if (group != null) explicitGroups.add(group);
    for (final order in hostOrder.values) {
      order.remove(host.hostAlias);
    }
    recentHosts.remove(host.hostAlias);
    _dirtyHosts.remove(host.hostAlias);
    _applyFilter();
    if (selected != null &&
        selected != host &&
        filteredHosts.contains(selected)) {
      _selectedIndex = filteredHosts.indexOf(selected);
    } else {
      _selectedIndex = filteredHosts.isEmpty
          ? 0
          : _selectedIndex.clamp(0, filteredHosts.length - 1);
    }
    saveMetadata();
    saveConfig();
  }

  Future<List<String>> listKeys() => KeyLibrary().listKeys();

  Future<String> generateKey({
    required String filename,
    required String type,
    String passphrase = '',
  }) async {
    try {
      return await KeyLibrary().generate(filename, type, passphrase);
    } catch (error) {
      return 'Error: $error';
    }
  }

  Future<String> commandFor(SSHHost host) async {
    final options = host.advancedOptions.keys
        .map((key) => key.toLowerCase())
        .toSet();
    return host.getPreviewCommand(
      networkArguments: await sshNetworkProxyArguments(host),
      additionalArguments: [
        if (!options.contains('connecttimeout')) ...[
          '-o',
          'ConnectTimeout=${preferences.connectTimeout}',
        ],
        if (preferences.keepAlive > 0 &&
            !options.contains('serveraliveinterval')) ...[
          '-o',
          'ServerAliveInterval=${preferences.keepAlive}',
          if (!options.contains('serveralivecountmax')) ...[
            '-o',
            'ServerAliveCountMax=3',
          ],
        ],
      ],
    );
  }

  Future<void> copyHostCommand(SSHHost host) async {
    await Clipboard.setData(ClipboardData(text: await commandFor(host)));
  }

  Future<void> copyCommandToClipboard(BuildContext context) async {
    if (currentHost == null) return;
    final h = currentHost!;
    final cmd = await commandFor(h);

    await Clipboard.setData(ClipboardData(text: cmd));

    if (context.mounted) {
      showHarborDialog(
        context: context,
        builder: (_) => HarborAlert(
          appIcon: const Icon(
            CupertinoIcons.checkmark_circle_fill,
            color: CupertinoColors.activeGreen,
          ),
          title: const Text("Command Copied"),
          message: const Text(
            "The SSH command has been copied to your clipboard.",
          ),
          primaryButton: HarborButton(
            label: "OK",
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
  }

  Future<void> openTerminal([SSHHost? target]) async {
    final host = target ?? currentHost;
    if (host == null) return;
    final cmd = await commandFor(host);
    final directory = await Directory.systemTemp.createTemp('harbor-ssh-');
    final script = File(p.join(directory.path, 'connect.command'));
    try {
      await script.writeAsString(terminalCommandScript(cmd), flush: true);
      final permissions = await Process.run('/bin/chmod', ['700', script.path]);
      if (permissions.exitCode != 0) {
        throw Exception(permissions.stderr.toString().trim());
      }
      final result = await Process.run(
        '/usr/bin/open',
        terminalOpenArguments(script.path),
      );
      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString().trim());
      }
    } catch (_) {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
    recordRecentHost(host);
    notifyListeners();
    await saveMetadata();
  }

  Future<String?> toggleConnection() async {
    if (currentHost == null) return null;
    final alias = currentHost!.hostAlias;

    if (isConnected(alias)) {
      await stopProxy(alias);
      return null;
    } else {
      final host = currentHost!;
      final results = await Future.wait([
        if (host.dynamicForward.isNotEmpty)
          startProxy(
            alias,
            forwardType: 'D',
            forwardValue: host.dynamicForward,
          ),
        for (final value in host.localForwards)
          startProxy(alias, forwardType: 'L', forwardValue: value),
        for (final value in host.remoteForwards)
          startProxy(alias, forwardType: 'R', forwardValue: value),
      ]);
      final errors = results.whereType<String>().toList();
      return errors.isEmpty ? null : errors.join('\n');
    }
  }

  Future<String?> startProxy(
    String alias, {
    String? forwardType,
    String? forwardValue,
    String? processKey,
  }) async {
    if (_shuttingDown) return 'Application is quitting.';
    final key =
        processKey ??
        (forwardType == null
            ? alias
            : forwardKey(alias, forwardType, forwardValue!));
    if (_loadingStates[key] == true || _activeProxies.containsKey(key)) {
      return null;
    }
    _loadingStates[key] = true;
    notifyListeners();

    final h = hosts.firstWhere((e) => e.hostAlias == alias);

    List<String> args = [
      if (processKey != null) ...['-F', '/dev/null'],
      '-N',
      '-v',
    ];
    if (h.port != '22') args.addAll(['-p', h.port]);
    if (h.identityFile.isNotEmpty) args.addAll(['-i', h.identityFile]);
    if (h.proxyJump.isNotEmpty) {
      final jump = processKey == null
          ? h.proxyJump
          : h.proxyJump
                .split(',')
                .map((alias) {
                  final matches = hosts.where(
                    (host) => host.hostAlias == alias.trim(),
                  );
                  if (matches.isEmpty) return alias;
                  final server = matches.first;
                  return '${server.user.isEmpty ? '' : '${server.user}@'}${server.hostName}${server.port == '22' ? '' : ':${server.port}'}';
                })
                .join(',');
      args.addAll(['-J', jump]);
    }
    if (forwardType != null) {
      args.addAll(['-$forwardType', forwardValue!]);
    } else {
      if (h.dynamicForward.isNotEmpty) args.addAll(['-D', h.dynamicForward]);
      for (var fwd in h.localForwards) {
        args.addAll(['-L', fwd]);
      }
      for (final forward in h.remoteForwards) {
        args.addAll(['-R', forward]);
      }
    }

    args.addAll(['-o', 'ExitOnForwardFailure=yes']);

    bool hasCustomTimeout = h.advancedOptions.keys.any(
      (k) => k.toLowerCase() == 'connecttimeout',
    );
    if (!hasCustomTimeout) {
      args.addAll(['-o', 'ConnectTimeout=${preferences.connectTimeout}']);
    }

    if (preferences.keepAlive > 0 &&
        !h.advancedOptions.keys.any(
          (key) => key.toLowerCase() == 'serveraliveinterval',
        )) {
      args.addAll(['-o', 'ServerAliveInterval=${preferences.keepAlive}']);
      if (!h.advancedOptions.keys.any(
        (key) => key.toLowerCase() == 'serveralivecountmax',
      )) {
        args.addAll(['-o', 'ServerAliveCountMax=3']);
      }
    }
    h.advancedOptions.forEach((k, v) {
      if (k.toLowerCase() != 'exitonforwardfailure') {
        args.addAll(['-o', '$k=$v']);
      }
    });

    args.addAll(['--', '${h.user.isEmpty ? '' : '${h.user}@'}${h.hostName}']);

    try {
      final networkArguments = await sshNetworkProxyArguments(h);
      if (networkArguments.isNotEmpty) {
        final jumpIndex = args.indexOf('-J');
        if (jumpIndex >= 0) args.removeRange(jumpIndex, jumpIndex + 2);
        args.insertAll(0, networkArguments);
      }
      debugPrint("Starting background SSH: ssh ${args.join(' ')}");

      final process = await _spawnProxy(args);
      if (_shuttingDown || _loadingStates[key] != true) {
        process.kill();
        unawaited(process.stdout.drain<void>());
        unawaited(process.stderr.drain<void>());
        return 'Mapping startup cancelled.';
      }
      _activeProxies[key] = process;
      unawaited(process.stdout.drain<void>());
      final Completer<String?> connectionCompleter = Completer();
      final StringBuffer stderrBuffer = StringBuffer();

      final stderrDone = Completer<void>();
      process.stderr
          .transform(utf8.decoder)
          .listen(
            (data) {
              stderrBuffer.write(data);

              if (!connectionCompleter.isCompleted) {
                if (stderrBuffer.toString().contains(
                  "Entering interactive session",
                )) {
                  debugPrint("SSH Connection established successfully.");
                  connectionCompleter.complete(null);
                }
              }
            },
            onDone: () {
              if (!stderrDone.isCompleted) stderrDone.complete();
            },
            onError: (Object error) {
              stderrBuffer.writeln(error);
              if (!stderrDone.isCompleted) stderrDone.complete();
            },
          );

      process.exitCode.then((exitCode) async {
        await stderrDone.future;
        debugPrint("SSH process for $alias exited with $exitCode");
        if (identical(_activeProxies[key], process)) {
          _activeProxies.remove(key);
          notifyListeners();
        }

        if (!connectionCompleter.isCompleted) {
          String errorMessage = stderrBuffer.toString();
          final lines = errorMessage
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList();
          if (lines.isNotEmpty) {
            errorMessage = lines.length > 3
                ? lines.sublist(lines.length - 3).join('\n')
                : errorMessage;
          } else {
            errorMessage = "Process exited with code $exitCode";
          }
          connectionCompleter.complete(errorMessage);
        }
      });

      final result = await connectionCompleter.future.timeout(
        Duration(
          seconds:
              (int.tryParse(
                    h.advancedOptions.entries
                            .where(
                              (entry) =>
                                  entry.key.toLowerCase() == 'connecttimeout',
                            )
                            .map((entry) => entry.value)
                            .firstOrNull ??
                        '',
                  ) ??
                  preferences.connectTimeout) +
              10,
        ),
        onTimeout: () => 'SSH tunnel startup timed out.',
      );

      _loadingStates[key] = false;

      if (result != null) {
        process.kill();
        if (identical(_activeProxies[key], process)) _activeProxies.remove(key);
      }

      notifyListeners();
      return result;
    } catch (e) {
      _loadingStates[key] = false;
      notifyListeners();
      return "System Error: $e";
    }
  }

  Future<void> stopProxy(String alias) async {
    final keys = _activeProxies.keys
        .where((key) => key == alias || key.startsWith('$alias\u001f'))
        .toList();
    for (final key in keys) {
      _activeProxies.remove(key)?.kill();
      _loadingStates[key] = false;
    }
    notifyListeners();
  }
}

// ----------------------
// 4. UI Interface - MACOS26 Liquid Design (Fixed)
// ----------------------

class MainWindow extends StatefulWidget {
  const MainWindow({super.key});

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow>
    with SingleTickerProviderStateMixin {
  final SSHActivityMonitor _activityMonitor = SSHActivityMonitor();
  bool _activityPage = false;
  final Map<String, GlobalKey> _sectionDropKeys = {};
  final Map<String, GlobalKey> _stickySectionDropKeys = {};
  final Map<(String, SSHHost), GlobalKey> _rowDropKeys = {};
  bool _didAutoScroll = false;
  bool _dragCancelled = false;
  ({String section, SSHHost? host, bool after})? _dragHover;
  ({String section, SSHHost? host, bool after})? _findDragDrop() {
    final viewport = _libraryViewportKey.currentContext?.findRenderObject();
    final pointer = _dragPointer;
    if (pointer == null ||
        viewport is! RenderBox ||
        !(viewport.localToGlobal(Offset.zero) & viewport.size).contains(
          pointer,
        )) {
      return null;
    }
    for (final entry in _sectionDropKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).contains(pointer)) {
        return (
          section: entry.key,
          host: null,
          after: box.globalToLocal(pointer).dy >= box.size.height / 2,
        );
      }
    }
    for (final entry in _stickySectionDropKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).contains(pointer)) {
        return (
          section: entry.key,
          host: null,
          after: box.globalToLocal(pointer).dy >= box.size.height / 2,
        );
      }
    }
    for (final entry in _rowDropKeys.entries) {
      if (_collapsed.contains(entry.key.$1) || _dragSection == entry.key.$1) {
        continue;
      }
      if (_dragHosts.contains(entry.key.$2)) continue;
      final box = entry.value.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).contains(pointer)) {
        return (
          section: entry.key.$1,
          host: _dragSection == null ? entry.key.$2 : null,
          after:
              _dragSection != null ||
              box.globalToLocal(pointer).dy > box.size.height / 2 + 4,
        );
      }
    }
    return null;
  }

  void _refreshDragHover() {
    if (!mounted || !_didAutoScroll) return;
    final hover = _findDragDrop();
    if (hover != _dragHover) setState(() => _dragHover = hover);
  }

  final GlobalKey _libraryViewportKey = GlobalKey();
  SSHHost? _dragLeader;
  String? _dragSection;
  List<SSHHost> _dragHosts = [];
  List<SSHHost> _visibleOrder = [];
  Offset? _dragPointer;
  Duration _lastDragTick = Duration.zero;
  late final Ticker _dragTicker;
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleSearchKey);
    _dragTicker = createTicker(_scrollDuringDrag);
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _activityMonitor.start();
    }
    _commandChannel.setMethodCallHandler(_handleNativeCommand);
  }

  bool _handleSearchKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyF ||
        !(keyboard.isMetaPressed || keyboard.isControlPressed) ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    unawaited(_openSearch());
    return true;
  }

  bool _updatePromptQueued = false;
  Future<void> _promptForUpdate(SSHStore store) async {
    if (_updatePromptQueued ||
        !store.shouldPromptForUpdate ||
        store.updateBusy) {
      return;
    }
    _updatePromptQueued = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      while (mounted &&
          store.shouldPromptForUpdate &&
          ModalRoute.of(context)?.isCurrent == false) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!mounted || !store.shouldPromptForUpdate) return;
      final update = store.availableUpdate;
      if (update == null) return;
      final action = await showHarborDialog<String>(
        context: context,
        builder: (dialogContext) => HarborAlert(
          appIcon: const Icon(CupertinoIcons.arrow_down_circle),
          title: Text('发现新版本 ${update.version}'),
          message: const Text(
            '立即更新会下载安装包并重启 Harbor，当前端口转发将关闭。跳过只在本次启动生效；忽略后不再自动提示此版本。',
          ),
          tertiaryButton: HarborButton(
            label: '跳过本次更新',
            secondary: true,
            onPressed: () => Navigator.of(dialogContext).pop('skip'),
          ),
          secondaryButton: HarborButton(
            label: '忽略',
            secondary: true,
            onPressed: () => Navigator.of(dialogContext).pop('ignore'),
          ),
          primaryButton: HarborButton(
            label: '立即更新',
            onPressed: () => Navigator.of(dialogContext).pop('install'),
          ),
        ),
      );
      if (action == 'ignore') {
        await store.ignoreUpdatePrompt();
      } else {
        store.skipUpdatePrompt();
        if (action == 'install') await store.installUpdate();
      }
    } finally {
      _updatePromptQueued = false;
    }
  }

  static const _commandChannel = MethodChannel('harbor/commands');

  Future<void> _handleNativeCommand(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'shutdown') {
      await context.read<SSHStore>().shutdownProxies();
      return;
    }
    // A modal owns keyboard input until it closes.
    if (call.method == 'quickConnect' &&
        _quickConnectRoutes[Navigator.of(context, rootNavigator: true)] !=
            null) {
      showQuickConnect(context);
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final store = context.read<SSHStore>();
    switch (call.method) {
      case 'settings':
        _showSettings();
      case 'search':
        _openSearch();
      case 'quickConnect':
        showQuickConnect(context);
      case 'newConnection':
        _newConnection(store);
      case 'save':
        await store.saveConfig();
    }
  }

  void _scrollDuringDrag(Duration elapsed) {
    final delta = (elapsed - _lastDragTick).inMicroseconds / 1000000;
    _lastDragTick = elapsed;
    final viewport = _libraryViewportKey.currentContext?.findRenderObject();
    if (_dragPointer == null ||
        viewport is! RenderBox ||
        !_listScrollController.hasClients) {
      return;
    }
    final local = viewport.globalToLocal(_dragPointer!);
    if (local.dx < -40 ||
        local.dx > viewport.size.width + 40 ||
        local.dy < -80 ||
        local.dy > viewport.size.height + 80) {
      return;
    }
    const edge = 64.0;
    final distance = local.dy < edge
        ? local.dy - edge
        : local.dy > viewport.size.height - edge
        ? local.dy - (viewport.size.height - edge)
        : 0.0;
    final intensity = (distance / edge).clamp(-1.0, 1.0);
    final next =
        (_listScrollController.offset +
                intensity * intensity.abs() * 650 * delta.clamp(0.0, 0.032))
            .clamp(0.0, _listScrollController.position.maxScrollExtent);
    if (next != _listScrollController.offset) {
      if (!_didAutoScroll) setState(() => _didAutoScroll = true);
      _listScrollController.jumpTo(next);
    }
    if (_didAutoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDragHover());
    }
  }

  void _updateDrag(Offset position) {
    _dragPointer = position;
    _refreshDragHover();
  }

  void _startDragScroll() {
    _didAutoScroll = false;
    _dragCancelled = false;
    _dragHover = null;
    _lastDragTick = Duration.zero;
    if (!_dragTicker.isActive) _dragTicker.start();
  }

  void _finishDrag() {
    if (_didAutoScroll && !_dragCancelled) {
      final drop = _findDragDrop();
      if (drop != null) {
        final store = context.read<SSHStore>();
        if (_dragSection != null) {
          store.moveSection(
            _dragSection!,
            drop.section,
            _sectionDropKeys.keys,
            after: drop.after,
          );
        } else if (_dragLeader != null) {
          store.moveHosts(
            List.of(_dragHosts),
            drop.section,
            target: drop.host,
            after: drop.after,
          );
          if (drop.host == null) _collapsed.remove(drop.section);
        }
      }
    }
    _didAutoScroll = false;
    _dragHover = null;
    _dragTicker.stop();
    _dragPointer = null;
    if (mounted) {
      setState(() {
        _dragLeader = null;
        _dragSection = null;
        _dragHosts = [];
      });
    }
  }

  void _beginSectionDrag(String name) {
    setState(() => _dragSection = name);
    _startDragScroll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.watch<SSHStore>();
    if (store.shouldPromptForUpdate && !_updatePromptQueued) {
      unawaited(_promptForUpdate(store));
    }
    if (!_initialPageSelected && store.preferencesLoaded) {
      _initialPageSelected = true;
      _workbench = store.preferences.startPage == 'workbench';
      _mappingPage = store.preferences.startPage == 'mappings';
      _keysPage = store.preferences.startPage == 'keys';
    }
  }

  final FocusNode _windowFocus = FocusNode(debugLabel: 'Harbor window');
  String _pageBeforeSettings = 'workbench';

  void _showSettings() => setState(() {
    if (!_settingsPage) {
      _pageBeforeSettings = _activityPage
          ? 'activity'
          : _mappingPage
          ? 'mappings'
          : _keysPage
          ? 'keys'
          : _workbench
          ? 'workbench'
          : 'connection';
    }
    _initialPageSelected = true;
    _workbench = false;
    _activityPage = false;
    _mappingPage = false;
    _keysPage = false;
    _settingsPage = true;
  });

  void _returnToPreviousPage() {
    if (_searchVisible && _filterFocus.hasFocus) {
      _closeSidebarSearch(context.read<SSHStore>());
      return;
    }
    final page = _settingsPage ? _pageBeforeSettings : 'workbench';
    _windowFocus.requestFocus();
    setState(() {
      _settingsPage = false;
      _workbench = page == 'workbench';
      _activityPage = page == 'activity';
      _mappingPage = page == 'mappings';
      _keysPage = page == 'keys';
    });
  }

  final ScrollController _listScrollController = ScrollController();
  final TextEditingController _filterController = TextEditingController();
  final FocusNode _filterFocus = FocusNode();
  final FocusNode _settingsSearchFocus = FocusNode(
    debugLabel: 'Settings search',
  );
  final TextEditingController _settingsSearchController =
      TextEditingController();

  Future<void> _openSearch() async {
    if (!_settingsPage) {
      _openSidebarSearch();
      return;
    }
    // A page fade temporarily excludes focus; honor Command-F once it finishes.
    while (mounted &&
        _settingsPage &&
        (_settingsSearchFocus.context == null ||
            !_settingsSearchFocus.canRequestFocus)) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted ||
        !_settingsPage ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _settingsSearchFocus.requestFocus();
    _settingsSearchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _settingsSearchController.text.length,
    );
  }

  bool _searchVisible = false;
  void _openSidebarSearch() {
    setState(() => _searchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _filterFocus.requestFocus();
        _filterController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _filterController.text.length,
        );
      }
    });
  }

  void _closeSidebarSearch(SSHStore store) {
    _windowFocus.requestFocus();
    _filterController.clear();
    store.search('');
    setState(() => _searchVisible = false);
  }

  final Set<String> _collapsed = {};
  bool _workbench = true;
  bool _mappingPage = false;
  bool _keysPage = false;
  bool _settingsPage = false;
  bool _initialPageSelected = false;
  final Set<SSHHost> _selectedHosts = {};
  SSHHost? _selectionAnchor;
  String? _selectedSidebarSection;
  List<SSHHost> _selectionFor(SSHHost host) {
    if (_dragLeader == host && _dragHosts.isNotEmpty) {
      return List.of(_dragHosts);
    }
    if (!_selectedHosts.contains(host)) return [host];
    final ordered = [
      ..._visibleOrder,
      ...context.read<SSHStore>().hosts.where(
        (host) => !_visibleOrder.contains(host),
      ),
    ];
    return ordered.where(_selectedHosts.contains).toList();
  }

  void _clickHost(
    SSHStore store,
    SSHHost host,
    List<SSHHost> visible, {
    required String section,
  }) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final range =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final additive =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (!range && !additive) {
      _showHost(store, host, section: section);
      return;
    }
    setState(() {
      _selectedSidebarSection = section;
      if (range &&
          _selectionAnchor != null &&
          visible.contains(_selectionAnchor)) {
        final start = visible.indexOf(_selectionAnchor!);
        final end = visible.indexOf(host);
        if (!additive) _selectedHosts.clear();
        _selectedHosts.addAll(
          visible.sublist(
            start < end ? start : end,
            (start > end ? start : end) + 1,
          ),
        );
      } else {
        if (!_selectedHosts.remove(host)) _selectedHosts.add(host);
        _selectionAnchor = host;
      }
      _workbench = false;
      _activityPage = false;
      _mappingPage = false;
      _keysPage = false;
      _settingsPage = false;
    });
    store.selectHost(host);
  }

  void _beginHostDrag(SSHHost host) {
    final moving = _selectionFor(host);
    setState(() {
      if (!_selectedHosts.contains(host)) {
        _selectedHosts
          ..clear()
          ..add(host);
        _selectionAnchor = host;
      }
      _dragLeader = host;
      _dragHosts = moving;
    });
    _startDragScroll();
  }

  Future<void> _moveSelection(SSHStore store, SSHHost host, String group) =>
      store.moveHosts(_selectionFor(host), group.isEmpty ? 'Ungrouped' : group);

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleSearchKey);
    _commandChannel.setMethodCallHandler(null);
    _activityMonitor.dispose();
    _windowFocus.dispose();
    _listScrollController.dispose();
    _dragTicker.dispose();
    _filterFocus.dispose();
    _filterController.dispose();
    _settingsSearchFocus.dispose();
    _settingsSearchController.dispose();
    super.dispose();
  }

  void _newConnection(SSHStore store, {String? group}) {
    final normalizedGroup = group == 'Group · Favorites' ? 'Favorites' : group;
    final host = store.addHost(
      group: group == 'Favorites' ? null : normalizedGroup,
    );
    if (group == 'Favorites') store.toggleFavorite(host);
    _filterController.clear();
    if (group != null) _collapsed.remove(group);
    _showHost(store, host);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext =
          _rowDropKeys[(store.groupFor(host), host)]?.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          duration: harborMotion(context, 280),
          curve: Curves.easeInOutCubic,
          alignment: 0.5,
        );
      }
    });
  }

  void _showHost(SSHStore store, SSHHost host, {String? section}) {
    _selectedSidebarSection = section ?? store.groupFor(host);
    _selectedHosts
      ..clear()
      ..add(host);
    _selectionAnchor = host;
    store.selectHost(host);
    _filterController.clear();
    setState(() {
      _workbench = false;
      _activityPage = false;
      _mappingPage = false;
      _keysPage = false;
      _settingsPage = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final colors = HarborColors.of(context);
    final selectionSection =
        _selectedSidebarSection == 'Favorites' &&
            store.currentHost != null &&
            store.isFavorite(store.currentHost!)
        ? 'Favorites'
        : store.currentHost == null
        ? null
        : store.groupFor(store.currentHost!);
    final sections = <String, List<SSHHost>>{};
    final favorites = store.filteredHosts.where(store.isFavorite).toList();
    if (!store.isSearching || favorites.isNotEmpty) {
      sections['Favorites'] = favorites;
    }
    final groups = {
      ...store.filteredHosts.map(store.groupFor),
      if (!store.isSearching) ...store.groupNames,
    }.toList()..sort();
    for (final group in groups) {
      sections[group == 'Favorites' ? 'Group · Favorites' : group] = store
          .filteredHosts
          .where((h) => store.groupFor(h) == group)
          .toList();
    }
    final orderedSections = sections.entries.toList()
      ..sort((a, b) {
        if (a.key == 'Ungrouped' || b.key == 'Ungrouped') {
          return a.key == 'Ungrouped' ? 1 : -1;
        }
        final first = store.sectionOrder.indexOf(a.key);
        final second = store.sectionOrder.indexOf(b.key);
        final result = (first < 0 ? 999 : first).compareTo(
          second < 0 ? 999 : second,
        );
        return result != 0
            ? result
            : sections.keys
                  .toList()
                  .indexOf(a.key)
                  .compareTo(sections.keys.toList().indexOf(b.key));
      });
    final collapsedSections = {
      ..._collapsed,
      if (_dragSection != null) _dragSection!,
    };
    final foldedHosts = _dragHosts.where((host) => host != _dragLeader).toSet();
    final visibleHosts = <SSHHost>[];
    for (final section in orderedSections) {
      if (!_collapsed.contains(section.key)) {
        for (final host in store.orderedHosts(section.key, section.value)) {
          if (!visibleHosts.contains(host)) visibleHosts.add(host);
        }
      }
    }
    _visibleOrder = visibleHosts;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _returnToPreviousPage,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _showSettings,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.f2): () {
          final host = store.currentHost;
          if (host != null) showRenameHostDialog(context, store, host);
        },
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            _newConnection(store),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            showQuickConnect(context),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            store.saveConfig(),
      },
      child: Focus(
        focusNode: _windowFocus,
        autofocus: true,
        child: MacosWindow(
          backgroundColor: colors.background,
          child: Row(
            children: [
              ResizableSidebar(
                minWidth: 220,
                startWidth: store.sidebarWidth,
                onWidthChanged: store.setSidebarWidth,
                maxWidth: 320,
                child: Container(
                  color: colors.sidebar,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
                        child: Row(
                          children: [
                            const HarborMark(size: 34),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Harbor',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.8,
                                    color: colors.text,
                                  ),
                                ),
                                Text(
                                  'SSH WORKSPACE',
                                  style: TextStyle(
                                    fontSize: 7,
                                    letterSpacing: 1.4,
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: [
                            HarborSidebarNavigation(
                              selectedIndex: _workbench
                                  ? 0
                                  : _activityPage
                                  ? 1
                                  : _mappingPage
                                  ? 2
                                  : _keysPage
                                  ? 3
                                  : null,
                              children: [
                                HarborNavItem(
                                  key: const ValueKey('sidebar-nav:workbench'),
                                  icon: CupertinoIcons.square_grid_2x2,
                                  label: 'Workbench',
                                  selected: _workbench,
                                  onTap: () => setState(() {
                                    _workbench = true;
                                    _activityPage = false;
                                    _mappingPage = false;
                                    _keysPage = false;
                                    _settingsPage = false;
                                  }),
                                ),
                                HarborNavItem(
                                  key: const ValueKey('sidebar-nav:activity'),
                                  icon: CupertinoIcons.waveform_path,
                                  label: 'Activity',
                                  selected: _activityPage,
                                  onTap: () => setState(() {
                                    _workbench = false;
                                    _mappingPage = false;
                                    _keysPage = false;
                                    _settingsPage = false;
                                    _activityPage = true;
                                  }),
                                ),
                                HarborNavItem(
                                  key: const ValueKey('sidebar-nav:mappings'),
                                  icon: CupertinoIcons.arrow_right_arrow_left,
                                  label: 'Port mappings',
                                  selected: _mappingPage,
                                  onTap: () => setState(() {
                                    _workbench = false;
                                    _activityPage = false;
                                    _mappingPage = true;
                                    _keysPage = false;
                                    _settingsPage = false;
                                  }),
                                ),
                                HarborNavItem(
                                  key: const ValueKey('sidebar-nav:keys'),
                                  icon: CupertinoIcons.lock_shield,
                                  label: 'Keys',
                                  selected: _keysPage,
                                  onTap: () => setState(() {
                                    _workbench = false;
                                    _activityPage = false;
                                    _mappingPage = false;
                                    _keysPage = true;
                                    _settingsPage = false;
                                  }),
                                ),
                              ],
                            ),
                            HarborSearchReveal(
                              visible: _searchVisible,
                              child: Padding(
                                key: const ValueKey('sidebar-search'),
                                padding: const EdgeInsets.only(top: 12),
                                child: Focus(
                                  onKeyEvent: (_, event) {
                                    if (event is KeyDownEvent &&
                                        event.logicalKey ==
                                            LogicalKeyboardKey.escape) {
                                      _closeSidebarSearch(store);
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: HarborTextField(
                                    controller: _filterController,
                                    focusNode: _filterFocus,
                                    prefix: const Padding(
                                      padding: EdgeInsets.only(left: 12),
                                      child: Icon(CupertinoIcons.search),
                                    ),
                                    placeholder: 'Find a connection…',
                                    onChanged: store.search,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (store.configError != null ||
                          store.metadataError != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            store.configError ?? store.metadataError!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: HarborColors.copper,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Listener(
                          key: _libraryViewportKey,
                          onPointerCancel: (_) => _dragCancelled = true,
                          onPointerDown: (event) => _updateDrag(event.position),
                          onPointerMove: (event) => _updateDrag(event.position),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onSecondaryTapUp: (details) =>
                                _showNativeContextMenu(
                                  context,
                                  details.globalPosition,
                                  null,
                                  store,
                                ),
                            child: Stack(
                              children: [
                                SingleChildScrollView(
                                  controller: _listScrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: HarborAnimatedSections(
                                    sections: orderedSections,
                                    collapsed: collapsedSections,
                                    folded: foldedHosts,
                                    sectionBuilder: (section) => Column(
                                      children: [
                                        HarborSectionDropTarget(
                                          key: _sectionDropKeys.putIfAbsent(
                                            section.key,
                                            () => GlobalKey(),
                                          ),
                                          externalHover: _didAutoScroll
                                              ? _dragHover?.section ==
                                                        section.key &&
                                                    _dragHover?.host == null
                                              : null,
                                          externalAfter: _dragHover?.after,
                                          hostDrag: _dragLeader != null,
                                          name: section.key,
                                          pointerPosition: () => _dragPointer,
                                          onDropHost: (host) {
                                            if (_didAutoScroll) {
                                              return;
                                            }
                                            store.moveHosts(
                                              _selectionFor(host),
                                              section.key,
                                            );
                                            setState(
                                              () => _collapsed.remove(
                                                section.key,
                                              ),
                                            );
                                          },
                                          onDropSection: (name, after) {
                                            if (!_didAutoScroll) {
                                              store.moveSection(
                                                name,
                                                section.key,
                                                orderedSections.map(
                                                  (entry) => entry.key,
                                                ),
                                                after: after,
                                              );
                                            }
                                          },
                                          builder: (highlighted) {
                                            final header = HarborGroupHeader(
                                              highlighted: highlighted,
                                              name: section.key,
                                              count: section.value.length,
                                              collapsed: collapsedSections
                                                  .contains(section.key),
                                              plain: section.key == 'Ungrouped',
                                            );
                                            return GestureDetector(
                                              onSecondaryTapUp: (details) =>
                                                  _showNativeContextMenu(
                                                    context,
                                                    details.globalPosition,
                                                    null,
                                                    store,
                                                    group: section.key,
                                                  ),
                                              onTap: () => setState(() {
                                                if (!_collapsed.remove(
                                                  section.key,
                                                )) {
                                                  _collapsed.add(section.key);
                                                }
                                              }),
                                              child: section.key == 'Ungrouped'
                                                  ? header
                                                  : HarborSectionDraggable(
                                                      name: section.key,
                                                      onDragStarted: () =>
                                                          _beginSectionDrag(
                                                            section.key,
                                                          ),
                                                      onDragEnd: _finishDrag,
                                                      child: header,
                                                    ),
                                            );
                                          },
                                        ),
                                        HarborAnimatedHosts(
                                          animateSelection: true,
                                          selectedHost:
                                              !_workbench &&
                                                  !_mappingPage &&
                                                  !_keysPage &&
                                                  !_activityPage &&
                                                  !_settingsPage &&
                                                  _selectedHosts.length == 1 &&
                                                  selectionSection ==
                                                      section.key
                                              ? store.currentHost
                                              : null,
                                          collapsed: collapsedSections.contains(
                                            section.key,
                                          ),
                                          hosts: store.orderedHosts(
                                            section.key,
                                            section.value,
                                          ),
                                          folded: foldedHosts,
                                          leader: _dragLeader,
                                          itemBuilder: (host) =>
                                              HarborHostDraggable(
                                                key: _rowDropKeys.putIfAbsent((
                                                  section.key,
                                                  host,
                                                ), () => GlobalKey()),
                                                externalHover: _didAutoScroll
                                                    ? _dragHover?.section ==
                                                              section.key &&
                                                          identical(
                                                            _dragHover?.host,
                                                            host,
                                                          )
                                                    : null,
                                                externalAfter:
                                                    _dragHover?.after,
                                                pointerPosition: () =>
                                                    _dragPointer,
                                                onDragStarted: () =>
                                                    _beginHostDrag(host),
                                                selectionCount:
                                                    _selectedHosts.contains(
                                                      host,
                                                    )
                                                    ? _selectedHosts.length
                                                    : 1,
                                                onDragEnd: _finishDrag,
                                                onDropAt: (source, after) {
                                                  if (!_didAutoScroll) {
                                                    store.moveHosts(
                                                      _selectionFor(source),
                                                      section.key,
                                                      target: host,
                                                      after: after,
                                                    );
                                                  }
                                                },
                                                child: LibraryHostRow(
                                                  key: ObjectKey(host),
                                                  host: host,
                                                  selected:
                                                      !_workbench &&
                                                      !_mappingPage &&
                                                      !_keysPage &&
                                                      !_activityPage &&
                                                      !_settingsPage &&
                                                      _selectedHosts.contains(
                                                        host,
                                                      ) &&
                                                      (_selectedHosts.length >
                                                              1 ||
                                                          section.key ==
                                                              selectionSection),
                                                  slidingSelection:
                                                      _selectedHosts.length <=
                                                      1,
                                                  dragging:
                                                      _dragLeader != null ||
                                                      _dragSection != null,
                                                  onTap: () => _clickHost(
                                                    store,
                                                    host,
                                                    visibleHosts,
                                                    section: section.key,
                                                  ),
                                                  onSecondaryTapUp: (details) =>
                                                      _showNativeContextMenu(
                                                        context,
                                                        details.globalPosition,
                                                        host,
                                                        store,
                                                      ),
                                                ),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _HarborStickySectionHeader(
                                  sections: orderedSections,
                                  scrollController: _listScrollController,
                                  viewportKey: _libraryViewportKey,
                                  sectionKeys: _sectionDropKeys,
                                  builder: (section) {
                                    return HarborSectionDropTarget(
                                      key: _stickySectionDropKeys.putIfAbsent(
                                        section.key,
                                        () => GlobalKey(),
                                      ),
                                      externalHover: _didAutoScroll
                                          ? _dragHover?.section ==
                                                    section.key &&
                                                _dragHover?.host == null
                                          : null,
                                      externalAfter: _dragHover?.after,
                                      hostDrag: _dragLeader != null,
                                      name: section.key,
                                      pointerPosition: () => _dragPointer,
                                      onDropHost: (host) {
                                        if (!_didAutoScroll) {
                                          store.moveHosts(
                                            _selectionFor(host),
                                            section.key,
                                          );
                                          setState(
                                            () =>
                                                _collapsed.remove(section.key),
                                          );
                                        }
                                      },
                                      onDropSection: (name, after) {
                                        if (!_didAutoScroll) {
                                          store.moveSection(
                                            name,
                                            section.key,
                                            orderedSections.map(
                                              (entry) => entry.key,
                                            ),
                                            after: after,
                                          );
                                        }
                                      },
                                      builder: (highlighted) {
                                        final header = HarborGroupHeader(
                                          highlighted: highlighted,
                                          name: section.key,
                                          count: section.value.length,
                                          collapsed: collapsedSections.contains(
                                            section.key,
                                          ),
                                          plain: section.key == 'Ungrouped',
                                        );
                                        return GestureDetector(
                                          onSecondaryTapUp: (details) =>
                                              _showNativeContextMenu(
                                                context,
                                                details.globalPosition,
                                                null,
                                                store,
                                                group: section.key,
                                              ),
                                          onTap: () => setState(() {
                                            if (!_collapsed.remove(
                                              section.key,
                                            )) {
                                              _collapsed.add(section.key);
                                            }
                                          }),
                                          child: section.key == 'Ungrouped'
                                              ? header
                                              : HarborSectionDraggable(
                                                  name: section.key,
                                                  onDragStarted: () =>
                                                      _beginSectionDrag(
                                                        section.key,
                                                      ),
                                                  onDragEnd: _finishDrag,
                                                  child: header,
                                                ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            HarborButton(
                              label: 'New connection',
                              icon: CupertinoIcons.add,
                              fullWidth: true,
                              onPressed: () {
                                _newConnection(store);
                              },
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Tooltip(
                                  message: 'Settings  ⌘,',
                                  child: CupertinoButton(
                                    key: const ValueKey('open-settings'),
                                    padding: const EdgeInsets.all(6),
                                    minimumSize: const Size(28, 28),
                                    onPressed: _showSettings,
                                    child: Icon(
                                      CupertinoIcons.gear_alt,
                                      size: 18,
                                      color: _settingsPage
                                          ? colors.accent
                                          : colors.muted,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'v${store.applicationVersion}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ContentArea(
                  builder: (context, controller) => Container(
                    color: colors.background,
                    child: HarborPageTransition(
                      child: _workbench
                          ? HarborWorkbench(
                              key: const ValueKey('workbench'),
                              onSelect: (host) => _showHost(store, host),
                              monitor: _activityMonitor,
                              onViewActivity: () => setState(() {
                                _workbench = false;
                                _activityPage = true;
                              }),
                            )
                          : _activityPage
                          ? HarborActivityPage(
                              key: const ValueKey('activity'),
                              monitor: _activityMonitor,
                            )
                          : _mappingPage
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: HarborForwardingPage(
                                key: ValueKey('mappings'),
                              ),
                            )
                          : _keysPage
                          ? const HarborKeysPage(key: ValueKey('keys'))
                          : _settingsPage
                          ? HarborSettingsPage(
                              key: const ValueKey('settings'),
                              searchFocusNode: _settingsSearchFocus,
                              searchController: _settingsSearchController,
                            )
                          : HostDetailTabs(
                              key: ValueKey(
                                identityHashCode(store.currentHost),
                              ),
                              initialTab:
                                  store.currentHost?.hostName.isEmpty == true
                                  ? 1
                                  : 0,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNativeContextMenu(
    BuildContext context,
    Offset position,
    SSHHost? host,
    SSHStore store, {
    String? group,
  }) {
    void perform(VoidCallback action) {
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) action();
      });
    }

    final actualGroup = group == 'Group · Favorites' ? 'Favorites' : group;
    final entries = <HarborMenuEntry>[
      if (host != null) ...[
        HarborMenuEntry(
          'Open in terminal',
          CupertinoIcons.arrow_up_right,
          onSelected: () =>
              perform(() => launchHostTerminal(context, store, host)),
        ),
        HarborMenuEntry(
          'Rename…',
          CupertinoIcons.pencil,
          shortcut: 'F2',
          onSelected: () =>
              perform(() => showRenameHostDialog(context, store, host)),
        ),
        HarborMenuEntry(
          'Copy SSH command',
          CupertinoIcons.doc_on_doc,
          onSelected: () => perform(() => store.copyHostCommand(host)),
        ),
        const HarborMenuEntry.separator(),
        HarborMenuEntry(
          store.isFavorite(host) ? 'Unpin connection' : 'Pin connection',
          CupertinoIcons.star,
          onSelected: () => perform(() {
            store.toggleFavorite(host);
          }),
        ),
        HarborMenuEntry(
          'Edit tags…',
          CupertinoIcons.tag,
          onSelected: () =>
              perform(() => showHostTagsEditor(context, store, host)),
        ),
        HarborMenuEntry(
          'Choose icon…',
          CupertinoIcons.square_grid_2x2,
          onSelected: () =>
              perform(() => showHostIconPicker(context, store, host)),
        ),
        HarborMenuEntry(
          _selectionFor(host).length > 1
              ? 'Move ${_selectionFor(host).length} connections to group'
              : 'Move to group',
          CupertinoIcons.folder,
          children: [
            for (final name in store.groupNames)
              HarborMenuEntry(
                name,
                CupertinoIcons.folder,
                checked: store.groupFor(host) == name,
                onSelected: () => perform(() {
                  _moveSelection(store, host, name);
                }),
              ),
            HarborMenuEntry(
              'Ungrouped',
              CupertinoIcons.tray,
              checked: store.groupFor(host) == 'Ungrouped',
              onSelected: () => perform(() {
                _moveSelection(store, host, '');
              }),
            ),
            const HarborMenuEntry.separator(),
            HarborMenuEntry(
              'New group…',
              CupertinoIcons.folder_badge_plus,
              onSelected: () =>
                  perform(() => showNewGroupDialog(context, store, host: host)),
            ),
          ],
        ),
        const HarborMenuEntry.separator(),
      ],
      HarborMenuEntry(
        'New connection',
        CupertinoIcons.plus,
        shortcut: '⌘N',
        onSelected: () => perform(
          () => _newConnection(
            store,
            group: group ?? (host == null ? null : store.groupFor(host)),
          ),
        ),
      ),
      HarborMenuEntry(
        'New group…',
        CupertinoIcons.folder_badge_plus,
        onSelected: () =>
            perform(() => showNewGroupDialog(context, store, host: host)),
      ),
      if (host == null &&
          group != null &&
          group != 'Favorites' &&
          group != 'Ungrouped') ...[
        const HarborMenuEntry.separator(),
        HarborMenuEntry(
          'Group appearance…',
          CupertinoIcons.paintbrush,
          onSelected: () => perform(
            () => showGroupAppearancePicker(context, store, actualGroup!),
          ),
        ),
        HarborMenuEntry(
          'Rename group…',
          CupertinoIcons.pencil,
          onSelected: () => perform(
            () => showNewGroupDialog(context, store, renameFrom: actualGroup),
          ),
        ),
        HarborMenuEntry(
          'Remove group…',
          CupertinoIcons.folder_badge_minus,
          destructive: true,
          onSelected: () =>
              perform(() => confirmRemoveGroup(context, store, actualGroup!)),
        ),
      ],
      if (host != null) ...[
        const HarborMenuEntry.separator(),
        HarborMenuEntry(
          'Delete connection…',
          CupertinoIcons.trash,
          destructive: true,
          onSelected: () =>
              perform(() => confirmDeleteHost(context, store, host)),
        ),
      ],
    ];
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: harborMotion(context, 130),
        reverseTransitionDuration: harborMotion(context, 110),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            ),
        pageBuilder: (menuContext, _, _) => HarborContextMenu(
          position: position,
          entries: entries,
          onDismiss: () => Navigator.pop(menuContext),
        ),
      ),
    );
  }
}

class _HarborStickySectionHeader extends StatelessWidget {
  final List<MapEntry<String, List<SSHHost>>> sections;
  final ScrollController scrollController;
  final GlobalKey viewportKey;
  final Map<String, GlobalKey> sectionKeys;
  final Widget Function(MapEntry<String, List<SSHHost>>) builder;

  const _HarborStickySectionHeader({
    required this.sections,
    required this.scrollController,
    required this.viewportKey,
    required this.sectionKeys,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: scrollController,
    builder: (context, _) {
      final viewport = viewportKey.currentContext?.findRenderObject();
      if (sections.isEmpty || viewport is! RenderBox || !viewport.hasSize) {
        return const SizedBox.shrink();
      }
      final viewportTop = viewport.localToGlobal(Offset.zero).dy;
      final tops = <double>[];
      for (final section in sections) {
        final renderObject = sectionKeys[section.key]?.currentContext
            ?.findRenderObject();
        if (renderObject is! RenderBox || !renderObject.hasSize) {
          return const SizedBox.shrink();
        }
        tops.add(renderObject.localToGlobal(Offset.zero).dy - viewportTop);
      }
      var active = -1;
      for (var index = 0; index < tops.length; index++) {
        if (tops[index] < 0) {
          active = index;
        } else {
          break;
        }
      }
      if (active < 0) return const SizedBox.shrink();
      final nextTop = active + 1 < tops.length ? tops[active + 1] : null;
      final top = nextTop == null
          ? 0.0
          : (nextTop - 40).clamp(-40.0, 0.0).toDouble();
      final section = sections[active];
      return Positioned(
        left: 12,
        right: 12,
        top: top,
        height: 40,
        child: ColoredBox(
          color: HarborColors.of(context).sidebar,
          child: builder(section),
        ),
      );
    },
  );
}

class HostDetailTabs extends StatefulWidget {
  final int initialTab;
  const HostDetailTabs({super.key, this.initialTab = 0});

  @override
  State<HostDetailTabs> createState() => _HostDetailTabsState();
}

class _HostDetailTabsState extends State<HostDetailTabs> {
  late final MacosTabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = MacosTabController(
      initialIndex: widget.initialTab,
      length: 5,
    );
    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final colors = HarborColors.of(context);
    final host = store.currentHost;

    if (host == null) {
      return const HarborEmptyState(message: 'Select or create a host');
    }

    final isDirty = store.isDirty(host.hostAlias);

    return Column(
      children: [
        Container(
          color: colors.background,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
          child: Column(
            children: [
              Row(
                children: [
                  HostMonogram(
                    host: host,
                    size: 42,
                    color: store.colorForGroup(store.groupFor(host)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          host.hostAlias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MacosTheme.of(context).typography.title2
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${store.groupFor(host)} · ${host.hostName}${store.tagsFor(host).isEmpty ? '' : ' · ${store.tagsFor(host).map((tag) => '#$tag').join(' ')}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  HarborFavoriteButton(host: host, size: 18),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 100,
                    height: 40,
                    child: HarborButton(
                      secondary: true,
                      fullWidth: true,
                      onPressed: isDirty ? store.saveConfig : null,
                      icon: isDirty
                          ? CupertinoIcons.pencil
                          : CupertinoIcons.check_mark,
                      label: isDirty ? 'Save' : 'Saved',
                    ),
                  ),
                  const SizedBox(width: 8),
                  HarborButton(
                    label: 'Open Terminal',
                    icon: CupertinoIcons.arrow_up_right,
                    onPressed: () => launchHostTerminal(context, store, host),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: HarborSlidingTabs(
                      labels: const [
                        'Overview',
                        'General',
                        'Connection',
                        'Advanced',
                        'Port mapping',
                      ],
                      selectedIndex: _tabController.index,
                      onSelected: (index) => _tabController.index = index,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: HarborPageTransition(
              child: KeyedSubtree(
                key: ValueKey(
                  '${identityHashCode(host)}:${_tabController.index}',
                ),
                child: [
                  _buildDashboard(context, host),
                  _buildGeneral(context, store),
                  _buildConnection(context, store),
                  _buildAdvanced(context, store),
                  SingleChildScrollView(
                    child: HarborConfigForwards(host: host),
                  ),
                ][_tabController.index],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Tab 1: Dashboard (Visual Summary) ---
  Widget _buildDashboard(BuildContext context, SSHHost host) {
    final theme = MacosTheme.of(context);
    final isConnected = context.watch<SSHStore>().isConnected(host.hostAlias);

    final dark = theme.brightness == Brightness.dark;
    final muted = HarborColors.of(context).muted;
    final surface = HarborColors.of(context).surface;
    final border = HarborColors.of(context).border;
    final status = isConnected ? const Color(0xFF5DBB8A) : muted;
    Widget info(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: TextStyle(fontSize: 12, color: muted)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.typography.body.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.desktopcomputer,
                      size: 18,
                      color: muted,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Connection details',
                      style: theme.typography.headline.copyWith(fontSize: 13),
                    ),
                    const Spacer(),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: status,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'Tunnels running' : 'Tunnels inactive',
                      style: TextStyle(fontSize: 11, color: status),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                info(
                  'Host',
                  host.hostName.isEmpty ? 'Not configured' : host.hostName,
                ),
                info(
                  'Username',
                  host.user.isEmpty ? 'Default user' : host.user,
                ),
                info('Port', host.port.isEmpty ? '22' : host.port),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'SSH command',
                  style: theme.typography.headline.copyWith(fontSize: 13),
                ),
              ),
              HarborIconButton(
                icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                onPressed: () => context.read<SSHStore>().copyHostCommand(host),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Run this command in your terminal to connect.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            child: FutureBuilder<String>(
              future: context.read<SSHStore>().commandFor(host),
              builder: (context, snapshot) => SelectableText(
                snapshot.hasError
                    ? 'Could not generate SSH command: ${snapshot.error}'
                    : snapshot.data ?? 'Resolving SSH command…',
                style: TextStyle(
                  fontFamily: 'Menlo',
                  color: dark
                      ? const Color(0xFFD8DFEB)
                      : const Color(0xFF34435C),
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Port forwarding',
            style: theme.typography.headline.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (host.dynamicForward.isNotEmpty)
            _buildTunnelRow(
              'SOCKS5',
              'localhost:${host.dynamicForward}',
              'Internet',
            ),
          for (var fwd in host.localForwards)
            _buildTunnelRow(
              'Local',
              'localhost:${fwd.split(':')[0]}',
              fwd.split(':').sublist(1).join(':'),
            ),
          for (final forward in host.remoteForwards)
            _buildTunnelRow(
              'Remote',
              'server:${forward.split(':').first}',
              forward.split(':').sublist(1).join(':'),
            ),
          if (host.dynamicForward.isEmpty &&
              host.localForwards.isEmpty &&
              host.remoteForwards.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.arrow_right_arrow_left,
                    size: 16,
                    color: muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add forwarding settings in the Port mapping tab.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTunnelRow(String type, String from, String to) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CupertinoColors.systemGrey.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: HarborColors.copper.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: HarborColors.copper.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              type,
              style: const TextStyle(
                color: HarborColors.copper,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              from,
              overflow: TextOverflow.ellipsis,
              style: MacosTheme.of(context).typography.body,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              CupertinoIcons.arrow_right,
              size: 14,
              color: CupertinoColors.systemGrey,
            ),
          ),
          Flexible(
            child: Text(
              to,
              overflow: TextOverflow.ellipsis,
              style: MacosTheme.of(context).typography.body,
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab 2: General ---
  Widget _buildGeneral(BuildContext context, SSHStore store) {
    final host = store.currentHost!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Group'),
                    Text(
                      store.groupFor(host),
                      style: MacosTheme.of(context).typography.body,
                    ),
                  ],
                ),
              ),
              HarborButton(
                secondary: true,
                onPressed: () => showGroupEditor(context, store, host),
                label: 'Change group…',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Tags'),
                    Text(
                      store.tagsFor(host).isEmpty
                          ? 'No tags'
                          : store.tagsFor(host).map((tag) => '#$tag').join(' '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              HarborButton(
                label: 'Edit tags…',
                secondary: true,
                onPressed: () => showHostTagsEditor(context, store, host),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              HostMonogram(
                host: host,
                color: store.colorForGroup(store.groupFor(host)),
              ),
              const SizedBox(width: 12),
              HarborButton(
                label: 'Choose icon',
                secondary: true,
                onPressed: () => showHostIconPicker(context, store, host),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildLabel("Host Alias (Display Name)"),
          HarborTextField(
            autofocus: host.hostName.isEmpty,
            initialValue: host.hostAlias,
            validator: (value) => store.validateHostAlias(host, value),
            onChanged: (v) {
              store.renameHost(host, v);
            },
          ),
          const SizedBox(height: 20),
          _buildLabel("HostName (IP Address or Domain)"),
          HarborTextField(
            initialValue: host.hostName,
            onChanged: (v) {
              host.hostName = v;
              store.markDirty(host.hostAlias);
            },
          ),
          const SizedBox(height: 24),
          HarborButton(
            color: CupertinoColors.destructiveRed,
            label: "Delete Host",
            onPressed: () => confirmDeleteHost(context, store, host),
          ),
        ],
      ),
    );
  }

  // --- Tab 3: Connection (Keys & User) ---
  Widget _buildConnection(BuildContext context, SSHStore store) {
    final host = store.currentHost!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("User"),
                    HarborTextField(
                      initialValue: host.user,
                      onChanged: (v) {
                        host.user = v;
                        store.markDirty(host.hostAlias);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Port"),
                    HarborTextField(
                      initialValue: host.port,
                      onChanged: (v) {
                        host.port = v;
                        store.markDirty(host.hostAlias);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildLabel("Private Key (IdentityFile)"),
          Row(
            children: [
              Expanded(
                child: HarborTextField(
                  initialValue: host.identityFile,
                  readOnly: true,
                  placeholder: "Default (~/.ssh/id_rsa)",
                ),
              ),
              const SizedBox(width: 8),
              HarborButton(
                secondary: true,
                label: "Select...",
                onPressed: () => _showKeyPicker(context, store, host),
              ),
              const SizedBox(width: 8),
              HarborButton(
                label: "Create New",
                onPressed: () => _showKeyGenerator(context, store),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 10),
          _buildLabel('SSH over proxy'),
          const SizedBox(height: 6),
          CupertinoSlidingSegmentedControl<String>(
            groupValue: store.proxyFor(host).mode,
            children: const {
              'off': Text('Off'),
              'system': Text('System'),
              'socks': Text('SOCKS5'),
              'http': Text('HTTP'),
            },
            onValueChanged: (value) {
              if (value != null) {
                store.updateConnectionProxy(
                  host,
                  store.proxyFor(host).copyWith(mode: value),
                );
              }
            },
          ),
          if (['socks', 'http'].contains(store.proxyFor(host).mode)) ...[
            const SizedBox(height: 12),
            _buildLabel('Proxy host'),
            HarborTextField(
              key: ValueKey('connection-proxy-host-${host.hostAlias}'),
              initialValue: store.proxyFor(host).host,
              validator: (value) =>
                  RegExp(r'^[a-zA-Z0-9_.:-]+$').hasMatch(value.trim()) &&
                      !value.trim().startsWith('-')
                  ? null
                  : 'Enter a hostname or IP address.',
              onChanged: (value) => store.updateConnectionProxy(
                host,
                store.proxyFor(host).copyWith(host: value.trim()),
              ),
            ),
            const SizedBox(height: 12),
            _buildLabel('Proxy port'),
            HarborTextField(
              key: ValueKey('connection-proxy-port-${host.hostAlias}'),
              initialValue: '${store.proxyFor(host).port}',
              validator: (value) {
                final port = int.tryParse(value);
                return port != null && port > 0 && port <= 65535
                    ? null
                    : 'Invalid port.';
              },
              onChanged: (value) {
                final port = int.tryParse(value);
                if (port != null && port > 0 && port <= 65535) {
                  store.updateConnectionProxy(
                    host,
                    store.proxyFor(host).copyWith(port: port),
                  );
                }
              },
            ),
          ],
          const SizedBox(height: 7),
          Text(
            'Applies to new SSH sessions and this connection’s port mappings. A custom ProxyCommand takes precedence.',
            style: TextStyle(
              fontSize: 11,
              color: HarborColors.of(context).muted,
            ),
          ),
          const SizedBox(height: 20),
          _buildLabel("Jump host (ProxyJump)"),
          HarborTextField(
            initialValue: host.proxyJump,
            placeholder: 'bastion or user@host:22',
            onChanged: (value) {
              host.proxyJump = value.trim();
              store.markDirty(host.hostAlias);
            },
          ),
          const SizedBox(height: 7),
          Text(
            'Use a saved SSH alias or comma-separated hops. Leave empty for a direct connection.',
            style: TextStyle(
              fontSize: 11,
              color: HarborColors.of(context).muted,
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab 4: Advanced ---
  Widget _buildAdvanced(BuildContext context, SSHStore store) =>
      HarborAdvancedOptionsPage(host: store.currentHost!);

  // --- Dialogs ---

  void _showKeyPicker(
    BuildContext context,
    SSHStore store,
    SSHHost host,
  ) async {
    try {
      final path = await const MethodChannel(
        'harbor/files',
      ).invokeMethod<String>('pickIdentityFile');
      if (!context.mounted || path == null || !store.hosts.contains(host)) {
        return;
      }
      host.identityFile = path;
      store.markDirty(host.hostAlias);
    } catch (error) {
      if (!context.mounted) return;
      showHarborDialog(
        context: context,
        builder: (dialogContext) => HarborAlert(
          appIcon: const Icon(CupertinoIcons.exclamationmark_triangle),
          title: const Text('Could not select identity file'),
          message: Text('$error'),
          primaryButton: HarborButton(
            label: 'OK',
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ),
      );
    }
  }

  void _showKeyGenerator(BuildContext context, SSHStore store) {
    final filenameCtrl = TextEditingController(text: "id_ed25519_new");
    String type = "ed25519";

    showHarborSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return MacosSheet(
            child: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Generate New Key Pair",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    HarborTextField(
                      controller: filenameCtrl,
                      prefix: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text("Filename:"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Simple Toggle for Type
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Type: "),
                        const SizedBox(width: 10),
                        MacosRadioButton<String>(
                          groupValue: type,
                          value: "ed25519",
                          onChanged: (v) => setState(() => type = v!),
                        ),
                        const Text("ED25519"),
                        const SizedBox(width: 10),
                        MacosRadioButton<String>(
                          groupValue: type,
                          value: "rsa",
                          onChanged: (v) => setState(() => type = v!),
                        ),
                        const Text("RSA"),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HarborButton(
                          secondary: true,
                          label: "Cancel",
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 10),
                        HarborButton(
                          label: "Generate",
                          onPressed: () async {
                            final res = await store.generateKey(
                              filename: filenameCtrl.text,
                              type: type,
                            );
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                            // Show alert result (simplified)
                            debugPrint(res);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
      ),
    );
  }
}

class LibraryHostRow extends StatefulWidget {
  final SSHHost host;
  final bool selected;
  final bool dragging;
  final bool slidingSelection;
  final VoidCallback onTap;
  final GestureTapUpCallback onSecondaryTapUp;
  const LibraryHostRow({
    super.key,
    required this.host,
    required this.selected,
    this.dragging = false,
    this.slidingSelection = false,
    required this.onTap,
    required this.onSecondaryTapUp,
  });
  @override
  State<LibraryHostRow> createState() => _LibraryHostRowState();
}

class _LibraryHostRowState extends State<LibraryHostRow> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final dark = MacosTheme.of(context).brightness == Brightness.dark;
    final colors = HarborColors.of(context);
    final showHover = hovered && !widget.dragging;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: AnimatedContainer(
          duration: harborHoverMotion(context),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: Color.alphaBlend(
              widget.selected && !widget.slidingSelection
                  ? colors.accent.withValues(alpha: dark ? 0.16 : 0.12)
                  : Colors.transparent,
              showHover
                  ? CupertinoColors.systemGrey.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              HostMonogram(
                host: widget.host,
                size: 26,
                color: store.colorForGroup(store.groupFor(widget.host)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.host.hostAlias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${store.preferences.showAddresses ? widget.host.hostName : store.groupFor(widget.host)}${store.tagsFor(widget.host).isEmpty ? '' : ' · ${store.tagsFor(widget.host).map((tag) => '#$tag').join(' ')}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 20,
                child: store.isDirty(widget.host.hostAlias)
                    ? const Tooltip(
                        message: 'Unsaved changes',
                        child: Icon(
                          CupertinoIcons.pencil,
                          size: 13,
                          color: CupertinoColors.systemOrange,
                        ),
                      )
                    : null,
              ),
              IgnorePointer(
                ignoring: !showHover && !store.isFavorite(widget.host),
                child: AnimatedOpacity(
                  duration: harborHoverMotion(context),
                  curve: Curves.easeOutCubic,
                  opacity: showHover || store.isFavorite(widget.host) ? 1 : 0,
                  child: HarborFavoriteButton(host: widget.host, size: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> launchHostTerminal(
  BuildContext context,
  SSHStore store,
  SSHHost host,
) async {
  try {
    await store.openTerminal(host);
  } catch (e) {
    if (!context.mounted) return;
    showHarborDialog(
      context: context,
      builder: (dialogContext) => HarborAlert(
        appIcon: const Icon(CupertinoIcons.exclamationmark_triangle),
        title: const Text('Could not open Terminal'),
        message: Text('$e'),
        primaryButton: HarborButton(
          onPressed: () => Navigator.pop(dialogContext),
          label: 'OK',
        ),
      ),
    );
  }
}

Future<void> showHostTagsEditor(
  BuildContext context,
  SSHStore store,
  SSHHost host,
) async {
  final controller = TextEditingController(
    text: store.tagsFor(host).join(', '),
  );
  final suggestions =
      store.hostTags.values.expand((tags) => tags).toSet().toList()..sort();
  final value = await showHarborDialog<String>(
    context: context,
    builder: (dialogContext) => HarborAlert(
      appIcon: const Icon(CupertinoIcons.tag),
      title: const Text('Server tags'),
      message: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Separate tags with commas. Clear the field to remove all tags.',
          ),
          const SizedBox(height: 12),
          HarborTextField(
            controller: controller,
            autofocus: true,
            placeholder: 'work, production',
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in suggestions)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: Size.zero,
                    onPressed: () {
                      final tags = ManagedMapping.normalizeTags(
                        controller.text.split(RegExp('[,，]')),
                      );
                      if (!tags.remove(tag)) tags.add(tag);
                      controller.text = tags.join(', ');
                    },
                    child: Text('#$tag', style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ],
      ),
      secondaryButton: HarborButton(
        label: 'Cancel',
        secondary: true,
        onPressed: () => Navigator.pop(dialogContext),
      ),
      primaryButton: HarborButton(
        label: 'Save tags',
        onPressed: () => Navigator.pop(dialogContext, controller.text),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 150));
  controller.dispose();
  if (value != null) await store.setHostTags(host, value.split(RegExp('[,，]')));
}

Future<void> showGroupEditor(
  BuildContext context,
  SSHStore store,
  SSHHost host,
) async {
  final controller = TextEditingController(
    text: store.groupFor(host) == 'Ungrouped' ? '' : store.groupFor(host),
  );
  final group = await showHarborSheet<String>(
    context: context,
    builder: (dialogContext) => MacosSheet(
      child: SizedBox(
        width: 400,
        height: 280,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Organize host',
                style: MacosTheme.of(context).typography.title2,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose an existing group or enter a new name.',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(height: 16),
              HarborTextField(
                controller: controller,
                autofocus: true,
                placeholder: 'Group name (empty to ungroup)',
                onSubmitted: (value) => Navigator.pop(dialogContext, value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final name in store.groupNames)
                        HarborButton(
                          secondary: true,
                          onPressed: () => controller.text = name,
                          label: name,
                        ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  HarborButton(
                    secondary: true,
                    onPressed: () => Navigator.pop(dialogContext),
                    label: 'Cancel',
                  ),
                  const SizedBox(width: 8),
                  HarborButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, controller.text),
                    label: 'Save group',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  // Sheet removal is animated; keep the field controller alive until it finishes.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  controller.dispose();
  if (group != null) await store.setGroup(host, group);
}

final _quickConnectRoutes = Expando<RawDialogRoute<SSHHost>>();

Future<void> showQuickConnect(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final active = _quickConnectRoutes[navigator];
  if (active != null) {
    if (active.isCurrent) navigator.pop();
    return;
  }
  final store = context.read<SSHStore>();
  final route = RawDialogRoute<SSHHost>(
    barrierDismissible: true,
    barrierLabel: 'Dismiss Quick Connect',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: harborMotion(context, 320),
    pageBuilder: (_, _, _) => ChangeNotifierProvider.value(
      value: store,
      child: const QuickConnectSheet(),
    ),
    // Center outside the filter so its layer contains only the panel,
    // rather than allocating a texture the size of the whole window.
    transitionBuilder: (_, animation, _, child) => Center(
      child: HarborQuickConnectTransition(animation: animation, child: child),
    ),
  );
  _quickConnectRoutes[navigator] = route;
  SSHHost? host;
  try {
    host = await navigator.push(route);
  } finally {
    _quickConnectRoutes[navigator] = null;
  }
  if (host == null || !context.mounted) return;
  store.selectHost(host);
  await launchHostTerminal(context, store, host);
}

class QuickConnectSheet extends StatefulWidget {
  final bool autofocus;
  const QuickConnectSheet({super.key, this.autofocus = true});
  @override
  State<QuickConnectSheet> createState() => _QuickConnectSheetState();
}

class _QuickConnectSheetState extends State<QuickConnectSheet> {
  String query = '';
  int selected = 0;
  final controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final matches =
        store.hosts.where((host) => store.matchesHost(host, query)).toList()
          ..sort((a, b) {
            final favoriteOrder =
                (store.isFavorite(b) ? 1 : 0) - (store.isFavorite(a) ? 1 : 0);
            return favoriteOrder != 0
                ? favoriteOrder
                : a.hostAlias.compareTo(b.hostAlias);
          });
    if (selected >= matches.length) selected = 0;
    void choose() {
      if (matches.isNotEmpty) Navigator.pop(context, matches[selected]);
    }

    return MacosSheet(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 520,
        height: 430,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape ||
                (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.keyK &&
                    HardwareKeyboard.instance.isMetaPressed)) {
              Navigator.pop(context);
              return KeyEventResult.handled;
            }
            if (matches.isNotEmpty &&
                (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp)) {
              setState(
                () => selected =
                    (selected +
                        (event.logicalKey == LogicalKeyboardKey.arrowDown
                            ? 1
                            : -1)) %
                    matches.length,
              );
              if (controller.hasClients) {
                controller.jumpTo(
                  (selected * 56.0).clamp(
                    0.0,
                    controller.position.maxScrollExtent,
                  ),
                );
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Quick connect',
                      style: MacosTheme.of(context).typography.title2,
                    ),
                    const Spacer(),
                    HarborIconButton(
                      icon: const Icon(CupertinoIcons.xmark, size: 14),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                HarborTextField(
                  autofocus: widget.autofocus,
                  placeholder: 'Search hosts, addresses or groups…',
                  onChanged: (value) => setState(() {
                    query = value;
                    selected = 0;
                  }),
                  onSubmitted: (_) => choose(),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: matches.isEmpty
                      ? const Center(child: Text('No matching hosts'))
                      : ListView.builder(
                          controller: controller,
                          itemExtent: 56,
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final host = matches[index];
                            return GestureDetector(
                              onTap: () => Navigator.pop(context, host),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: selected == index
                                      ? CupertinoColors.activeBlue.withValues(
                                          alpha: 0.15,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      store.isFavorite(host)
                                          ? CupertinoIcons.star_fill
                                          : CupertinoIcons.desktopcomputer,
                                      size: 16,
                                      color: store.isFavorite(host)
                                          ? CupertinoColors.systemYellow
                                          : CupertinoColors.systemGrey,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            host.hostAlias,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            '${host.hostName} · ${store.groupFor(host)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: CupertinoColors.systemGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (index == selected)
                                      const Icon(
                                        CupertinoIcons.return_icon,
                                        size: 14,
                                        color: CupertinoColors.systemGrey,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '↑ ↓ Select     ↵ Open Terminal     esc Close',
                  style: TextStyle(
                    fontSize: 11,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
