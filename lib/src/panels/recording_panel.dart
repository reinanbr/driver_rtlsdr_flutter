import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// WAV + raw I/Q recording subscreen over [RecordingController] — by
/// default, records into the real, shared Downloads folder via
/// [RecordingController.startRecordingToDownloads]/
/// [RecordingController.startIqRecordingToDownloads] (falls back
/// automatically to app-specific storage on Android below API 29), unless
/// [buildFilePath]/[buildIqFilePath] are given, in which case recording
/// goes to exactly that path instead. The two recordings are independent —
/// both can run at once, same as [RecordingController] allows. Each
/// completed recording gets a share button (Android's native share sheet).
class RecordingPanel extends StatelessWidget {
  const RecordingPanel({
    super.key,
    required this.radio,
    required this.recording,
    this.buildFilePath,
    this.buildIqFilePath,
  });

  final RadioController radio;
  final RecordingController recording;
  final Future<String> Function()? buildFilePath;
  final Future<String> Function()? buildIqFilePath;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([radio, recording]),
      builder: (context, _) {
        return RtlSdrPanel(
          title: 'RECORDING',
          icon: Icons.fiber_manual_record,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _RecordButton(
                      theme: theme,
                      label: 'PCM',
                      isRecording: recording.isRecording,
                      enabled: radio.isStreaming,
                      onPressed: recording.isRecording
                          ? recording.stopRecording
                          : _startPcm,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RecordButton(
                      theme: theme,
                      label: 'I/Q',
                      isRecording: recording.isIqRecording,
                      enabled: radio.isStreaming,
                      onPressed: recording.isIqRecording
                          ? recording.stopIqRecording
                          : _startIq,
                    ),
                  ),
                ],
              ),
              if (recording.isRecording &&
                  recording.currentFilePath != null) ...[
                const SizedBox(height: 8),
                _fileRow(
                  theme,
                  'PCM: ${recording.currentFilePath}',
                  radio.recordingBytesWritten,
                ),
              ],
              if (!recording.isRecording &&
                  recording.lastRecordingPath != null) ...[
                const SizedBox(height: 8),
                _savedRow(
                  theme,
                  'PCM saved: ${recording.lastRecordingPath}',
                  recording.shareRecording,
                ),
              ],
              if (recording.isIqRecording &&
                  recording.currentIqFilePath != null) ...[
                const SizedBox(height: 8),
                _fileRow(
                  theme,
                  'I/Q: ${recording.currentIqFilePath}',
                  radio.iqRecordingBytesWritten,
                ),
              ],
              if (!recording.isIqRecording &&
                  recording.lastIqRecordingPath != null) ...[
                const SizedBox(height: 8),
                _savedRow(
                  theme,
                  'I/Q saved: ${recording.lastIqRecordingPath}',
                  recording.shareIqRecording,
                ),
              ],
              if (recording.lastError != null) ...[
                const SizedBox(height: 8),
                Text(
                  recording.lastError!,
                  style: TextStyle(color: theme.meterHot),
                ),
              ],
              if (recording.lastIqError != null) ...[
                const SizedBox(height: 8),
                Text(
                  recording.lastIqError!,
                  style: TextStyle(color: theme.meterHot),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _fileRow(RtlSdrThemeData theme, String path, int bytesWritten) {
    return Text(
      '$path (${(bytesWritten / 1e6).toStringAsFixed(2)} MB)',
      style: TextStyle(color: theme.textSecondary, fontSize: 12),
    );
  }

  Widget _savedRow(
    RtlSdrThemeData theme,
    String text,
    Future<void> Function() onShare,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ),
        IconButton(
          icon: Icon(Icons.share, size: 18, color: theme.textSecondary),
          tooltip: 'Share',
          onPressed: onShare,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Future<void> _startPcm() async {
    if (buildFilePath != null) {
      await recording.startRecording(await buildFilePath!());
      return;
    }
    await recording.startRecordingToDownloads(
      frequencyHz: radio.frequencyHz,
      mode: radio.demodMode,
    );
  }

  Future<void> _startIq() async {
    if (buildIqFilePath != null) {
      await recording.startIqRecording(await buildIqFilePath!());
      return;
    }
    await recording.startIqRecordingToDownloads(frequencyHz: radio.frequencyHz);
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.theme,
    required this.label,
    required this.isRecording,
    required this.enabled,
    required this.onPressed,
  });

  final RtlSdrThemeData theme;
  final String label;
  final bool isRecording;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: isRecording ? theme.meterHot : theme.accent,
        foregroundColor: theme.background,
      ),
      onPressed: enabled ? onPressed : null,
      icon: Icon(isRecording ? Icons.stop : Icons.fiber_manual_record),
      label: Text(isRecording ? 'Stop $label' : 'Record $label'),
    );
  }
}
