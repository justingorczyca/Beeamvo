import 'package:flutter/material.dart';

import '../mobile_transcription_controller.dart';

class MobileResultCard extends StatelessWidget {
  const MobileResultCard({
    super.key,
    required this.state,
    required this.text,
    required this.error,
    required this.canRetry,
    required this.errorAction,
    required this.onCopy,
    required this.onClear,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final MobileTranscriptionState state;
  final String? text;
  final String? error;
  final bool canRetry;
  final MobileErrorAction errorAction;
  final VoidCallback? onCopy;
  final VoidCallback onClear;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (text == null && error == null) return const SizedBox(height: 100);
    final theme = Theme.of(context);
    final isError = state == MobileTranscriptionState.error;
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: isError ? colors.error : colors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isError ? error! : text!,
              maxLines: 7,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: isError
                  ? [
                      if (errorAction == MobileErrorAction.openSettings)
                        TextButton(
                          onPressed: onOpenSettings,
                          child: const Text('Open settings'),
                        )
                      else if (canRetry)
                        TextButton(
                          onPressed: onRetry,
                          child: const Text('Retry'),
                        ),
                    ]
                  : [
                      TextButton(onPressed: onCopy, child: const Text('Copy')),
                      TextButton(
                        onPressed: onClear,
                        child: const Text('Clear'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}
