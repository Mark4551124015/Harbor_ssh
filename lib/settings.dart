part of 'main.dart';

const harborAccentPalette = <String, ({Color light, Color dark})>{
  'Copper': (light: Color(0xFF9A5427), dark: Color(0xFFE5A16B)),
  'Teal': (light: Color(0xFF28796D), dark: Color(0xFF69BDB0)),
  'Blue': (light: Color(0xFF386FA3), dark: Color(0xFF7FAED5)),
  'Violet': (light: Color(0xFF7354A6), dark: Color(0xFFAA9BDC)),
  'Rose': (light: Color(0xFFA34F70), dark: Color(0xFFD68EAA)),
};

class HarborPreferences {
  final ThemeMode theme;
  final String accent;
  final bool reduceMotion;
  final bool showAddresses;
  final String terminal;
  final String startPage;
  final int connectTimeout;
  final int keepAlive;
  final bool recordRecent;
  final bool autoCheckUpdates;
  const HarborPreferences({
    this.theme = ThemeMode.system,
    this.accent = 'Copper',
    this.reduceMotion = false,
    this.showAddresses = true,
    this.terminal = 'system',
    this.startPage = 'workbench',
    this.connectTimeout = 15,
    this.keepAlive = 30,
    this.recordRecent = true,
    this.autoCheckUpdates = true,
  });
  factory HarborPreferences.fromJson(dynamic value) {
    final data = value is Map ? value : const {};
    bool flag(String name, bool fallback) =>
        data[name] is bool ? data[name] as bool : fallback;
    return HarborPreferences(
      theme:
          ThemeMode.values
              .where((mode) => mode.name == data['theme'])
              .firstOrNull ??
          ThemeMode.system,
      accent: harborAccentPalette.containsKey(data['accent'])
          ? data['accent'] as String
          : 'Copper',
      reduceMotion: flag('reduceMotion', false),
      showAddresses: flag('showAddresses', true),
      terminal: ['system', 'iterm', 'terminal'].contains(data['terminal'])
          ? data['terminal'] as String
          : 'system',
      startPage: ['workbench', 'mappings', 'keys'].contains(data['startPage'])
          ? data['startPage'] as String
          : 'workbench',
      connectTimeout: [10, 15, 30, 60].contains(data['connectTimeout'])
          ? (data['connectTimeout'] as num).toInt()
          : 15,
      keepAlive: [0, 30, 60].contains(data['keepAlive'])
          ? (data['keepAlive'] as num).toInt()
          : 30,
      recordRecent: flag('recordRecent', true),
      autoCheckUpdates: flag('autoCheckUpdates', true),
    );
  }
  HarborPreferences copyWith({
    ThemeMode? theme,
    String? accent,
    bool? reduceMotion,
    bool? showAddresses,
    String? terminal,
    String? startPage,
    int? connectTimeout,
    int? keepAlive,
    bool? recordRecent,
    bool? autoCheckUpdates,
  }) => HarborPreferences(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    showAddresses: showAddresses ?? this.showAddresses,
    terminal: terminal ?? this.terminal,
    startPage: startPage ?? this.startPage,
    connectTimeout: connectTimeout ?? this.connectTimeout,
    keepAlive: keepAlive ?? this.keepAlive,
    recordRecent: recordRecent ?? this.recordRecent,
    autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
  );
  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'accent': accent,
    'reduceMotion': reduceMotion,
    'showAddresses': showAddresses,
    'terminal': terminal,
    'startPage': startPage,
    'connectTimeout': connectTimeout,
    'keepAlive': keepAlive,
    'recordRecent': recordRecent,
    'autoCheckUpdates': autoCheckUpdates,
  };
}

class HarborSettingsPage extends StatefulWidget {
  final FocusNode? searchFocusNode;
  final TextEditingController? searchController;
  const HarborSettingsPage({
    super.key,
    this.searchFocusNode,
    this.searchController,
  });
  @override
  State<HarborSettingsPage> createState() => _HarborSettingsPageState();
}

class _HarborSettingsPageState extends State<HarborSettingsPage> {
  String query = '';
  String? category;
  String? feedback;
  bool actionFailed = false;
  late final search = widget.searchController ?? TextEditingController();
  @override
  void initState() {
    super.initState();
    query = search.text;
  }

  @override
  void dispose() {
    if (widget.searchController == null) search.dispose();
    super.dispose();
  }

  Future<void> perform(
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      if (mounted) {
        setState(() {
          feedback = success;
          actionFailed = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          feedback = error.toString();
          actionFailed = true;
        });
      }
    }
  }

  Widget toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      Semantics(
        label: label,
        child: MacosSwitch(value: value, onChanged: onChanged),
      );
  Widget options<T extends Object>(
    T value,
    Map<T, String> labels,
    ValueChanged<T> onChanged,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 280),
    child: HarborSegmentedControl<T>(
      groupValue: value,
      children: labels.map(
        (key, label) => MapEntry(
          key,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(label, style: const TextStyle(fontSize: 11)),
          ),
        ),
      ),
      onValueChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final store = context.watch<SSHStore>();
    final prefs = store.preferences;
    final colors = HarborColors.of(context);
    void update(HarborPreferences preferences) =>
        store.updatePreferences(preferences);
    final allSections = <_HarborSettingsSection>[
      _HarborSettingsSection(
        title: 'Appearance',
        icon: CupertinoIcons.paintbrush,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                const HarborAppIcon(size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Make Harbor yours',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Changes appear immediately.',
                        style: TextStyle(fontSize: 11, color: colors.muted),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          _HarborSettingRow(
            title: 'Theme',
            subtitle: 'Follow macOS or choose a fixed appearance.',
            control: options(prefs.theme, {
              ThemeMode.system: 'System',
              ThemeMode.light: 'Light',
              ThemeMode.dark: 'Dark',
            }, (value) => update(prefs.copyWith(theme: value))),
          ),
          _HarborSettingRow(
            title: 'Accent color',
            subtitle: prefs.accent,
            control: Wrap(
              spacing: 9,
              children: [
                for (final entry in harborAccentPalette.entries)
                  Tooltip(
                    message: entry.key,
                    child: Semantics(
                      label: '${entry.key} accent',
                      button: true,
                      selected: prefs.accent == entry.key,
                      child: CupertinoButton(
                        key: ValueKey('accent-${entry.key}'),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(28, 28),
                        onPressed: () =>
                            update(prefs.copyWith(accent: entry.key)),
                        child: Container(
                          width: 27,
                          height: 27,
                          decoration: BoxDecoration(
                            color: colors.dark
                                ? entry.value.dark
                                : entry.value.light,
                            shape: BoxShape.circle,
                          ),
                          child: prefs.accent == entry.key
                              ? Icon(
                                  CupertinoIcons.check_mark,
                                  color: colors.dark
                                      ? colors.background
                                      : Colors.white,
                                  size: 14,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _HarborSettingRow(
            title: 'Reduce motion',
            subtitle:
                'Keep transitions still. macOS accessibility settings also apply.',
            control: toggle(
              'Reduce motion',
              prefs.reduceMotion,
              (value) => update(prefs.copyWith(reduceMotion: value)),
            ),
          ),
          _HarborSettingRow(
            title: 'Show server addresses',
            subtitle: 'Display hostnames below connections in the sidebar.',
            control: toggle(
              'Show server addresses',
              prefs.showAddresses,
              (value) => update(prefs.copyWith(showAddresses: value)),
            ),
          ),
        ],
      ),
      _HarborSettingsSection(
        title: 'Connections',
        icon: CupertinoIcons.arrow_right_arrow_left,
        children: [
          _HarborSettingRow(
            title: 'Start page',
            subtitle: 'Where Harbor opens next time.',
            control: options(prefs.startPage, {
              'workbench': 'Workbench',
              'mappings': 'Mappings',
              'keys': 'Keys',
            }, (value) => update(prefs.copyWith(startPage: value))),
          ),
          _HarborSettingRow(
            title: 'Open connections in',
            subtitle: 'System uses the default app for .command files.',
            control: options(prefs.terminal, {
              'system': 'System',
              'iterm': 'iTerm2',
              'terminal': 'Terminal',
            }, (value) => update(prefs.copyWith(terminal: value))),
          ),
          _HarborSettingRow(
            title: 'Connection timeout',
            subtitle: 'For new tunnels; server-specific options take priority.',
            control: options(
              prefs.connectTimeout,
              {10: '10s', 15: '15s', 30: '30s', 60: '60s'},
              (value) => update(prefs.copyWith(connectTimeout: value)),
            ),
          ),
          _HarborSettingRow(
            title: 'Keep-alive interval',
            subtitle:
                'For new tunnels. Detects a lost SSH connection after three missed replies.',
            control: options(prefs.keepAlive, {
              0: 'Off',
              30: '30s',
              60: '60s',
            }, (value) => update(prefs.copyWith(keepAlive: value))),
          ),
        ],
      ),
      _HarborSettingsSection(
        title: 'Data & privacy',
        icon: CupertinoIcons.lock_shield,
        children: [
          _HarborSettingRow(
            title: 'Remember recent connections',
            subtitle: 'Record successfully opened connections on this Mac.',
            control: toggle(
              'Remember recent connections',
              prefs.recordRecent,
              (value) => update(prefs.copyWith(recordRecent: value)),
            ),
          ),
          _HarborSettingRow(
            title: 'Recent history',
            subtitle: '${store.recentHosts.length} recent connections.',
            control: HarborButton(
              label: 'Clear history',
              secondary: true,
              onPressed: store.recentHosts.isEmpty
                  ? null
                  : () => perform(
                      store.clearRecentHosts,
                      success: 'Recent history cleared.',
                    ),
            ),
          ),
          _HarborSettingRow(
            title: 'Harbor data',
            subtitle: 'Groups, preferences and independent mappings.',
            control: HarborButton(
              label: 'Show in Finder',
              secondary: true,
              onPressed: () => perform(() => store.revealDataFile()),
            ),
          ),
          _HarborSettingRow(
            title: 'SSH configuration',
            subtitle: 'Host settings in ~/.ssh/config.',
            control: HarborButton(
              label: 'Show config',
              secondary: true,
              onPressed: () =>
                  perform(() => store.revealDataFile(sshConfig: true)),
            ),
          ),
        ],
      ),
      _HarborSettingsSection(
        title: 'Keyboard shortcuts',
        icon: CupertinoIcons.keyboard,
        children: [
          for (final shortcut in const [
            ('Quick connect', '⌘K'),
            ('Search settings or connections', '⌘F / Ctrl+F'),
            ('New connection', '⌘N'),
            ('Save SSH configuration', '⌘S'),
            ('Settings', '⌘,'),
            ('Back / close dialog', 'Esc'),
            ('Rename selected connection', 'F2'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: _settingsHighlightedText(
                      context,
                      shortcut.$1,
                      style: TextStyle(fontSize: 12, color: colors.text),
                    ),
                  ),
                  Text(
                    shortcut.$2,
                    style: TextStyle(fontSize: 11, color: colors.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
      _HarborSettingsSection(
        title: 'About',
        icon: CupertinoIcons.info_circle,
        children: [
          Row(
            children: [
              const HarborAppIcon(size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Harbor SSH',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Version ${store.applicationVersion} (${store.applicationBuild})',
                      style: TextStyle(fontSize: 11, color: colors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _HarborSettingRow(
            title: 'Automatically check for updates',
            subtitle: 'Check GitHub Releases when Harbor starts.',
            control: toggle(
              'Automatically check for updates',
              prefs.autoCheckUpdates,
              (value) => update(prefs.copyWith(autoCheckUpdates: value)),
            ),
          ),
          Text(
            store.updateStatus,
            style: TextStyle(
              fontSize: 12,
              color: store.updateError
                  ? CupertinoColors.systemRed
                  : colors.muted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HarborButton(
                label: 'Check for updates',
                busy: store.updateBusy,
                secondary: true,
                onPressed: store.updateBusy ? null : store.checkForUpdates,
              ),
              if (store.availableUpdate != null)
                HarborButton(
                  label: 'Install and restart',
                  onPressed: store.updateBusy
                      ? null
                      : () async {
                          final confirmed = await showHarborDialog<bool>(
                            context: context,
                            builder: (dialogContext) => HarborAlert(
                              appIcon: const Icon(
                                CupertinoIcons.arrow_down_circle,
                              ),
                              title: Text(
                                'Install ${store.availableUpdate!.version}?',
                              ),
                              message: const Text(
                                'Harbor will download the update and restart. Active port mappings will close. Your saved settings and connections will be preserved.',
                              ),
                              secondaryButton: HarborButton(
                                label: 'Cancel',
                                secondary: true,
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                              ),
                              primaryButton: HarborButton(
                                label: 'Install and restart',
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                              ),
                            ),
                          );
                          if (confirmed == true) await store.installUpdate();
                        },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Your servers, keys and tunnels, together on your Mac.',
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HarborButton(
                label: 'Copy diagnostics',
                secondary: true,
                onPressed: () => perform(
                  () => Clipboard.setData(
                    ClipboardData(
                      text:
                          'Harbor SSH ${store.applicationVersion} (${store.applicationBuild})\n${Platform.operatingSystem} ${Platform.operatingSystemVersion}\nHosts: ${store.hosts.length}\nMappings: ${store.mappings.length}',
                    ),
                  ),
                  success: 'Diagnostics copied.',
                ),
              ),
              HarborButton(
                label: 'Reset preferences',
                secondary: true,
                onPressed: () async {
                  final reset = await showHarborDialog<bool>(
                    context: context,
                    builder: (dialogContext) => HarborAlert(
                      appIcon: const Icon(
                        CupertinoIcons.arrow_counterclockwise,
                      ),
                      title: const Text('Reset preferences?'),
                      message: const Text(
                        'Restore the default appearance and connection preferences. Your servers, keys, groups and mappings stay in place.',
                      ),
                      secondaryButton: HarborButton(
                        label: 'Cancel',
                        secondary: true,
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                      primaryButton: HarborButton(
                        label: 'Reset',
                        onPressed: () => Navigator.pop(dialogContext, true),
                      ),
                    ),
                  );
                  if (reset == true && mounted) {
                    await perform(
                      () => store.updatePreferences(const HarborPreferences()),
                      success: 'Preferences restored.',
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    ];
    final terms = _settingsTerms(query);
    final sections = <_HarborSettingsSection>[];
    for (final section in allSections) {
      if (terms.isEmpty && category != null && category != section.title) {
        continue;
      }
      final sectionMatches =
          terms.isNotEmpty &&
          _settingsContains(
            '${section.title} ${_settingsAliases[section.title] ?? ''}',
            terms,
          );
      final children = terms.isEmpty || sectionMatches
          ? section.children
          : section.children
                .where(
                  (child) =>
                      _settingsContains(_settingsWidgetText(child), terms),
                )
                .toList();
      if (children.isNotEmpty) {
        sections.add(
          _HarborSettingsSection(
            title: section.title,
            icon: section.icon,
            children: children,
          ),
        );
      }
    }
    return _HarborSettingsSearchScope(
      query: query,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A workspace that feels like yours.',
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: HarborTextField(
                    controller: search,
                    focusNode: widget.searchFocusNode,
                    placeholder: 'Search settings…',
                    prefix: const Icon(CupertinoIcons.search),
                    onChanged: (value) => setState(() {
                      query = value;
                      if (value.trim().isNotEmpty) category = null;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in const [
                  'All',
                  'Appearance',
                  'Connections',
                  'Data & privacy',
                  'Keyboard shortcuts',
                  'About',
                ])
                  Semantics(
                    button: true,
                    selected: (category ?? 'All') == name,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      minimumSize: Size.zero,
                      onPressed: () => setState(() {
                        category = name == 'All' ? null : name;
                        query = '';
                        search.clear();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: (category ?? 'All') == name
                                  ? colors.accent
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 11,
                            color: (category ?? 'All') == name
                                ? colors.accent
                                : colors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (feedback != null || store.metadataError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  store.metadataError ?? feedback!,
                  style: TextStyle(
                    fontSize: 12,
                    color: actionFailed || store.metadataError != null
                        ? CupertinoColors.destructiveRed
                        : HarborColors.teal,
                  ),
                ),
              ),
            Expanded(
              child: HarborPageTransition(
                child: KeyedSubtree(
                  key: ValueKey(
                    '${category ?? 'All'}:${sections.map((section) => section.title).join(',')}',
                  ),
                  child: sections.isEmpty
                      ? Center(
                          child: Text(
                            'No matching settings',
                            style: TextStyle(fontSize: 13, color: colors.muted),
                          ),
                        )
                      : ListView.separated(
                          key: ValueKey(
                            '${category ?? 'All'}:${query.trim().toLowerCase()}',
                          ),
                          itemCount: sections.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 16),
                          itemBuilder: (_, index) => sections[index],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Preferences are saved automatically on this Mac.',
              style: TextStyle(fontSize: 10, color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _HarborSettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _HarborSettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.accent),
              const SizedBox(width: 8),
              _settingsHighlightedText(
                context,
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _HarborSettingRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget control;
  const _HarborSettingRow({
    required this.title,
    required this.subtitle,
    required this.control,
  });
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    final terms = _settingsTerms(_HarborSettingsSearchScope.of(context));
    final highlighted =
        terms.isNotEmpty && _settingsContains(_settingsWidgetText(this), terms);
    return DecoratedBox(
      key: highlighted ? ValueKey('setting-match-$title') : null,
      decoration: BoxDecoration(
        color: highlighted
            ? colors.accent.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _settingsHighlightedText(
                    context,
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _settingsHighlightedText(
                    context,
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            control,
          ],
        ),
      ),
    );
  }
}

const _settingsAliases = <String, String>{
  'Appearance': '外观',
  'Connections': '连接',
  'Data & privacy': '数据 隐私',
  'Keyboard shortcuts': '快捷键 键盘',
  'About': '关于',
  'Theme': '主题 外观 system light dark 浅色 深色 系统',
  'Accent color': '强调色 颜色 copper teal blue violet rose',
  'Reduce motion': '减少 动画 animation motion accessibility 辅助功能',
  'Show server addresses': '显示 服务器 地址 hostname sidebar 边栏',
  'Start page': '启动 页面 workbench mappings keys 工作台 映射 密钥',
  'Open connections in': 'terminal iterm iterm2 default 终端 默认',
  'Connection timeout': '连接 超时 timeout 10s 15s 30s 60s',
  'Keep-alive interval': 'keepalive keep alive 保活 心跳 间隔 off 30s 60s',
  'Remember recent connections': '记录 最近 历史 history recent',
  'Recent history': '最近 历史 清除 clear history',
  'Harbor data': '数据 分组 配置 映射 finder',
  'SSH configuration': 'ssh config 配置 文件 finder',
};

List<String> _settingsTerms(String query) => query
    .trim()
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((term) => term.isNotEmpty)
    .toList();

bool _settingsContains(String text, List<String> terms) {
  final normalized = text.toLowerCase();
  return terms.every(normalized.contains);
}

String _settingsWidgetText(Widget widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  if (widget is _HarborSettingRow) {
    return '${widget.title} ${widget.subtitle} ${_settingsAliases[widget.title] ?? ''} ${_settingsWidgetText(widget.control)}';
  }
  if (widget is HarborButton) return widget.label;
  if (widget is HarborSegmentedControl) {
    return widget.children.values.map(_settingsWidgetText).join(' ');
  }
  if (widget is Flex) return widget.children.map(_settingsWidgetText).join(' ');
  if (widget is Wrap) return widget.children.map(_settingsWidgetText).join(' ');
  Widget? child;
  if (widget is Padding) child = widget.child;
  if (widget is Expanded) child = widget.child;
  if (widget is Container) child = widget.child;
  if (widget is SizedBox) child = widget.child;
  if (widget is ConstrainedBox) child = widget.child;
  if (widget is Tooltip) {
    return '${widget.message} ${widget.child == null ? '' : _settingsWidgetText(widget.child!)}';
  }
  return child == null ? '' : _settingsWidgetText(child);
}

class _HarborSettingsSearchScope extends InheritedWidget {
  final String query;
  const _HarborSettingsSearchScope({required this.query, required super.child});
  static String of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_HarborSettingsSearchScope>()
          ?.query ??
      '';
  @override
  bool updateShouldNotify(_HarborSettingsSearchScope oldWidget) =>
      query != oldWidget.query;
}

Widget _settingsHighlightedText(
  BuildContext context,
  String text, {
  required TextStyle style,
}) {
  final terms = _settingsTerms(_HarborSettingsSearchScope.of(context));
  if (terms.isEmpty) return Text(text, style: style);
  final pattern = RegExp(
    terms.map(RegExp.escape).join('|'),
    caseSensitive: false,
  );
  final spans = <TextSpan>[];
  var offset = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > offset) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
    }
    spans.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: TextStyle(
          backgroundColor: HarborColors.of(
            context,
          ).accent.withValues(alpha: 0.25),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    offset = match.end;
  }
  if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
  return Text.rich(TextSpan(children: spans), style: style);
}
