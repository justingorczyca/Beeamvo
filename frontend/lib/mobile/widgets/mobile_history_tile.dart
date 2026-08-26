import 'package:flutter/material.dart';

import '../../models/clipboard_history_entry.dart';

class MobileHistoryTile extends StatelessWidget {
  const MobileHistoryTile({
    super.key,
    required this.entry,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
  });

  final ClipboardHistoryEntry entry;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      onTap: onCopy,
      title: Text(entry.text, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Text('${entry.createdAt.toLocal()}'.split('.').first),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'pin') onPin();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'pin',
            child: Text(entry.isPinned ? 'Unpin' : 'Pin'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    ),
  );
}
