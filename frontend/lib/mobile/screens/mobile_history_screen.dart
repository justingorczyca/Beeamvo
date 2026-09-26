import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/settings_service.dart';
import '../widgets/mobile_history_tile.dart';

class MobileHistoryScreen extends StatefulWidget {
  const MobileHistoryScreen({super.key, required this.settingsService});

  final SettingsService settingsService;

  @override
  State<MobileHistoryScreen> createState() => _MobileHistoryScreenState();
}

class _MobileHistoryScreenState extends State<MobileHistoryScreen> {
  @override
  void initState() {
    super.initState();
    widget.settingsService.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.settingsService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all history?'),
        content: const Text(
          'This removes pinned and unpinned transcriptions from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.settingsService.clearClipboardHistory(keepPinned: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.settingsService.clipboardHistory;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              onPressed: _confirmClear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('No transcriptions yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return MobileHistoryTile(
                  entry: entry,
                  onCopy: () => _copy(entry.text),
                  onPin: () async {
                    await widget.settingsService.setClipboardEntryPinned(
                      entry.id,
                      !entry.isPinned,
                    );
                  },
                  onDelete: () async {
                    await widget.settingsService.removeClipboardEntry(entry.id);
                  },
                );
              },
            ),
    );
  }
}
