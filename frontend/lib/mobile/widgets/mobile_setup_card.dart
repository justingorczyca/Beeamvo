import 'package:flutter/material.dart';

class MobileSetupCard extends StatelessWidget {
  const MobileSetupCard({super.key, required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(Icons.key_outlined, size: 34, color: colors.primary),
            const SizedBox(height: 12),
            const Text(
              'Add a cloud API key to start',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your key is stored securely on this device.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}
