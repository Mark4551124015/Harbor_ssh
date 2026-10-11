part of 'main.dart';

class SSHActivity {
  final int pid;
  final String elapsed;
  final String source;
  final List<String> endpoints;
  final List<String> listeners;
  const SSHActivity({
    required this.pid,
    required this.elapsed,
    required this.source,
    required this.endpoints,
    required this.listeners,
  });
  bool get connected => endpoints.isNotEmpty;
  String get target => endpoints.isEmpty ? 'SSH process' : endpoints.first;
  String get status => connected
      ? 'TCP connected'
      : listeners.isNotEmpty
      ? 'Listening'
      : 'No TCP observed';
}

/// Observes processes only. Never attaches to sessions or modifies SSH config.
class SSHActivityMonitor extends ChangeNotifier {
  List<SSHActivity> entries = [];
  String? error;
  bool refreshing = false;
  bool _disposed = false;
  Timer? _timer;
  void start() {
    refresh();
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) => refresh());
  }

  static List<SSHActivity> parse(String processes, String sockets) {
    final rows = <int, ({int parent, String elapsed, String command})>{};
    for (final line in const LineSplitter().convert(processes)) {
      final match = RegExp(
        r'^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.+)$',
      ).firstMatch(line);
      if (match == null) continue;
      rows[int.parse(match[1]!)] = (
        parent: int.parse(match[2]!),
        elapsed: match[3]!,
        command: match[4]!.trim(),
      );
    }
    final remote = <int, Set<String>>{};
    final listening = <int, Set<String>>{};
    int? pid;
    String? address;
    for (final line in const LineSplitter().convert(sockets)) {
      if (line.startsWith('p')) {
        pid = int.tryParse(line.substring(1));
        address = null;
      }
      if (line.startsWith('f')) address = null;
      if (line.startsWith('n')) address = line.substring(1);
      if (pid == null || address == null) continue;
      if (line == 'TST=ESTABLISHED' && address.contains('->')) {
        (remote[pid] ??= {}).add(address.split('->').last);
      } else if (line == 'TST=LISTEN') {
        (listening[pid] ??= {}).add(address);
      }
    }
    final result = <SSHActivity>[];
    for (final row in rows.entries) {
      // Exact executable name excludes ssh-agent, sshd and grep-like matches.
      if (p.basename(row.value.command) != 'ssh') continue;
      var ancestor = row.value.parent;
      var source = 'External';
      final seen = <int>{row.key};
      for (var depth = 0; depth < 16 && seen.add(ancestor); depth++) {
        final parent = rows[ancestor];
        if (parent == null) break;
        final name = p.basename(parent.command).toLowerCase();
        if (name.contains('harbor')) {
          source = 'Harbor';
          break;
        }
        if (name.contains('iterm')) {
          source = 'iTerm';
          break;
        }
        if (name == 'terminal') {
          source = 'Terminal';
          break;
        }
        ancestor = parent.parent;
      }
      result.add(
        SSHActivity(
          pid: row.key,
          elapsed: row.value.elapsed,
          source: source,
          endpoints: (remote[row.key] ?? {}).toList()..sort(),
          listeners: (listening[row.key] ?? {}).toList()..sort(),
        ),
      );
    }
    result.sort((a, b) => a.pid.compareTo(b.pid));
    return result;
  }

  Future<void> refresh() async {
    if (refreshing || _disposed) return;
    refreshing = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _run('/bin/ps', ['-axo', 'pid=,ppid=,etime=,comm=']),
        _run('/usr/sbin/lsof', [
          '-nP',
          '-a',
          '-c',
          '/^ssh\$/',
          '-iTCP',
          '-FpcfnT',
        ]),
      ]);
      if (_disposed) return;
      if (results[0].exitCode != 0 ||
          (results[1].exitCode != 0 &&
              results[1].stderr.toString().trim().isNotEmpty)) {
        throw const ProcessException(
          'SSH monitor',
          [],
          'Process information unavailable',
        );
      }
      entries = parse(
        results[0].stdout.toString(),
        results[1].stdout.toString(),
      );
      error = null;
    } catch (_) {
      if (!_disposed) {
        error = 'Unable to read local SSH activity. Try refreshing.';
      }
    } finally {
      if (!_disposed) {
        refreshing = false;
        notifyListeners();
      }
    }
  }

  static Future<ProcessResult> _run(
    String command,
    List<String> arguments,
  ) async {
    final process = await Process.start(command, arguments);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 4));
      return ProcessResult(process.pid, code, await output, await errors);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await Future.wait([output, errors]);
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

class SSHPortProbe {
  static Future<List<int>> measure(
    String endpoint, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final split = endpoint.lastIndexOf(':');
    if (split <= 0) throw const FormatException('Invalid endpoint');
    var host = endpoint.substring(0, split);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    final port = int.parse(endpoint.substring(split + 1));
    if (port < 1 || port > 65535) throw const FormatException('Invalid port');
    final samples = <int>[];
    for (var i = 0; i < 3; i++) {
      final watch = Stopwatch()..start();
      final socket = await Socket.connect(host, port, timeout: timeout);
      watch.stop();
      socket.destroy();
      samples.add(watch.elapsedMilliseconds);
    }
    return samples;
  }
}

class HarborActivityList extends StatelessWidget {
  final SSHActivityMonitor monitor;
  final bool compact;
  final String filter;
  final VoidCallback? onViewAll;
  const HarborActivityList({
    super.key,
    required this.monitor,
    this.compact = false,
    this.filter = 'All',
    this.onViewAll,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) {
      final colors = HarborColors.of(context);
      final filtered = monitor.entries.where(
        (entry) => switch (filter) {
          'Connected' => entry.connected,
          'With listeners' => entry.listeners.isNotEmpty,
          _ => true,
        },
      );
      final entries = (compact ? filtered.take(4) : filtered).toList();
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Local SSH activity',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                  ),
                  HarborButton(
                    label: 'View all',
                    secondary: true,
                    onPressed: onViewAll,
                  ),
                ],
              ),
            ),
          if (monitor.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                monitor.error!,
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            )
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                monitor.refreshing
                    ? 'Checking local SSH processes…'
                    : (filter == 'All'
                          ? 'No local SSH processes running.'
                          : 'No matching SSH processes.'),
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            )
          else
            for (final entry in entries)
              SizedBox(
                height: 56,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showHarborSheet<void>(
                    context: context,
                    barrierDismissible: true,
                    builder: (_) =>
                        _SSHActivityDetail(entry: entry, monitor: monitor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.circle_fill,
                        size: 6,
                        color: entry.connected
                            ? HarborColors.teal
                            : colors.muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.target,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${entry.status}${entry.listeners.isEmpty ? '' : ' · ${entry.listeners.length} listeners'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 78,
                        child: Text(
                          entry.source,
                          style: TextStyle(color: colors.muted, fontSize: 11),
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: Text(
                          entry.elapsed,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: colors.muted,
                            fontSize: 11,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 12,
                        color: colors.muted,
                      ),
                    ],
                  ),
                ),
              ),
        ],
      );
      return compact ? SizedBox(height: 272, child: body) : body;
    },
  );
}

class HarborActivityPage extends StatefulWidget {
  final SSHActivityMonitor monitor;
  const HarborActivityPage({super.key, required this.monitor});
  @override
  State<HarborActivityPage> createState() => _HarborActivityPageState();
}

class _HarborActivityPageState extends State<HarborActivityPage> {
  String filter = 'All';
  SSHActivityMonitor get monitor => widget.monitor;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        ListenableBuilder(
          listenable: monitor,
          builder: (context, _) => HarborPageHeader(
            title: 'SSH activity',
            subtitle:
                '${monitor.entries.length} local processes · updates every 5 seconds',
            secondaryAction: const SizedBox.shrink(),
            primaryAction: HarborButton(
              label: 'Refresh',
              icon: CupertinoIcons.refresh,
              busy: monitor.refreshing,
              onPressed: monitor.refresh,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 340,
            child: HarborSegmentedControl<String>(
              groupValue: filter,
              children: const {
                'All': Text('All'),
                'Connected': Text('Connected'),
                'With listeners': Text('With listeners'),
              },
              onValueChanged: (value) {
                if (value != null) setState(() => filter = value);
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: HarborActivityList(monitor: monitor, filter: filter),
          ),
        ),
      ],
    ),
  );
}

class _SSHActivityDetail extends StatefulWidget {
  final SSHActivity entry;
  final SSHActivityMonitor monitor;
  const _SSHActivityDetail({required this.entry, required this.monitor});
  @override
  State<_SSHActivityDetail> createState() => _SSHActivityDetailState();
}

class _SSHActivityDetailState extends State<_SSHActivityDetail> {
  SSHActivity? get currentEntry {
    for (final entry in widget.monitor.entries) {
      if (entry.pid == widget.entry.pid) return entry;
    }
    return null;
  }

  bool testing = false;
  String? result;
  Future<void> testPort() async {
    setState(() {
      testing = true;
      result = null;
    });
    try {
      final samples = await SSHPortProbe.measure(
        (currentEntry ?? widget.entry).endpoints.first,
      );
      if (mounted) {
        setState(
          () => result =
              '${(samples.reduce((a, b) => a + b) / samples.length).round()} ms average · ${samples.join(' / ')} ms',
        );
      }
    } catch (_) {
      if (mounted) setState(() => result = 'Port unreachable or timed out.');
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.monitor,
    builder: (context, _) => _build(context),
  );
  Widget _build(BuildContext context) {
    final colors = HarborColors.of(context);
    final entry = currentEntry ?? widget.entry;
    final ended = currentEntry == null;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height - 64,
        maxWidth: MediaQuery.sizeOf(context).width - 48,
      ),
      child: SingleChildScrollView(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'SSH process',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  HarborButton(
                    label: 'Done',
                    secondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SelectableText(
                'PID ${entry.pid} · ${entry.source}\n${ended ? 'Process exited · last observed ${entry.elapsed}' : 'Running ${entry.elapsed} · ${entry.status}'}\n\nRemote endpoints\n${entry.endpoints.isEmpty ? 'None observed' : entry.endpoints.join('\n')}\n\nListening ports\n${entry.listeners.isEmpty ? 'None observed' : entry.listeners.join('\n')}',
                style: TextStyle(color: colors.text, fontSize: 12, height: 1.7),
              ),
              const SizedBox(height: 24),
              Text(
                'Network diagnostics',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Opens 3 TCP connections to the first observed remote endpoint. Measures port connection time, not SSH session latency or bandwidth.',
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              HarborButton(
                label: 'Test port latency',
                busy: testing,
                onPressed: !ended && entry.connected ? testPort : null,
              ),
              SizedBox(
                height: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    result ?? '',
                    style: TextStyle(color: colors.text, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
