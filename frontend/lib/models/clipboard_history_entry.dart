class ClipboardHistoryEntry {
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;

  const ClipboardHistoryEntry({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    required this.isPinned,
  });

  ClipboardHistoryEntry copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
  }) {
    return ClipboardHistoryEntry(
      id: id ?? this.id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPinned': isPinned,
    };
  }

  factory ClipboardHistoryEntry.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();

    return ClipboardHistoryEntry(
      id: (map['id'] as String?) ?? 'clip_${now.microsecondsSinceEpoch}',
      text: (map['text'] as String?) ?? '',
      createdAt: DateTime.tryParse((map['createdAt'] as String?) ?? '') ?? now,
      updatedAt: DateTime.tryParse((map['updatedAt'] as String?) ?? '') ?? now,
      isPinned: (map['isPinned'] as bool?) ?? false,
    );
  }
}
