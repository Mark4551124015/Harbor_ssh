import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // Used for ImageFilter
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Used for Clipboard
import 'package:macos_ui/macos_ui.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ----------------------
// 1. App Entry Point
// ----------------------
void main() {
  runApp(const AppRoot());
}

// 定义一个强制不显示滚动条的 ScrollBehavior
class NoScrollbarBehavior extends MacosScrollBehavior {
  const NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child; // 直接返回 child，不包裹 Scrollbar
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

  const ResizableSidebar({
    super.key,
    required this.minWidth,
    required this.startWidth,
    required this.maxWidth,
    required this.child,
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
    _width = _width.clamp(widget.minWidth, widget.maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Row(
        children: [
          Expanded(child: widget.child),
          // Drag handle
          MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _width = (_width + details.delta.dx)
                      .clamp(widget.minWidth, widget.maxWidth);
                });
              },
              child: Container(
                width: 4,
                color: MacosTheme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF37383B)
                    : const Color(0xFFDDDFE3),
                alignment: Alignment.center,
                child: Container(
                  width: 2,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SSHStore(),
      child: MacosApp(
        title: 'SSH Manager',
        // 全局禁用默认滚动条，防止 Flutter 自动给 ListView 加原生滚动条
        scrollBehavior: const NoScrollbarBehavior(),
        theme: MacosThemeData.light().copyWith(
          canvasColor: const Color(0xFFF5F5F7),
        ),
        darkTheme: MacosThemeData.dark().copyWith(
          canvasColor: const Color(0xFF282C34),
        ),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: const MainWindow(),
      ),
    );
  }
}

// ----------------------
// 2. Data Model (保持不变)
// ----------------------

class SSHHost {
  String hostAlias;
  String hostName;
  String user;
  String port;
  String identityFile;

  List<String> localForwards;
  String dynamicForward; // SOCKS5

  Map<String, String> advancedOptions;

  SSHHost({
    required this.hostAlias,
    this.hostName = '',
    this.user = '',
    this.port = '22',
    this.identityFile = '',
    this.dynamicForward = '',
    List<String>? localForwards,
    Map<String, String>? advancedOptions,
  })  : localForwards = localForwards ?? [],
        advancedOptions = advancedOptions ?? {};

  String toConfigBlock() {
    final buffer = StringBuffer();
    buffer.writeln('Host $hostAlias');
    if (hostName.isNotEmpty) buffer.writeln('  HostName $hostName');
    if (user.isNotEmpty) buffer.writeln('  User $user');
    if (port != '22' && port.isNotEmpty) buffer.writeln('  Port $port');
    if (identityFile.isNotEmpty) buffer.writeln('  IdentityFile $identityFile');
    if (dynamicForward.isNotEmpty)
      buffer.writeln('  DynamicForward $dynamicForward');

    for (var fwd in localForwards) {
      final parts = fwd.split(':');
      if (parts.length >= 2) {
        buffer.writeln('  LocalForward ${fwd.replaceFirst(':', ' ')}');
      } else {
        buffer.writeln('  LocalForward $fwd');
      }
    }

    advancedOptions.forEach((k, v) {
      buffer.writeln('  $k $v');
    });

    return buffer.toString();
  }

  String getPreviewCommand() {
    final sb = StringBuffer('ssh');
    if (port != '22') sb.write(' -p $port');
    if (identityFile.isNotEmpty) sb.write(' -i $identityFile');
    if (dynamicForward.isNotEmpty) sb.write(' -D $dynamicForward');
    for (var fwd in localForwards) sb.write(' -L $fwd');

    advancedOptions.forEach((k, v) {
      sb.write(' -o $k=$v');
    });

    sb.write(' ${user.isEmpty ? '' : '$user@'}$hostName');
    return sb.toString();
  }
}

// ----------------------
// 3. Logic Core (Store) (保持不变)
// ----------------------

class SSHStore extends ChangeNotifier {
  List<SSHHost> hosts = [];
  List<SSHHost> filteredHosts = [];
  int _selectedIndex = 0;
  String _searchQuery = "";

  final Map<String, Process> _activeProxies = {};
  final Map<String, bool> _loadingStates = {};
  final Set<String> _dirtyHosts = {};

  int get selectedIndex => _selectedIndex;

  SSHHost? get currentHost {
    if (filteredHosts.isEmpty) return null;
    if (_selectedIndex >= filteredHosts.length) return filteredHosts.last;
    return filteredHosts[_selectedIndex];
  }

  final Set<String> favorites = {};
  final Map<String, String> hostGroups = {};
  File? _metadataFile;
  Future<void> _pendingMetadata = Future.value();
  String? metadataError;

  SSHStore({bool load = true, File? metadataFile})
      : _metadataFile = metadataFile {
    if (load) initialize();
  }

  Future<void> initialize() async {
    await loadMetadata();
    await loadConfig();
  }

  String groupFor(SSHHost host) => hostGroups[host.hostAlias] ?? 'Ungrouped';
  bool isFavorite(SSHHost host) => favorites.contains(host.hostAlias);

  Future<void> loadMetadata() async {
    try {
      _metadataFile ??= File(p.join(
          (await getApplicationSupportDirectory()).path, 'host-library.json'));
      if (await _metadataFile!.exists()) {
        final data = jsonDecode(await _metadataFile!.readAsString())
            as Map<String, dynamic>;
        favorites.addAll(List<String>.from(data['favorites'] ?? []));
        hostGroups.addAll(Map<String, String>.from(data['groups'] ?? {}));
      }
    } catch (e) {
      metadataError = 'Could not load your host library: $e';
    }
    notifyListeners();
  }

  Future<void> saveMetadata() {
    final contents =
        jsonEncode({'favorites': favorites.toList(), 'groups': hostGroups});
    _pendingMetadata = _pendingMetadata.then((_) async {
      try {
        _metadataFile ??= File(p.join(
            (await getApplicationSupportDirectory()).path,
            'host-library.json'));
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

  void renameHost(SSHHost host, String alias) {
    final old = host.hostAlias;
    host.hostAlias = alias;
    if (favorites.remove(old)) favorites.add(alias);
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
          .where((h) =>
              h.hostAlias.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              h.hostName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              groupFor(h).toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

  bool isConnected(String hostAlias) => _activeProxies.containsKey(hostAlias);
  bool isLoading(String hostAlias) => _loadingStates[hostAlias] ?? false;
  bool isDirty(String hostAlias) => _dirtyHosts.contains(hostAlias);

  void markDirty(String hostAlias) {
    if (!_dirtyHosts.contains(hostAlias)) {
      _dirtyHosts.add(hostAlias);
      notifyListeners();
    }
  }

  Future<void> loadConfig() async {
    final home = Platform.environment['HOME'];
    final configPath = File('$home/.ssh/config');

    _dirtyHosts.clear();

    if (!await configPath.exists()) {
      hosts = [];
      _applyFilter();
      return;
    }

    try {
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
            case 'dynamicforward':
              current.dynamicForward = value;
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
            case 'compression':
            case 'serveraliveinterval':
            case 'serveralivecountmax':
            case 'exitonforwardfailure':
            case 'stricthostkeychecking':
            case 'userknownhostsfile':
            case 'forwardx11':
              current.advancedOptions[parts[0]] = value;
              break;
          }
        }
      }
      if (current != null) hosts.add(current);
      _applyFilter();
    } catch (e) {
      debugPrint("Error loading config: $e");
    }
  }

  Future<void> saveConfig() async {
    final home = Platform.environment['HOME'];
    final configPath = File('$home/.ssh/config');

    if (!await configPath.parent.exists()) {
      await configPath.parent.create(recursive: true);
    }

    final buffer = StringBuffer();
    for (var host in hosts) {
      buffer.writeln(host.toConfigBlock());
    }

    try {
      if (await configPath.exists()) {
        await configPath.copy('${configPath.path}.bak');
      }
      await configPath.writeAsString(buffer.toString());

      _dirtyHosts.clear();
      notifyListeners();
    } catch (e) {
      debugPrint("Error saving config: $e");
    }
  }

  void addHost() {
    final newHost = SSHHost(hostAlias: 'NewHost', hostName: '192.168.1.1');
    hosts.add(newHost);
    _searchQuery = "";
    _applyFilter();
    _selectedIndex = filteredHosts.indexOf(newHost);
    markDirty(newHost.hostAlias);
  }

  void deleteCurrentHost() {
    if (currentHost == null) return;
    stopProxy(currentHost!.hostAlias);
    hosts.remove(currentHost);
    _applyFilter();
    if (_selectedIndex >= filteredHosts.length)
      _selectedIndex = filteredHosts.length - 1;
    if (_selectedIndex < 0) _selectedIndex = 0;
    saveConfig();
  }

  void deleteHost(SSHHost host) {
    stopProxy(host.hostAlias);
    hosts.remove(host);
    _applyFilter();
    if (_selectedIndex >= filteredHosts.length)
      _selectedIndex = filteredHosts.length - 1;
    if (_selectedIndex < 0) _selectedIndex = 0;
    saveConfig();
  }

  Future<List<String>> listKeys() async {
    final home = Platform.environment['HOME'];
    final sshDir = Directory('$home/.ssh');
    if (!await sshDir.exists()) return [];

    final entities = await sshDir.list().toList();
    final keys = <String>[];
    for (var e in entities) {
      if (e is File) {
        final name = p.basename(e.path);
        if (!name.endsWith('.pub') &&
            name != 'known_hosts' &&
            name != 'config' &&
            !name.startsWith('.')) {
          keys.add(e.path);
        }
      }
    }
    return keys;
  }

  Future<String> generateKey(
      {required String filename,
      required String type,
      String passphrase = ""}) async {
    final home = Platform.environment['HOME'];
    final keyPath = '$home/.ssh/$filename';

    if (await File(keyPath).exists()) {
      return "Error: File already exists";
    }

    try {
      await Process.run('ssh-keygen', [
        '-t',
        type,
        '-f',
        keyPath,
        '-N',
        passphrase,
        '-C',
        'generated-by-ssh-tool'
      ]);
      return keyPath;
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<void> copyCommandToClipboard(BuildContext context) async {
    if (currentHost == null) return;
    final h = currentHost!;
    final cmd = h.getPreviewCommand();

    await Clipboard.setData(ClipboardData(text: cmd));

    if (context.mounted) {
      showMacosAlertDialog(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: const Icon(CupertinoIcons.checkmark_circle_fill,
              color: CupertinoColors.activeGreen),
          title: const Text("Command Copied"),
          message:
              const Text("The SSH command has been copied to your clipboard."),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            child: const Text("OK"),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
  }

  Future<void> openTerminal([SSHHost? target]) async {
    final host = target ?? currentHost;
    if (host == null) return;
    final cmd = host.getPreviewCommand();
    final escaped = cmd.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    final result = await Process.run('osascript', [
      '-e',
      'tell application "Terminal"\n do script "$escaped"\n activate\nend tell'
    ]);
    if (result.exitCode != 0) throw Exception(result.stderr.toString().trim());
  }

  Future<String?> toggleConnection() async {
    if (currentHost == null) return null;
    final alias = currentHost!.hostAlias;

    if (isConnected(alias)) {
      await stopProxy(alias);
      return null;
    } else {
      return await startProxy(alias);
    }
  }

  Future<String?> startProxy(String alias) async {
    _loadingStates[alias] = true;
    notifyListeners();

    final h = hosts.firstWhere((e) => e.hostAlias == alias);

    List<String> args = ['-N', '-v'];
    if (h.port != '22') args.addAll(['-p', h.port]);
    if (h.identityFile.isNotEmpty) args.addAll(['-i', h.identityFile]);
    if (h.dynamicForward.isNotEmpty) args.addAll(['-D', h.dynamicForward]);
    for (var fwd in h.localForwards) args.addAll(['-L', fwd]);

    args.addAll(['-o', 'ExitOnForwardFailure=yes']);

    bool hasCustomTimeout =
        h.advancedOptions.keys.any((k) => k.toLowerCase() == 'connecttimeout');
    if (!hasCustomTimeout) {
      args.addAll(['-o', 'ConnectTimeout=15']);
    }

    h.advancedOptions.forEach((k, v) {
      if (k.toLowerCase() != 'exitonforwardfailure') {
        args.addAll(['-o', '$k=$v']);
      }
    });

    args.add('${h.user.isEmpty ? '' : '${h.user}@'}${h.hostName}');

    try {
      debugPrint("Starting background SSH: ssh ${args.join(' ')}");

      final process = await Process.start('ssh', args);

      final Completer<String?> connectionCompleter = Completer();
      final StringBuffer stderrBuffer = StringBuffer();

      process.stderr.transform(utf8.decoder).listen((data) {
        stderrBuffer.write(data);

        if (!connectionCompleter.isCompleted) {
          if (data.contains("Entering interactive session") ||
              data.contains("Authentication succeeded") ||
              data.contains("forking to background")) {
            debugPrint("SSH Connection established successfully.");
            connectionCompleter.complete(null);
          }
        }
      });

      process.exitCode.then((exitCode) {
        debugPrint("SSH process for $alias exited with $exitCode");
        if (_activeProxies.containsKey(alias)) {
          _activeProxies.remove(alias);
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

      final result = await connectionCompleter.future;

      _loadingStates[alias] = false;

      if (result == null) {
        _activeProxies[alias] = process;
      } else {
        process.kill();
      }

      notifyListeners();
      return result;
    } catch (e) {
      _loadingStates[alias] = false;
      notifyListeners();
      return "System Error: $e";
    }
  }

  Future<void> stopProxy(String alias) async {
    _loadingStates[alias] = false;
    final process = _activeProxies[alias];
    if (process != null) {
      process.kill();
      _activeProxies.remove(alias);
      notifyListeners();
    }
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

class _MainWindowState extends State<MainWindow> {
  // 1. Independent ScrollController for the list content
  final ScrollController _listScrollController = ScrollController();

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final isDarkMode = MacosTheme.of(context).brightness == Brightness.dark;

    final BoxDecoration sidebarDecoration = BoxDecoration(
      color: isDarkMode ? const Color(0xFF252629) : const Color(0xFFF1F2F4),
      border: Border(
          right: BorderSide(
        color: isDarkMode ? const Color(0xFF37383B) : const Color(0xFFDDDFE3),
        width: 0.5,
      )),
    );

    final sections = <String, List<SSHHost>>{};
    final favoriteHosts = store.filteredHosts.where(store.isFavorite).toList();
    if (favoriteHosts.isNotEmpty) sections['Favorites'] = favoriteHosts;
    final groupNames = store.filteredHosts.map(store.groupFor).toSet().toList()
      ..sort();
    for (final group in groupNames) {
      sections[group == 'Favorites' ? 'Group · Favorites' : group] =
          store.filteredHosts.where((h) => store.groupFor(h) == group).toList();
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            showQuickConnect(context),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            store.saveConfig(),
      },
      child: Focus(
          autofocus: true,
          child: MacosWindow(
            backgroundColor:
                isDarkMode ? const Color(0xFF252629) : const Color(0xFFF1F2F4),
            child: Row(children: [
              ResizableSidebar(
                  minWidth: 200,
                  startWidth: 224,
                  maxWidth: 300,
                  child: Container(
                      decoration: sidebarDecoration,
                      child: Column(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Library',
                                      style: MacosTheme.of(context)
                                          .typography
                                          .title2
                                          .copyWith(
                                              fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 14),
                                  PushButton(
                                      controlSize: ControlSize.large,
                                      secondary: true,
                                      onPressed: () =>
                                          showQuickConnect(context),
                                      child: const Row(children: [
                                        Icon(CupertinoIcons.search, size: 14),
                                        SizedBox(width: 8),
                                        Expanded(
                                            child: Text('Quick connect',
                                                style:
                                                    TextStyle(fontSize: 12))),
                                        Text('⌘K',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    CupertinoColors.systemGrey))
                                      ])),
                                  const SizedBox(height: 12),
                                  MacosSearchField(
                                      placeholder: 'Filter hosts or groups',
                                      onChanged: store.search,
                                      placeholderStyle: TextStyle(
                                          fontSize: 11,
                                          color: isDarkMode
                                              ? const Color(0xFF9B9DA5)
                                              : const Color(0xFF737680))),
                                ])),
                        if (store.metadataError != null)
                          Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(store.metadataError!,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: CupertinoColors.systemOrange))),
                        Expanded(
                            child: ListView(
                                controller: _listScrollController,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                children: [
                              if (sections.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('No hosts found',
                                        style: TextStyle(fontSize: 12))),
                              for (final section in sections.entries) ...[
                                Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        10, 16, 10, 8),
                                    child: Text(section.key,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isDarkMode
                                                ? const Color(0xFF969AA3)
                                                : const Color(0xFF737680)))),
                                for (final host in section.value)
                                  LibraryHostRow(
                                      host: host,
                                      selected:
                                          identical(store.currentHost, host),
                                      onTap: () => store.selectIndex(
                                          store.filteredHosts.indexOf(host)),
                                      onSecondaryTapUp: (details) =>
                                          _showNativeContextMenu(
                                              context,
                                              details.globalPosition,
                                              host,
                                              store)),
                              ],
                            ])),
                        Padding(
                            padding: const EdgeInsets.all(12),
                            child: PushButton(
                                controlSize: ControlSize.large,
                                secondary: true,
                                onPressed: store.addHost,
                                child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(CupertinoIcons.add, size: 14),
                                      SizedBox(width: 8),
                                      Flexible(
                                          child: Text('New connection',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 12)))
                                    ]))),
                      ]))),
              Expanded(
                  child: ContentArea(
                      builder: (context, controller) => Container(
                          color: isDarkMode
                              ? const Color(0xFF1C1D20)
                              : const Color(0xFFFAFAFC),
                          child: const HostDetailTabs()))),
            ]),
          )),
    );
  }

  // ... (其余部分，_showNativeContextMenu, _ContextMenuItem, HostDetailTabs 等保持原样)
  // --- Hand-crafted Native-like Context Menu ---
  void _showNativeContextMenu(
      BuildContext context, Offset position, SSHHost host, SSHStore store) {
    final isDarkMode = MacosTheme.of(context).brightness == Brightness.dark;

    final double left = position.dx;
    final double top = position.dy;

    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (context, animation, __) {
        return Stack(
          children: [
            // Close menu on outside click
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),
            // Menu Body
            Positioned(
              left: left,
              top: top,
              child: FadeTransition(
                opacity: animation,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 160,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF303030).withOpacity(0.85)
                            : const Color(0xFFF5F5F5).withOpacity(0.85),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.white.withOpacity(0.15)
                              : Colors.black.withOpacity(0.1),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ContextMenuItem(
                            label: 'Delete Host',
                            onTap: () {
                              final rootContext =
                                  Navigator.of(context, rootNavigator: true)
                                      .context;
                              Navigator.of(context).pop();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _confirmDelete(rootContext, host, store);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ));
  }

  void _confirmDelete(BuildContext context, SSHHost host, SSHStore store) {
    showMacosAlertDialog(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const Icon(CupertinoIcons.trash),
        title: const Text("Delete Host?"),
        message: Text(
            "Are you sure you want to delete '${host.hostAlias}'? This cannot be undone."),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          color: CupertinoColors.destructiveRed,
          child: const Text("Delete"),
          onPressed: () {
            store.deleteHost(host);
            Navigator.of(dialogContext).pop();
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: const Text("Cancel"),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }
}

class _ContextMenuItem extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _ContextMenuItem({required this.label, required this.onTap});

  @override
  State<_ContextMenuItem> createState() => _ContextMenuItemState();
}

class _ContextMenuItemState extends State<_ContextMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
          decoration: BoxDecoration(
            color: _isHovered ? CupertinoColors.activeBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              color: _isHovered
                  ? Colors.white
                  : MacosTheme.of(context).typography.body.color,
            ),
          ),
        ),
      ),
    );
  }
}

class HostDetailTabs extends StatefulWidget {
  const HostDetailTabs({super.key});

  @override
  State<HostDetailTabs> createState() => _HostDetailTabsState();
}

class _HostDetailTabsState extends State<HostDetailTabs> {
  final _tabController = MacosTabController(initialIndex: 0, length: 4);

  @override
  void initState() {
    super.initState();
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

  Future<void> _handleConnect(
      BuildContext context, SSHStore store, SSHHost host) async {
    if (store.isDirty(host.hostAlias)) {
      showMacosAlertDialog(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: const Icon(CupertinoIcons.exclamationmark_triangle),
          title: const Text("Unsaved Changes"),
          message: const Text(
              "You have unsaved changes. Do you want to save them before connecting?"),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            child: const Text("Save & Connect"),
            onPressed: () async {
              Navigator.of(context).pop();
              await store.saveConfig();
              if (context.mounted) _performConnection(context, store);
            },
          ),
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } else {
      _performConnection(context, store);
    }
  }

  Future<void> _performConnection(BuildContext context, SSHStore store) async {
    final error = await store.toggleConnection();
    if (error != null && context.mounted) {
      showMacosAlertDialog(
        context: context,
        builder: (_) => MacosAlertDialog(
          appIcon: const Icon(CupertinoIcons.exclamationmark_triangle),
          title: const Text("Connection Failed"),
          message: Text(error),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            child: const Text("OK"),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final host = store.currentHost;

    if (host == null) {
      return const Center(child: Text("Select or Create a Host"));
    }

    final isConnected = store.isConnected(host.hostAlias);
    final isLoading = store.isLoading(host.hostAlias);
    final isDirty = store.isDirty(host.hostAlias);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: MacosTheme.of(context).dividerColor, width: 0.5))),
          child: Column(children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(CupertinoIcons.desktopcomputer,
                      size: 20, color: CupertinoColors.activeBlue)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(host.hostAlias,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MacosTheme.of(context)
                            .typography
                            .title2
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('${store.groupFor(host)} · ${host.hostName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: CupertinoColors.systemGrey)),
                  ])),
              MacosIconButton(
                  icon: Icon(
                      store.isFavorite(host)
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      size: 18,
                      color: store.isFavorite(host)
                          ? CupertinoColors.systemYellow
                          : CupertinoColors.systemGrey),
                  onPressed: () => store.toggleFavorite(host)),
              const SizedBox(width: 10),
              if (isDirty) ...[
                PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: store.saveConfig,
                    child: const Text('Save')),
                const SizedBox(width: 8),
              ],
              PushButton(
                  controlSize: ControlSize.regular,
                  onPressed: () => launchHostTerminal(context, store, host),
                  child: const Text('Open Terminal')),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                  child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (final entry in [
                  'Overview',
                  'General',
                  'Connection',
                  'Advanced'
                ].asMap().entries)
                  GestureDetector(
                      onTap: () {
                        _tabController.index = entry.key;
                      },
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                              color: _tabController.index == entry.key
                                  ? CupertinoColors.activeBlue
                                      .withValues(alpha: 0.13)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(entry.value,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _tabController.index == entry.key
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: _tabController.index == entry.key
                                      ? CupertinoColors.activeBlue
                                      : CupertinoColors.systemGrey)))),
              ])),
              if (isLoading)
                const ProgressCircle(radius: 8)
              else if (isConnected ||
                  host.dynamicForward.isNotEmpty ||
                  host.localForwards.isNotEmpty)
                PushButton(
                    controlSize: ControlSize.small,
                    secondary: true,
                    onPressed: () => _handleConnect(context, store, host),
                    child:
                        Text(isConnected ? 'Stop tunnels' : 'Start tunnels')),
            ]),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: IndexedStack(
              index: _tabController.index,
              children: [
                _buildDashboard(context, host),
                _buildGeneral(context, store),
                _buildConnection(context, store),
                _buildAdvanced(context, store),
              ],
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
    final muted = dark ? const Color(0xFFA6A9B2) : const Color(0xFF6B707B);
    final surface = dark ? const Color(0xFF25272C) : Colors.white;
    final border = dark ? const Color(0xFF373A41) : const Color(0xFFE1E3E8);
    final status = isConnected ? const Color(0xFF5DBB8A) : muted;
    Widget info(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            SizedBox(
                width: 108,
                child:
                    Text(label, style: TextStyle(fontSize: 12, color: muted))),
            Expanded(
                child: SelectableText(value,
                    style: theme.typography.body.copyWith(fontSize: 13))),
          ]),
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
                borderRadius: BorderRadius.circular(10)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(CupertinoIcons.desktopcomputer, size: 18, color: muted),
                const SizedBox(width: 10),
                Text('Connection details',
                    style: theme.typography.headline.copyWith(fontSize: 13)),
                const Spacer(),
                Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: status, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(isConnected ? 'Tunnels running' : 'Tunnels inactive',
                    style: TextStyle(fontSize: 11, color: status)),
              ]),
              const SizedBox(height: 12),
              info('Host',
                  host.hostName.isEmpty ? 'Not configured' : host.hostName),
              info('Username', host.user.isEmpty ? 'Default user' : host.user),
              info('Port', host.port.isEmpty ? '22' : host.port),
            ]),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
                child: Text('SSH command',
                    style: theme.typography.headline.copyWith(fontSize: 13))),
            MacosIconButton(
                icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                onPressed: () => Clipboard.setData(
                    ClipboardData(text: host.getPreviewCommand()))),
          ]),
          const SizedBox(height: 6),
          Text('Run this command in your terminal to connect.',
              style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border)),
            child: SelectableText(host.getPreviewCommand(),
                style: TextStyle(
                    fontFamily: 'Menlo',
                    color: dark
                        ? const Color(0xFFD8DFEB)
                        : const Color(0xFF34435C),
                    fontSize: 12,
                    height: 1.6)),
          ),
          const SizedBox(height: 24),
          Text('Port forwarding',
              style: theme.typography.headline.copyWith(fontSize: 13)),
          const SizedBox(height: 12),
          if (host.dynamicForward.isNotEmpty)
            _buildTunnelRow(
                'SOCKS5', 'localhost:${host.dynamicForward}', 'Internet'),
          for (var fwd in host.localForwards)
            _buildTunnelRow('Local', 'localhost:${fwd.split(':')[0]}',
                fwd.split(':').sublist(1).join(':')),
          if (host.dynamicForward.isEmpty && host.localForwards.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(CupertinoIcons.arrow_right_arrow_left,
                    size: 16, color: muted),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('No forwarding rules. Add them in Connection.',
                        style: TextStyle(fontSize: 12, color: muted))),
              ]),
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
          color: CupertinoColors.systemGrey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: CupertinoColors.systemGrey.withOpacity(0.1))),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: CupertinoColors.activeBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: CupertinoColors.activeBlue.withOpacity(0.2))),
            child: Text(type,
                style: const TextStyle(
                    color: CupertinoColors.activeBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Flexible(
              child: Text(from,
                  overflow: TextOverflow.ellipsis,
                  style: MacosTheme.of(context).typography.body)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(CupertinoIcons.arrow_right,
                size: 14, color: CupertinoColors.systemGrey),
          ),
          Flexible(
              child: Text(to,
                  overflow: TextOverflow.ellipsis,
                  style: MacosTheme.of(context).typography.body)),
        ],
      ),
    );
  }

  // --- Tab 2: General ---
  Widget _buildGeneral(BuildContext context, SSHStore store) {
    final host = store.currentHost!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _buildLabel('Group'),
                Text(store.groupFor(host),
                    style: MacosTheme.of(context).typography.body),
              ])),
          PushButton(
              controlSize: ControlSize.regular,
              secondary: true,
              onPressed: () => showGroupEditor(context, store, host),
              child: const Text('Change group…')),
        ]),
        const SizedBox(height: 24),
        _buildLabel("Host Alias (Display Name)"),
        MacosTextField(
          controller: TextEditingController(text: host.hostAlias),
          onChanged: (v) {
            store.renameHost(host, v);
          },
        ),
        const SizedBox(height: 20),
        _buildLabel("HostName (IP Address or Domain)"),
        MacosTextField(
          controller: TextEditingController(text: host.hostName),
          onChanged: (v) {
            host.hostName = v;
            store.markDirty(host.hostAlias);
          },
        ),
        const Spacer(),
        PushButton(
          controlSize: ControlSize.small,
          color: CupertinoColors.destructiveRed,
          child: const Text("Delete Host"),
          onPressed: () => store.deleteCurrentHost(),
        )
      ],
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
                  MacosTextField(
                    controller: TextEditingController(text: host.user),
                    onChanged: (v) {
                      host.user = v;
                      store.markDirty(host.hostAlias);
                    },
                  ),
                ],
              )),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel("Port"),
                    MacosTextField(
                      controller: TextEditingController(text: host.port),
                      onChanged: (v) {
                        host.port = v;
                        store.markDirty(host.hostAlias);
                      },
                    ),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 20),
          _buildLabel("Private Key (IdentityFile)"),
          Row(
            children: [
              Expanded(
                child: MacosTextField(
                  controller: TextEditingController(text: host.identityFile),
                  readOnly: true,
                  placeholder: "Default (~/.ssh/id_rsa)",
                ),
              ),
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.regular,
                secondary: true,
                child: const Text("Select..."),
                onPressed: () => _showKeyPicker(context, store, host),
              ),
              const SizedBox(width: 8),
              PushButton(
                controlSize: ControlSize.regular,
                child: const Text("Create New"),
                onPressed: () => _showKeyGenerator(context, store),
              )
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 10),
          Text("Port Forwarding",
              style: MacosTheme.of(context).typography.title2),
          const SizedBox(height: 10),
          _buildLabel("Dynamic Forward (SOCKS Proxy Port)"),
          MacosTextField(
            controller: TextEditingController(text: host.dynamicForward),
            placeholder: "e.g. 1080",
            onChanged: (v) {
              host.dynamicForward = v;
              store.markDirty(host.hostAlias);
            },
          ),
          const SizedBox(height: 10),
          _buildLabel("Local Forwards (List)"),
          Container(
            height: 150,
            decoration: BoxDecoration(
                border: Border.all(color: MacosTheme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(6)),
            child: ListView.separated(
              itemCount: host.localForwards.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == host.localForwards.length) {
                  return MacosListTile(
                    leading: const Icon(CupertinoIcons.add, size: 16),
                    title: const Text("Add Rule..."),
                    onClick: () => _showAddForwardDialog(context, host, store),
                  );
                }
                return MacosListTile(
                  title: Row(
                    children: [
                      Text(host.localForwards[index]),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          host.localForwards.removeAt(index);
                          store.markDirty(host.hostAlias); // 删除也是变更
                        },
                        child: const Icon(CupertinoIcons.trash,
                            size: 14, color: CupertinoColors.systemGrey),
                      ),
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  // --- Tab 4: Advanced ---
  Widget _buildAdvanced(BuildContext context, SSHStore store) {
    final host = store.currentHost!;
    final commonOptions = [
      "ForwardX11",
      "Compression",
      "StrictHostKeyChecking",
      "ServerAliveInterval",
      "ExitOnForwardFailure"
    ];

    return ListView(
      children: commonOptions.map((key) {
        final val = host.advancedOptions[key.toLowerCase()] ?? "";
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              SizedBox(
                  width: 160,
                  child: Text(key,
                      style: const TextStyle(fontWeight: FontWeight.w500))),
              Expanded(
                child: MacosTextField(
                  controller: TextEditingController(text: val),
                  placeholder: "Optional",
                  onChanged: (newValue) {
                    if (newValue.isEmpty) {
                      host.advancedOptions.remove(key.toLowerCase());
                    } else {
                      host.advancedOptions[key.toLowerCase()] = newValue;
                    }
                    store.markDirty(host.hostAlias);
                  },
                ),
              )
            ],
          ),
        );
      }).toList(),
    );
  }

  // --- Dialogs ---

  void _showKeyPicker(
      BuildContext context, SSHStore store, SSHHost host) async {
    final keys = await store.listKeys();
    if (!mounted) return;

    await showMacosSheet(
      context: context,
      builder: (context) => MacosSheet(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text("Select Identity File",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: keys.length,
                  itemBuilder: (context, index) {
                    final k = keys[index];
                    return MacosListTile(
                      leading: const Icon(CupertinoIcons.doc_text),
                      title: Text(p.basename(k)),
                      subtitle: Text(k, style: const TextStyle(fontSize: 10)),
                      onClick: () {
                        host.identityFile = k;
                        store.markDirty(host.hostAlias);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              PushButton(
                  controlSize: ControlSize.regular,
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.of(context).pop())
            ],
          ),
        ),
      ),
    );
  }

  void _showKeyGenerator(BuildContext context, SSHStore store) {
    final filenameCtrl = TextEditingController(text: "id_ed25519_new");
    String type = "ed25519";

    showMacosSheet(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setState) {
        return MacosSheet(
          child: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Generate New Key Pair",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  MacosTextField(
                    controller: filenameCtrl,
                    prefix: const Padding(
                        padding: EdgeInsets.all(8), child: Text("Filename:")),
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
                      PushButton(
                        controlSize: ControlSize.regular,
                        secondary: true,
                        child: const Text("Cancel"),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      PushButton(
                        controlSize: ControlSize.regular,
                        child: const Text("Generate"),
                        onPressed: () async {
                          final res = await store.generateKey(
                              filename: filenameCtrl.text, type: type);
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                          // Show alert result (simplified)
                          debugPrint(res);
                        },
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  void _showAddForwardDialog(
      BuildContext context, SSHHost host, SSHStore store) {
    final localCtrl = TextEditingController(text: "8080");
    final remoteCtrl = TextEditingController(text: "localhost:80");

    showMacosSheet(
        context: context,
        builder: (context) => MacosSheet(
              child: Center(
                child: SizedBox(
                  width: 350,
                  height: 250,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Add Local Forward"),
                      const SizedBox(height: 20),
                      MacosTextField(
                        controller: localCtrl,
                        prefix: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text("Local Port:")),
                      ),
                      const SizedBox(height: 10),
                      MacosTextField(
                        controller: remoteCtrl,
                        prefix: const Padding(
                            padding: EdgeInsets.all(8), child: Text("Remote:")),
                        placeholder: "localhost:80",
                      ),
                      const SizedBox(height: 20),
                      PushButton(
                        controlSize: ControlSize.regular,
                        child: const Text("Add"),
                        onPressed: () {
                          host.localForwards
                              .add("${localCtrl.text}:${remoteCtrl.text}");
                          store.saveConfig();
                          Navigator.of(context).pop();
                        },
                      )
                    ],
                  ),
                ),
              ),
            ));
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(text,
          style:
              const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
    );
  }
}

class LibraryHostRow extends StatefulWidget {
  final SSHHost host;
  final bool selected;
  final VoidCallback onTap;
  final GestureTapUpCallback onSecondaryTapUp;
  const LibraryHostRow(
      {super.key,
      required this.host,
      required this.selected,
      required this.onTap,
      required this.onSecondaryTapUp});
  @override
  State<LibraryHostRow> createState() => _LibraryHostRowState();
}

class _LibraryHostRowState extends State<LibraryHostRow> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final dark = MacosTheme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: widget.selected
                  ? (dark ? const Color(0xFF35465F) : const Color(0xFFDCE8F8))
                  : hovered
                      ? CupertinoColors.systemGrey.withValues(alpha: 0.1)
                      : Colors.transparent),
          child: Row(children: [
            Icon(CupertinoIcons.desktopcomputer,
                size: 16,
                color: store.isConnected(widget.host.hostAlias)
                    ? const Color(0xFF5DBB8A)
                    : CupertinoColors.systemGrey),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.host.hostAlias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w400)),
                  const SizedBox(height: 3),
                  Text(widget.host.hostName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10, color: CupertinoColors.systemGrey)),
                ])),
            if (store.isDirty(widget.host.hostAlias))
              const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(CupertinoIcons.circle_fill,
                      size: 5, color: CupertinoColors.systemOrange)),
            if (hovered || store.isFavorite(widget.host))
              MacosIconButton(
                  icon: Icon(
                      store.isFavorite(widget.host)
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      size: 13,
                      color: store.isFavorite(widget.host)
                          ? CupertinoColors.systemYellow
                          : CupertinoColors.systemGrey),
                  onPressed: () => store.toggleFavorite(widget.host)),
          ]),
        ),
      ),
    );
  }
}

Future<void> launchHostTerminal(
    BuildContext context, SSHStore store, SSHHost host) async {
  try {
    await store.openTerminal(host);
  } catch (e) {
    if (!context.mounted) return;
    showMacosAlertDialog(
        context: context,
        builder: (dialogContext) => MacosAlertDialog(
            appIcon: const Icon(CupertinoIcons.exclamationmark_triangle),
            title: const Text('Could not open Terminal'),
            message: Text('$e'),
            primaryButton: PushButton(
                controlSize: ControlSize.regular,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'))));
  }
}

Future<void> showGroupEditor(
    BuildContext context, SSHStore store, SSHHost host) async {
  final controller = TextEditingController(
      text: store.groupFor(host) == 'Ungrouped' ? '' : store.groupFor(host));
  final group = await showMacosSheet<String>(
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
                        Text('Organize host',
                            style: MacosTheme.of(context).typography.title2),
                        const SizedBox(height: 8),
                        const Text(
                            'Choose an existing group or enter a new name.',
                            style: TextStyle(
                                fontSize: 12,
                                color: CupertinoColors.systemGrey)),
                        const SizedBox(height: 16),
                        MacosTextField(
                            controller: controller,
                            autofocus: true,
                            placeholder: 'Group name (empty to ungroup)',
                            onSubmitted: (value) =>
                                Navigator.pop(dialogContext, value)),
                        const SizedBox(height: 12),
                        Expanded(
                            child: SingleChildScrollView(
                                child:
                                    Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final name
                              in (store.hostGroups.values.toSet().toList()
                                ..sort()))
                            PushButton(
                                controlSize: ControlSize.small,
                                secondary: true,
                                onPressed: () => controller.text = name,
                                child: Text(name)),
                        ]))),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              PushButton(
                                  controlSize: ControlSize.regular,
                                  secondary: true,
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Cancel')),
                              const SizedBox(width: 8),
                              PushButton(
                                  controlSize: ControlSize.regular,
                                  onPressed: () => Navigator.pop(
                                      dialogContext, controller.text),
                                  child: const Text('Save group')),
                            ]),
                      ])))));
  // Sheet removal is animated; keep the field controller alive until it finishes.
  await Future<void>.delayed(const Duration(milliseconds: 350));
  controller.dispose();
  if (group != null) await store.setGroup(host, group);
}

Future<void> showQuickConnect(BuildContext context) async {
  final store = context.read<SSHStore>();
  final host = await showMacosSheet<SSHHost>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
          value: store, child: const QuickConnectSheet()));
  if (host == null || !context.mounted) return;
  store.selectHost(host);
  await launchHostTerminal(context, store, host);
}

class QuickConnectSheet extends StatefulWidget {
  const QuickConnectSheet({super.key});
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
    final matches = store.hosts
        .where((host) =>
            '${host.hostAlias} ${host.hostName} ${host.user} ${store.groupFor(host)}'
                .toLowerCase()
                .contains(query.toLowerCase()))
        .toList()
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
        child: SizedBox(
            width: 520,
            height: 430,
            child: Focus(
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent)
                    return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.pop(context);
                    return KeyEventResult.handled;
                  }
                  if (matches.isNotEmpty &&
                      (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                          event.logicalKey == LogicalKeyboardKey.arrowUp)) {
                    setState(() => selected = (selected +
                            (event.logicalKey == LogicalKeyboardKey.arrowDown
                                ? 1
                                : -1)) %
                        matches.length);
                    if (controller.hasClients)
                      controller.jumpTo((selected * 56.0)
                          .clamp(0.0, controller.position.maxScrollExtent));
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('Quick connect',
                                style:
                                    MacosTheme.of(context).typography.title2),
                            const Spacer(),
                            MacosIconButton(
                                icon:
                                    const Icon(CupertinoIcons.xmark, size: 14),
                                onPressed: () => Navigator.pop(context))
                          ]),
                          const SizedBox(height: 16),
                          MacosTextField(
                              autofocus: true,
                              placeholder: 'Search hosts, addresses or groups…',
                              onChanged: (value) => setState(() {
                                    query = value;
                                    selected = 0;
                                  }),
                              onSubmitted: (_) => choose()),
                          const SizedBox(height: 12),
                          Expanded(
                              child: matches.isEmpty
                                  ? const Center(
                                      child: Text('No matching hosts'))
                                  : ListView.builder(
                                      controller: controller,
                                      itemExtent: 56,
                                      itemCount: matches.length,
                                      itemBuilder: (context, index) {
                                        final host = matches[index];
                                        return GestureDetector(
                                            onTap: () =>
                                                Navigator.pop(context, host),
                                            child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12),
                                                decoration: BoxDecoration(
                                                    color: selected == index
                                                        ? CupertinoColors
                                                            .activeBlue
                                                            .withValues(
                                                                alpha: 0.15)
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            7)),
                                                child: Row(children: [
                                                  Icon(
                                                      store.isFavorite(host)
                                                          ? CupertinoIcons
                                                              .star_fill
                                                          : CupertinoIcons
                                                              .desktopcomputer,
                                                      size: 16,
                                                      color:
                                                          store.isFavorite(host)
                                                              ? CupertinoColors
                                                                  .systemYellow
                                                              : CupertinoColors
                                                                  .systemGrey),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                      child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                        Text(host.hostAlias,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                    fontSize:
                                                                        13)),
                                                        Text(
                                                            '${host.hostName} · ${store.groupFor(host)}',
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: const TextStyle(
                                                                fontSize: 11,
                                                                color: CupertinoColors
                                                                    .systemGrey)),
                                                      ])),
                                                  if (index == selected)
                                                    const Icon(
                                                        CupertinoIcons
                                                            .return_icon,
                                                        size: 14,
                                                        color: CupertinoColors
                                                            .systemGrey),
                                                ])));
                                      })),
                          const SizedBox(height: 12),
                          const Text(
                              '↑ ↓ Select     ↵ Open Terminal     esc Close',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: CupertinoColors.systemGrey)),
                        ])))));
  }
}
