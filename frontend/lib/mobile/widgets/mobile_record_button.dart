import 'package:flutter/material.dart';

import '../mobile_transcription_controller.dart';

class MobileRecordButton extends StatelessWidget {
  const MobileRecordButton({
    super.key,
    required this.state,
    required this.duration,
    required this.amplitude,
    required this.onPressed,
    this.onCancel,
  });

  final MobileTranscriptionState state;
  final Duration duration;
  final double amplitude;
  final VoidCallback onPressed;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final recording = state == MobileTranscriptionState.recording;
    final processing = state == MobileTranscriptionState.processing;
    final success = state == MobileTranscriptionState.success;
    final icon = processing
        ? SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colors.primary,
            ),
          )
        : Icon(
            success
                ? Icons.check
                : recording
                ? Icons.stop
                : Icons.mic_none,
            size: 34,
          );
    return Column(
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (recording)
                SizedBox(
                  width: 116 + amplitude * 12,
                  height: 116 + amplitude * 12,
                  child: CircularProgressIndicator(
                    value: (0.15 + amplitude * 0.85).clamp(0.0, 1.0).toDouble(),
                    strokeWidth: 3,
                    color: colors.primary,
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: SizedBox(
                  key: ValueKey(state),
                  width: 96,
                  height: 96,
                  child: OutlinedButton(
                    onPressed: processing ? null : onPressed,
                    style: OutlinedButton.styleFrom(
                      shape: const CircleBorder(),
                      side: BorderSide(
                        color: recording ? colors.primary : colors.outline,
                        width: 2,
                      ),
                      backgroundColor: recording
                          ? colors.primary
                          : colors.surface,
                      foregroundColor: recording
                          ? colors.onPrimary
                          : colors.onSurface,
                    ),
                    child: icon,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (recording)
          Text(_formatDuration(duration))
        else if (processing)
          const Text('Transcribing…')
        else if (success)
          const Text('Copied to clipboard'),
        if (recording && onCancel != null)
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }

  String _formatDuration(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
      '${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
