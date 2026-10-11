// Run with flutter run --profile -d macos -t tool/quick_connect_benchmark.dart.
// Uses fictional hosts and never reads or writes the user's SSH configuration.
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:macos_ssh_tool/main.dart';

class BenchmarkStore extends SSHStore {
  BenchmarkStore() : super(load: false);
  @override
  Future<void> saveMetadata() async {}
}

void main() => runApp(const BenchmarkApp());

class BenchmarkApp extends StatefulWidget {
  const BenchmarkApp({super.key});
  @override
  State<BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<BenchmarkApp> {
  final window = GlobalKey();
  final frames = <FrameTiming>[];
  final store = BenchmarkStore();
  final periods = <({int start, int end})>[];
  @override
  void initState() {
    super.initState();
    store.hosts = List.generate(
      100,
      (index) => SSHHost(
        hostAlias: 'benchmark-$index',
        hostName: 'host-$index.example.test',
        user: 'demo',
      ),
    );
    store.search('');
    WidgetsBinding.instance.addTimingsCallback(frames.addAll);
    WidgetsBinding.instance.addPostFrameCallback((_) => measure());
  }

  Future<void> measure() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    for (var i = 0; i < 2; i++) {
      final start = Timeline.now;
      unawaited(showQuickConnect(window.currentContext!));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      periods.add((start: start, end: Timeline.now));
      Navigator.of(window.currentContext!, rootNavigator: true).pop();
      await Future<void>.delayed(const Duration(milliseconds: 1300));
    }
    final output = periods
        .map(
          (period) => frames
              .where((frame) {
                final timestamp = frame.timestampInMicroseconds(
                  FramePhase.vsyncStart,
                );
                return timestamp >= period.start && timestamp <= period.end;
              })
              .map(
                (frame) => {
                  'build_ms': frame.buildDuration.inMicroseconds / 1000,
                  'raster_ms': frame.rasterDuration.inMicroseconds / 1000,
                  'total_ms': frame.totalSpan.inMicroseconds / 1000,
                },
              )
              .toList(),
        )
        .toList();
    final path =
        Platform.environment['HARBOR_BENCHMARK_OUTPUT'] ??
        '/private/tmp/harbor-quick-connect-profile.json';
    await File(
      path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(output));
    exit(0);
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<SSHStore>.value(
    value: store,
    child: HarborApplication(home: MainWindow(key: window)),
  );
}
