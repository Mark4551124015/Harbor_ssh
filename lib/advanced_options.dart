part of 'main.dart';

class HarborSSHOption {
  final String name;
  final String description;
  final String example;
  const HarborSSHOption(this.name, this.description, this.example);
}

// Descriptions follow OpenSSH ssh_config(5); values are never enabled implicitly.
const harborSSHOptions = <HarborSSHOption>[
  HarborSSHOption(
    'ServerAliveInterval',
    'Seconds between encrypted keepalive requests.',
    '30',
  ),
  HarborSSHOption(
    'ServerAliveCountMax',
    'Unanswered keepalives before disconnecting.',
    '3',
  ),
  HarborSSHOption(
    'ConnectTimeout',
    'Connection and initial handshake timeout, in seconds.',
    '15',
  ),
  HarborSSHOption('ConnectionAttempts', 'Number of connection attempts.', '1'),
  HarborSSHOption(
    'TCPKeepAlive',
    'Use operating system TCP keepalive messages.',
    'yes or no',
  ),
  HarborSSHOption(
    'Compression',
    'Compress data sent through SSH.',
    'yes or no',
  ),
  HarborSSHOption(
    'ForwardAgent',
    'Forward access to your authentication agent.',
    'yes or no',
  ),
  HarborSSHOption(
    'ForwardX11',
    'Forward X11 graphical applications.',
    'yes or no',
  ),
  HarborSSHOption(
    'ForwardX11Trusted',
    'Allow trusted X11 forwarding.',
    'yes or no',
  ),
  HarborSSHOption(
    'ExitOnForwardFailure',
    'Exit when requested forwarding cannot be established.',
    'yes or no',
  ),
  HarborSSHOption(
    'IdentitiesOnly',
    'Use only explicitly configured authentication identities.',
    'yes or no',
  ),
  HarborSSHOption(
    'IdentityAgent',
    'Authentication agent socket path.',
    'SSH_AUTH_SOCK or none',
  ),
  HarborSSHOption(
    'AddKeysToAgent',
    'Add loaded private keys to your agent.',
    'yes, no, ask or confirm',
  ),
  HarborSSHOption(
    'PreferredAuthentications',
    'Authentication methods in priority order.',
    'publickey,password',
  ),
  HarborSSHOption(
    'PasswordAuthentication',
    'Allow password authentication.',
    'yes or no',
  ),
  HarborSSHOption(
    'PubkeyAuthentication',
    'Allow public key authentication.',
    'yes or no',
  ),
  HarborSSHOption(
    'BatchMode',
    'Disable interactive authentication prompts.',
    'yes or no',
  ),
  HarborSSHOption(
    'StrictHostKeyChecking',
    'Control acceptance of server host keys.',
    'ask, yes, accept-new or no',
  ),
  HarborSSHOption(
    'UserKnownHostsFile',
    'File containing trusted server host keys.',
    '~/.ssh/known_hosts',
  ),
  HarborSSHOption(
    'LogLevel',
    'Verbosity of SSH diagnostic messages.',
    'INFO or VERBOSE',
  ),
  HarborSSHOption(
    'AddressFamily',
    'Choose IPv4, IPv6 or either.',
    'any, inet or inet6',
  ),
  HarborSSHOption(
    'ControlMaster',
    'Share connections through a control socket.',
    'auto, ask, yes or no',
  ),
  HarborSSHOption(
    'ControlPath',
    'Path for the connection sharing socket.',
    '~/.ssh/cm-%C',
  ),
  HarborSSHOption(
    'ControlPersist',
    'Keep shared connections after the session exits.',
    '10m',
  ),
  HarborSSHOption(
    'SendEnv',
    'Environment variable names sent to the server.',
    'LANG LC_*',
  ),
  HarborSSHOption(
    'SetEnv',
    'Environment variables sent as explicit assignments.',
    'NAME=value',
  ),
  HarborSSHOption(
    'RequestTTY',
    'When to request a remote terminal.',
    'auto, yes, no or force',
  ),
  HarborSSHOption(
    'RemoteCommand',
    'Command to execute after connecting.',
    'tmux attach',
  ),
];

HarborSSHOption? harborSSHOption(String key) {
  for (final option in harborSSHOptions) {
    if (option.name.toLowerCase() == key.toLowerCase()) return option;
  }
  return null;
}

class HarborAdvancedOptionsPage extends StatefulWidget {
  final SSHHost host;
  const HarborAdvancedOptionsPage({super.key, required this.host});
  @override
  State<HarborAdvancedOptionsPage> createState() =>
      _HarborAdvancedOptionsPageState();
}

class _HarborAdvancedOptionsPageState extends State<HarborAdvancedOptionsPage> {
  final pending = <String>{};
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  String? focusKey;
  late final order = widget.host.advancedOptions.keys.toList();
  @override
  void didUpdateWidget(HarborAdvancedOptionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host)) {
      pending.clear();
      order
        ..clear()
        ..addAll(widget.host.advancedOptions.keys);
      focusKey = null;
    }
  }

  Future<void> addOption() async {
    final selected = await showHarborSheet<HarborSSHOption>(
      context: context,
      barrierDismissible: true,
      builder: (_) => HarborSSHOptionPicker(
        excluded: {
          ...widget.host.advancedOptions.keys.map((key) => key.toLowerCase()),
          ...pending.map((key) => key.toLowerCase()),
        },
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      pending.add(selected.name);
      order.add(selected.name);
      focusKey = selected.name;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !scroll.hasClients) return;
    final duration = harborMotion(context, 220);
    if (duration == Duration.zero) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
    } else {
      await scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: duration,
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    final store = context.read<SSHStore>();
    final host = widget.host;
    order.removeWhere(
      (key) => !host.advancedOptions.containsKey(key) && !pending.contains(key),
    );
    for (final key in host.advancedOptions.keys) {
      if (!order.contains(key)) order.add(key);
    }
    final keys = List<String>.of(order);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SSH options',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Add only the options you want to customize.',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            HarborButton(
              label: 'Add option',
              icon: CupertinoIcons.plus,
              onPressed: addOption,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: keys.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.slider_horizontal_3,
                          size: 26,
                          color: colors.muted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No custom options',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'SSH uses its existing configuration and defaults.',
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  controller: scroll,
                  children: [
                    for (final key in keys)
                      Builder(
                        key: ValueKey(key),
                        builder: (context) {
                          final option = harborSSHOption(key);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              border: Border.all(color: colors.border),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option?.name ?? key,
                                            style: TextStyle(
                                              color: colors.text,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            option?.description ??
                                                'Imported SSH option. Kept as configured.',
                                            style: TextStyle(
                                              color: colors.muted,
                                              fontSize: 11,
                                              height: 1.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Tooltip(
                                      message: 'Remove ${option?.name ?? key}',
                                      child: CupertinoButton(
                                        padding: const EdgeInsets.all(4),
                                        minimumSize: Size.zero,
                                        onPressed: () {
                                          final changed = host.advancedOptions
                                              .containsKey(key);
                                          setState(() {
                                            pending.remove(key);
                                            host.advancedOptions.remove(key);
                                          });
                                          if (changed) {
                                            store.markDirty(host.hostAlias);
                                          }
                                        },
                                        child: Icon(
                                          CupertinoIcons.minus_circle,
                                          size: 18,
                                          color: colors.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                HarborTextField(
                                  key: ValueKey('option-value-$key'),
                                  initialValue: host.advancedOptions[key] ?? '',
                                  autofocus: key == focusKey,
                                  placeholder: option == null
                                      ? 'Value'
                                      : 'e.g. ${option.example}',
                                  validator: (value) =>
                                      value.contains('\n') ||
                                          value.contains('\r')
                                      ? 'Enter a single-line SSH value.'
                                      : null,
                                  onChanged: (value) {
                                    if (value.contains('\n') ||
                                        value.contains('\r')) {
                                      return;
                                    }
                                    pending.add(key);
                                    if (value.trim().isEmpty) {
                                      host.advancedOptions.remove(key);
                                    } else {
                                      host.advancedOptions[key] = value.trim();
                                    }
                                    store.markDirty(host.hostAlias);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class HarborSSHOptionPicker extends StatefulWidget {
  final Set<String> excluded;
  const HarborSSHOptionPicker({super.key, this.excluded = const {}});
  @override
  State<HarborSSHOptionPicker> createState() => _HarborSSHOptionPickerState();
}

class _HarborSSHOptionPickerState extends State<HarborSSHOptionPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    final terms = query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty);
    final options = harborSSHOptions
        .where(
          (option) =>
              !widget.excluded.contains(option.name.toLowerCase()) &&
              terms.every(
                (term) => '${option.name} ${option.description}'
                    .toLowerCase()
                    .contains(term),
              ),
        )
        .toList();
    return Container(
      width: (MediaQuery.sizeOf(context).width - 48).clamp(0, 560),
      height: (MediaQuery.sizeOf(context).height - 64).clamp(0, 540),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add SSH option',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              HarborButton(
                label: 'Cancel',
                secondary: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          HarborTextField(
            autofocus: true,
            placeholder: 'Search options or descriptions…',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Icon(CupertinoIcons.search),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: options.isEmpty
                ? Center(
                    child: Text(
                      'No matching options',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  )
                : ListView(
                    children: [
                      for (final option in options)
                        _HarborSSHOptionChoice(
                          option: option,
                          onSelected: () => Navigator.of(context).pop(option),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HarborSSHOptionChoice extends StatefulWidget {
  final HarborSSHOption option;
  final VoidCallback onSelected;
  const _HarborSSHOptionChoice({
    required this.option,
    required this.onSelected,
  });
  @override
  State<_HarborSSHOptionChoice> createState() => _HarborSSHOptionChoiceState();
}

class _HarborSSHOptionChoiceState extends State<_HarborSSHOptionChoice> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: 1,
        onPressed: widget.onSelected,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: hovered
                ? colors.text.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.option.name,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.option.description,
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(CupertinoIcons.plus, size: 15, color: colors.accent),
            ],
          ),
        ),
      ),
    );
  }
}
