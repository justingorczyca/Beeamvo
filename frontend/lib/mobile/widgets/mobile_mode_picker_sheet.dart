import 'package:flutter/material.dart';

import '../../models/system_prompt.dart';

class MobileModePickerSheet extends StatelessWidget {
  const MobileModePickerSheet({
    super.key,
    required this.prompts,
    required this.selectedPromptId,
    required this.onSelected,
  });

  final List<SystemPrompt> prompts;
  final String selectedPromptId;
  final Future<void> Function(SystemPrompt prompt) onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text('Mode', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final prompt in prompts)
            ListTile(
              title: Text(prompt.name),
              subtitle: Text(
                prompt.instruction,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: prompt.id == selectedPromptId
                  ? const Icon(Icons.check)
                  : null,
              onTap: () async {
                await onSelected(prompt);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}
