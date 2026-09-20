import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'settings_screen.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UsbChannel>().refreshConnectedDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final usb = context.watch<UsbState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('RTL-SDR Mobile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _StatusIcon(status: usb.status),
            const SizedBox(height: 16),
            Text(
              _statusLabel(usb.status),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (usb.device != null) _DeviceInfoCard(device: usb.device!),
            if (usb.lastError != null) ...[
              const SizedBox(height: 16),
              Text(
                usb.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
            if (usb.status == UsbConnectionStatus.attached)
              FilledButton.icon(
                onPressed: () => context.read<UsbChannel>().requestPermission(),
                icon: const Icon(Icons.usb),
                label: const Text('Conceder permissão USB'),
              ),
            if (usb.status == UsbConnectionStatus.permissionRequested)
              const CircularProgressIndicator(),
            if (usb.status == UsbConnectionStatus.permissionDenied)
              FilledButton.icon(
                onPressed: () => context.read<UsbChannel>().requestPermission(),
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            if (usb.status == UsbConnectionStatus.noDevice) ...[
              const SizedBox(height: 8),
              const Text(
                'Conecte o dongle RTL-SDR via cabo USB-OTG.',
                textAlign: TextAlign.center,
              ),
            ],
            if (usb.status == UsbConnectionStatus.deviceReady)
              const _TunerPanel(),
          ],
        ),
      ),
    );
  }

  String _statusLabel(UsbConnectionStatus status) {
    return switch (status) {
      UsbConnectionStatus.noDevice => 'Nenhum dongle RTL-SDR detectado',
      UsbConnectionStatus.attached => 'Dongle conectado — permissão necessária',
      UsbConnectionStatus.permissionRequested => 'Aguardando permissão...',
      UsbConnectionStatus.permissionGranted => 'Permissão concedida',
      UsbConnectionStatus.permissionDenied => 'Permissão negada',
      UsbConnectionStatus.deviceReady => 'Driver nativo pronto',
    };
  }
}

/// Painel de sintonia: frequência, modo de demodulação (WFM/NFM/AM), ganho
/// (automático/manual) e squelch (NFM/AM), além de estatísticas de
/// streaming (taxa de IQ, overflow, nível de RF/áudio). Os painéis em si
/// (ganho, gravação, scan, presets, espectro) vêm de
/// `package:driver_rtlsdr/driver_rtlsdr.dart` — aqui fica só a composição.
class _TunerPanel extends StatefulWidget {
  const _TunerPanel();

  @override
  State<_TunerPanel> createState() => _TunerPanelState();
}

class _TunerPanelState extends State<_TunerPanel> {
  late final TextEditingController _freqController;
  final FocusNode _freqFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final radio = context.read<RadioController>();
    _freqController = TextEditingController(
      text: (radio.frequencyHz / 1e6).toStringAsFixed(3),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RadioController>().refreshGainList();
    });
  }

  @override
  void dispose() {
    _freqController.dispose();
    _freqFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioController>();
    final recording = context.read<RecordingController>();
    final scan = context.read<ScanController>();
    final presets = context.read<PresetsController>();

    // Mantém o campo sincronizado quando a frequência muda por fora (ex.
    // ao aplicar um preset) — mas nunca enquanto o usuário está digitando.
    final expectedFreqText = (radio.frequencyHz / 1e6).toStringAsFixed(3);
    if (!_freqFocusNode.hasFocus && _freqController.text != expectedFreqText) {
      _freqController.text = expectedFreqText;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sintonia', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _freqController,
                    focusNode: _freqFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Frequência (MHz)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final mhz = double.tryParse(
                      _freqController.text.replaceAll(',', '.'),
                    );
                    if (mhz != null) {
                      context.read<RadioController>().setFrequencyHz(
                        (mhz * 1e6).round(),
                      );
                    }
                  },
                  child: const Text('Aplicar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: ModeSelector(radio: radio),
            ),
            if (radio.demodMode.supportsStereoAndRds) ...[
              const SizedBox(height: 8),
              StereoRdsPanel(radio: radio),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: radio.isStreaming
                  ? () => _stopStreaming(context)
                  : () => context.read<RadioController>().startStreaming(),
              icon: Icon(radio.isStreaming ? Icons.stop : Icons.play_arrow),
              label: Text(
                radio.isStreaming ? 'Parar streaming' : 'Iniciar streaming',
              ),
            ),
            const Divider(height: 32),
            // Grava no armazenamento específico do app
            // (<external>/Recordings), que é o mesmo diretório listado pela
            // tela de configurações — sem buildFilePath o painel do pacote
            // gravaria direto na pasta pública Downloads.
            RecordingPanel(
              radio: radio,
              recording: recording,
              buildFilePath: () => defaultRecordingPath(
                frequencyHz: radio.frequencyHz,
                mode: radio.demodMode,
              ),
              buildIqFilePath: () =>
                  defaultIqRecordingPath(frequencyHz: radio.frequencyHz),
            ),
            const Divider(height: 32),
            ScanPanel(radio: radio, scan: scan, presets: presets),
            const Divider(height: 32),
            PresetsPanel(radio: radio, presets: presets),
            const Divider(height: 32),
            // Cabeçalho "immersive" do pacote (SignalMeter + FrequencyReadout
            // odômetro + PowerReadout + botão Start/Stop), o mesmo usado em
            // RtlSdrImmersiveScreen — posicionado direto em cima do
            // comparativo de sintonizadores por espectro abaixo, pra testar
            // esse controle de frequência mais refinado junto com cada
            // variante.
            _ImmersiveTuningHeader(
              radio: radio,
              onStop: () => _stopStreaming(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Sintonia por espectro',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Arraste pra passar de frequência, toque pra sintonizar direto num ponto.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 150,
                // SpectrumScope, not SpectrumTuner — the latter bundles its
                // own internal waterfall (scope + waterfall stacked), which
                // duplicated the separate "Espectro" WaterfallView section
                // right below. SpectrumScope is the scope-only widget, same
                // as this app's original single-strip spectrum tuner.
                child: SpectrumScope(
                  spectrum: radio.spectrumController,
                  centerFrequencyHz: radio.frequencyHz,
                  spanHz: radio.sampleRateHz,
                  passbandHz: defaultPassbandHzFor(radio.demodMode),
                  onFrequencyChanged: (hz) =>
                      context.read<RadioController>().setFrequencyHz(hz),
                ),
              ),
            ),
            const Divider(height: 32),
            Text('Espectro', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 160,
                child: WaterfallView(
                  spectrum: radio.spectrumController,
                  historyRows: 60,
                  spanHz: radio.sampleRateHz,
                  passbandHz: defaultPassbandHzFor(radio.demodMode),
                ),
              ),
            ),
            const Divider(height: 32),
            GainPanel(radio: radio),
            if (radio.demodMode.supportsSquelch) ...[
              const Divider(height: 32),
              Text('Squelch', style: Theme.of(context).textTheme.titleMedium),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: radio.squelchThresholdDb.clamp(-100.0, 0.0),
                      min: -100,
                      max: 0,
                      label:
                          '${radio.squelchThresholdDb.toStringAsFixed(0)} dBFS',
                      onChanged: (v) => context
                          .read<RadioController>()
                          .setSquelchThresholdDb(v),
                    ),
                  ),
                  Icon(
                    radio.squelchOpen ? Icons.mic : Icons.mic_off,
                    color: radio.squelchOpen ? Colors.green : Colors.grey,
                  ),
                ],
              ),
            ],
            const Divider(height: 32),
            Text(
              'Estatísticas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _statRow(
              'IQ recebido',
              '${(radio.bytesPerSecond / 1e6).toStringAsFixed(2)} MB/s',
            ),
            _statRow(
              'Total recebido',
              '${(radio.iqBytesReceived / 1e6).toStringAsFixed(2)} MB',
            ),
            _statRow('Overflow do ring buffer', '${radio.ringOverflowCount}'),
            _statRow(
              'Nível RF',
              '${radio.rfLevelDbfs.toStringAsFixed(1)} dBFS',
            ),
            _statRow(
              'Nível áudio',
              '${radio.audioLevelDbfs.toStringAsFixed(1)} dBFS',
            ),
            if (radio.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                radio.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// Para uma gravação em andamento ANTES de parar o streaming — parar o
  /// streaming primeiro finalizaria a gravação do lado nativo de qualquer
  /// forma (shim_stop_streaming chama stop_recording_if_active
  /// internamente, ver rtlsdr_shim.c), mas o estado `isRecording` do lado
  /// Dart (RecordingController) ficaria dessincronizado — nessa ordem,
  /// RecordingController.stopRecording() sempre reflete o que de fato
  /// aconteceu.
  void _stopStreaming(BuildContext context) {
    final scan = context.read<ScanController>();
    if (scan.isScanning) {
      scan.stopScan();
    }
    final recording = context.read<RecordingController>();
    if (recording.isRecording) {
      recording.stopRecording();
    }
    context.read<RadioController>().stopStreaming();
  }
}

/// SignalMeter + FrequencyReadout (odômetro, um dígito por vez) +
/// PowerReadout + botão Start/Stop — a mesma composição do cabeçalho de
/// `RtlSdrImmersiveScreen` no pacote, reaproveitada aqui como um cabeçalho
/// de sintonia mais refinado que o TextField simples do card "Sintonia".
class _ImmersiveTuningHeader extends StatelessWidget {
  const _ImmersiveTuningHeader({required this.radio, required this.onStop});

  final RadioController radio;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SignalMeter(
          valueDb: radio.rfLevelDbfs,
          squelchDb: radio.demodMode.supportsSquelch
              ? radio.squelchThresholdDb
              : null,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: FrequencyReadout(
                  frequencyHz: radio.frequencyHz,
                  onChanged: radio.setFrequencyHz,
                  // Drops the ones/tens/hundreds-of-Hz digits — RTL-SDR
                  // tuning never needs sub-kHz precision, and they'd read
                  // "0" forever anyway — leaving fewer, bigger digit cells
                  // that are easier to tap under each one.
                  digitCount: 7,
                  minStepHz: 1000,
                ),
              ),
            ),
            const SizedBox(width: 12),
            PowerReadout(valueDb: radio.rfLevelDbfs),
            const SizedBox(width: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: radio.isStreaming
                    ? theme.meterHot
                    : theme.accent,
                foregroundColor: theme.background,
              ),
              onPressed: radio.isStreaming ? onStop : radio.startStreaming,
              icon: Icon(radio.isStreaming ? Icons.stop : Icons.play_arrow),
              label: Text(radio.isStreaming ? 'Stop' : 'Start'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final UsbConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      UsbConnectionStatus.noDevice => (Icons.usb_off, Colors.grey),
      UsbConnectionStatus.attached => (Icons.usb, Colors.orange),
      UsbConnectionStatus.permissionRequested => (Icons.usb, Colors.blue),
      UsbConnectionStatus.permissionGranted => (
        Icons.check_circle,
        Colors.green,
      ),
      UsbConnectionStatus.permissionDenied => (Icons.error, Colors.red),
      UsbConnectionStatus.deviceReady => (Icons.check_circle, Colors.teal),
    };
    return Icon(icon, size: 72, color: color);
  }
}

class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({required this.device});

  final UsbDeviceInfo device;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('VID', device.vendorIdHex),
            _row('PID', device.productIdHex),
            _row('Nome', device.productName ?? device.deviceName),
            if (device.manufacturerName != null)
              _row('Fabricante', device.manufacturerName!),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
