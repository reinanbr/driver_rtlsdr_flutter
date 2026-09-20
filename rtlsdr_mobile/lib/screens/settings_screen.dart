import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Tela de configurações: gerenciamento das gravações salvas (listar,
/// compartilhar, apagar — mesmo diretório usado por RecordingController)
/// e informações do app/licença.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _SectionCard(title: 'Gravações', child: _RecordingsManager()),
          SizedBox(height: 16),
          _SectionCard(title: 'Sobre', child: _AboutSection()),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _RecordingsManager extends StatefulWidget {
  const _RecordingsManager();

  @override
  State<_RecordingsManager> createState() => _RecordingsManagerState();
}

class _RecordingsManagerState extends State<_RecordingsManager> {
  bool _loading = true;
  List<File> _files = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final baseDir = await getExternalStorageDirectory();
      if (baseDir == null) {
        setState(() {
          _error = 'Armazenamento externo indisponível';
          _loading = false;
        });
        return;
      }
      final dir = Directory('${baseDir.path}/Recordings');
      if (!await dir.exists()) {
        setState(() {
          _files = const [];
          _loading = false;
        });
        return;
      }
      final files = await dir
          .list()
          .where((entry) => entry is File && entry.path.toLowerCase().endsWith('.wav'))
          .cast<File>()
          .toList();
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      setState(() {
        _files = files;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Falha ao listar gravações: $e';
        _loading = false;
      });
    }
  }

  Future<void> _delete(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar gravação'),
        content: Text('Apagar "${_fileName(file)}"? Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Apagar')),
        ],
      ),
    );
    if (confirmed != true) return;
    await file.delete();
    _load();
  }

  String _fileName(File file) => file.uri.pathSegments.last;

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
    if (_files.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Nenhuma gravação salva ainda.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final file in _files)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              title: Text(_fileName(file), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${_formatSize(file.lengthSync())} · ${file.statSync().modified.toString().substring(0, 16)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Compartilhar',
                    onPressed: () => Share.shareXFiles([XFile(file.path)]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Apagar',
                    onPressed: () => _delete(file),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.radio, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('RTL-SDR Mobile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Versão 1.0.0'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Cliente Android para dongles RTL-SDR via USB-OTG: sintonia WFM/NFM/AM, '
          'estéreo e RDS em WFM, waterfall, scan automático de frequências, presets '
          'e gravação/exportação de áudio.',
        ),
        const SizedBox(height: 16),
        Text('Licença', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        const Text(
          'GPLv2, ou (a seu critério) qualquer versão posterior — ver o arquivo LICENSE '
          'na raiz do repositório. O app vincula librtlsdr (GPLv2-or-later), o que exige '
          'que o app inteiro seja distribuído sob GPL.',
        ),
        const SizedBox(height: 12),
        Text('Componentes de terceiros', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        const _ThirdPartyRow(name: 'librtlsdr 2.1.0', license: 'GPLv2-or-later'),
        const _ThirdPartyRow(name: 'libusb 1.0.30', license: 'LGPL-2.1'),
        const _ThirdPartyRow(name: 'KissFFT', license: 'BSD-3-Clause'),
        const _ThirdPartyRow(name: 'Oboe', license: 'Apache-2.0'),
      ],
    );
  }
}

class _ThirdPartyRow extends StatelessWidget {
  const _ThirdPartyRow({required this.name, required this.license});

  final String name;
  final String license;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name),
          Text(license, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
