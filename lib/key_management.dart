part of 'main.dart';

class KeyLibrary {
  final Directory directory;
  KeyLibrary({Directory? directory})
    : directory =
          directory ?? Directory('${Platform.environment['HOME']}/.ssh');

  Future<bool> isPrivateKey(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final header = utf8.decode(await handle.read(256), allowMalformed: true);
      return RegExp(
        r'^-----BEGIN (?:OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY-----',
      ).hasMatch(header);
    } on FileSystemException {
      return false;
    } finally {
      await handle?.close();
    }
  }

  Future<List<String>> listKeys() async {
    if (!await directory.exists()) return [];
    final keys = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && await isPrivateKey(entity)) keys.add(entity.path);
    }
    return keys..sort((a, b) => p.basename(a).compareTo(p.basename(b)));
  }

  Future<String> keyType(String path) async {
    String label(String type) {
      if (type == 'ssh-ed25519') return 'Ed25519';
      if (type == 'ssh-rsa' || type.startsWith('rsa-sha2-')) return 'RSA';
      if (type == 'ssh-dss') return 'DSA';
      if (type.startsWith('ecdsa-sha2-')) {
        return 'ECDSA (${type.substring(11)})';
      }
      if (type.startsWith('sk-ssh-ed25519')) return 'Ed25519 · security key';
      if (type.startsWith('sk-ecdsa-sha2-')) return 'ECDSA · security key';
      return 'Unknown type';
    }

    // OpenSSH stores the public blob before the encrypted private material.
    // Read only enough to identify its algorithm; never prompt for a passphrase.
    try {
      final file = await File(path).open();
      late String text;
      try {
        text = utf8.decode(await file.read(65536), allowMalformed: true);
      } finally {
        await file.close();
      }
      if (text.startsWith('-----BEGIN OPENSSH PRIVATE KEY-----')) {
        final encoded = text.split('-----')[2].replaceAll(RegExp(r'\s'), '');
        final bytes = base64.decode(encoded);
        const magic = 'openssh-key-v1\x00';
        if (bytes.length < magic.length ||
            ascii.decode(bytes.take(magic.length).toList()) != magic) {
          throw const FormatException('Invalid OpenSSH header');
        }
        var offset = magic.length;
        Uint8List readString() {
          if (offset + 4 > bytes.length) {
            throw const FormatException('Truncated key');
          }
          final length = ByteData.sublistView(
            bytes,
            offset,
            offset + 4,
          ).getUint32(0);
          offset += 4;
          if (offset + length > bytes.length) {
            throw const FormatException('Truncated key');
          }
          final value = Uint8List.sublistView(bytes, offset, offset + length);
          offset += length;
          return value;
        }

        readString(); // Cipher.
        readString(); // KDF.
        readString(); // KDF options.
        if (offset + 4 > bytes.length) {
          throw const FormatException('Truncated key');
        }
        final count = ByteData.sublistView(
          bytes,
          offset,
          offset + 4,
        ).getUint32(0);
        offset += 4;
        if (count < 1) throw const FormatException('Missing public key');
        final public = readString();
        if (public.length < 4) {
          throw const FormatException('Truncated public key');
        }
        final length = ByteData.sublistView(public, 0, 4).getUint32(0);
        if (length > public.length - 4) {
          throw const FormatException('Truncated algorithm');
        }
        return label(ascii.decode(public.sublist(4, 4 + length)));
      }
      if (text.startsWith('-----BEGIN RSA PRIVATE KEY-----')) return 'RSA';
      if (text.startsWith('-----BEGIN EC PRIVATE KEY-----')) return 'ECDSA';
      if (text.startsWith('-----BEGIN DSA PRIVATE KEY-----')) return 'DSA';
    } on FileSystemException {
      // A companion public key can still describe an unavailable private file.
    } on FormatException {
      // Malformed or unsupported containers use the public file if available.
    }
    try {
      final text = await File('$path.pub').readAsString();
      return label(text.trim().split(RegExp(r'\s+')).first);
    } on FileSystemException {
      return 'Unknown type';
    } on FormatException {
      return 'Unknown type';
    }
  }

  Future<void> _prepareDirectory() async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      await _permissions(directory.path, '700');
    }
  }

  Future<void> _permissions(String path, String mode) async {
    final result = await Process.run('/bin/chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('Could not set key permissions', path);
    }
  }

  Future<String> generate(
    String filename,
    String type,
    String passphrase,
  ) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(filename)) {
      throw const FormatException(
        'Use a filename containing letters, numbers, dots, underscores or hyphens.',
      );
    }
    if (!['ed25519', 'rsa'].contains(type)) {
      throw const FormatException('Unsupported key type.');
    }
    await _prepareDirectory();
    final path = p.join(directory.path, filename);
    if (await File(path).exists() || await File('$path.pub').exists()) {
      throw const FormatException('A key with this filename already exists.');
    }
    final result = await Process.run('/usr/bin/ssh-keygen', [
      '-t',
      type,
      if (type == 'rsa') ...['-b', '4096'],
      '-f',
      path,
      '-N',
      passphrase,
      '-C',
      'harbor-ssh',
    ]);
    if (result.exitCode != 0) {
      throw Exception(
        'Key generation failed: ${result.stderr.toString().trim()}',
      );
    }
    await _permissions(path, '600');
    return path;
  }

  Future<String> importKey(String source) async {
    final file = File(source);
    if (!await isPrivateKey(file)) {
      throw const FormatException('Select an OpenSSH or PEM private key file.');
    }
    await _prepareDirectory();
    final destination = p.join(directory.path, p.basename(source));
    if (p.normalize(p.absolute(source)) ==
        p.normalize(p.absolute(destination))) {
      return destination;
    }
    if (await File(destination).exists() ||
        await File('$destination.pub').exists()) {
      throw const FormatException(
        'A key with this filename already exists. Rename it before importing.',
      );
    }
    // Create the private file with restrictive permissions before writing key bytes.
    await File(destination).create(exclusive: true);
    try {
      await _permissions(destination, '600');
      await File(
        destination,
      ).writeAsBytes(await file.readAsBytes(), flush: true);
      if (await File('$source.pub').exists()) {
        await File('$source.pub').copy('$destination.pub');
      }
    } catch (_) {
      await File(destination).delete();
      rethrow;
    }
    return destination;
  }

  Future<String?> fingerprint(String path) async {
    if (!await File('$path.pub').exists()) return null;
    final result = await Process.run('/usr/bin/ssh-keygen', [
      '-l',
      '-f',
      '$path.pub',
    ]);
    return result.exitCode == 0 ? result.stdout.toString().trim() : null;
  }
}

class HarborKeysPage extends StatefulWidget {
  final KeyLibrary? library;
  const HarborKeysPage({super.key, this.library});
  @override
  State<HarborKeysPage> createState() => _HarborKeysPageState();
}

class _HarborKeysPageState extends State<HarborKeysPage> {
  late final KeyLibrary library = widget.library ?? KeyLibrary();
  List<({String path, String type, String? fingerprint, bool publicKey})> keys =
      [];
  bool busy = false;
  String? message;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => busy = true);
    try {
      final paths = await library.listKeys();
      final entries = await Future.wait(
        paths.map(
          (path) async => (
            path: path,
            type: await library.keyType(path),
            fingerprint: await library.fingerprint(path),
            publicKey: await File('$path.pub').exists(),
          ),
        ),
      );
      if (mounted) setState(() => keys = entries);
    } catch (error) {
      if (mounted) {
        setState(() {
          message = '$error';
          failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _run(Future<String> Function() action, String success) async {
    setState(() {
      busy = true;
      message = null;
      failed = false;
    });
    try {
      final path = await action();
      if (mounted) setState(() => message = '$success ${p.basename(path)}');
    } catch (error) {
      if (mounted) {
        setState(() {
          message = '$error';
          failed = true;
        });
      }
    }
    if (mounted) await _refresh();
  }

  Future<void> _import() async {
    try {
      final path = await const MethodChannel(
        'harbor/files',
      ).invokeMethod<String>('pickPrivateKey');
      if (path != null && mounted) {
        await _run(() => library.importKey(path), 'Imported');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          message = '$error';
          failed = true;
        });
      }
    }
  }

  Future<void> _generate() async {
    final name = TextEditingController(text: 'id_ed25519_harbor');
    final passphrase = TextEditingController();
    var type = 'ed25519';
    final request =
        await showHarborDialog<({String name, String type, String passphrase})>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) {
              final valid = RegExp(
                r'^[A-Za-z0-9][A-Za-z0-9._-]*$',
              ).hasMatch(name.text.trim());
              void submit() {
                if (valid) {
                  Navigator.pop(dialogContext, (
                    name: name.text.trim(),
                    type: type,
                    passphrase: passphrase.text,
                  ));
                }
              }

              return HarborAlert(
                appIcon: const Icon(Icons.key_outlined),
                title: const Text('Generate SSH key'),
                message: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HarborSegmentedControl<String>(
                      groupValue: type,
                      children: const {
                        'ed25519': Text('Ed25519'),
                        'rsa': Text('RSA 4096'),
                      },
                      onValueChanged: (value) => update(() {
                        type = value!;
                        name.text = 'id_${type}_harbor';
                      }),
                    ),
                    const SizedBox(height: 16),
                    const Text('Filename'),
                    const SizedBox(height: 6),
                    HarborTextField(
                      controller: name,
                      autofocus: true,
                      onChanged: (_) => update(() {}),
                      onSubmitted: (_) => submit(),
                    ),
                    const SizedBox(height: 12),
                    const Text('Passphrase (optional)'),
                    const SizedBox(height: 6),
                    HarborTextField(
                      controller: passphrase,
                      obscureText: true,
                      onSubmitted: (_) => submit(),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Saved in ~/.ssh. The private key stays on this Mac.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                secondaryButton: HarborButton(
                  label: 'Cancel',
                  secondary: true,
                  onPressed: () => Navigator.pop(dialogContext),
                ),
                primaryButton: HarborButton(
                  label: 'Generate',
                  onPressed: valid ? submit : null,
                ),
              );
            },
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    name.dispose();
    passphrase.dispose();
    if (request != null && mounted) {
      await _run(
        () => library.generate(request.name, request.type, request.passphrase),
        'Generated',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = HarborColors.of(context);
    final store = context.watch<SSHStore>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HarborPageHeader(
            title: 'SSH keys',
            subtitle: '${keys.length} keys in ~/.ssh',
            secondaryAction: HarborButton(
              label: 'Import',
              secondary: true,
              fullWidth: true,
              icon: CupertinoIcons.square_arrow_down,
              busy: busy,
              onPressed: _import,
            ),
            primaryAction: HarborButton(
              label: 'Generate key',
              icon: CupertinoIcons.plus,
              fullWidth: true,
              busy: busy,
              onPressed: _generate,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Manage keys used by your SSH connections.',
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              ),
              HarborButton(
                label: 'Refresh',
                secondary: true,
                busy: busy,
                onPressed: _refresh,
              ),
            ],
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                message!,
                style: TextStyle(
                  fontSize: 12,
                  color: failed
                      ? CupertinoColors.destructiveRed
                      : HarborColors.teal,
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: ProgressCircle(radius: 8),
            ),
          Expanded(
            child: keys.isEmpty && !busy
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.key_outlined, size: 32, color: colors.muted),
                        const SizedBox(height: 12),
                        Text(
                          'No SSH keys yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Import an existing private key or generate a new pair.',
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: keys.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final key = keys[index];
                      final uses = store.hosts
                          .where(
                            (host) =>
                                host.identityFile.replaceFirst(
                                  '~',
                                  Platform.environment['HOME'] ?? '',
                                ) ==
                                key.path,
                          )
                          .length;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: colors.accent.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                Icons.key_outlined,
                                size: 18,
                                color: colors.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        p.basename(key.path),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: colors.text,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.accent.withValues(
                                            alpha: 0.10,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                        child: Text(
                                          key.type,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: colors.accent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    key.fingerprint ??
                                        'Public key file unavailable',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'Menlo',
                                      color: colors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '$uses connections · ${key.path}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            HarborButton(
                              label: 'Copy public key',
                              secondary: true,
                              onPressed: !key.publicKey || busy
                                  ? null
                                  : () async {
                                      try {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: await File(
                                              '${key.path}.pub',
                                            ).readAsString(),
                                          ),
                                        );
                                        if (mounted) {
                                          setState(() {
                                            message = 'Public key copied';
                                            failed = false;
                                          });
                                        }
                                      } catch (error) {
                                        if (mounted) {
                                          setState(() {
                                            message = '$error';
                                            failed = true;
                                          });
                                        }
                                      }
                                    },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
