import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/clipboard_history_entry.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/settings_service.dart';
import '../settings_shared.dart';

class ClipboardPage extends StatefulWidget {
  const ClipboardPage({super.key});

  @override
  State<ClipboardPage> createState() => _ClipboardPageState();
}

class _ClipboardPageState extends State<ClipboardPage> {
  bool _historyEnabled = false;
  bool _watcherEnabled = false;
  bool _autoPasteEnabled = true;
  int _maxItems = 40;
  List<ClipboardHistoryEntry> _history = [];
  final TextEditingController _search = TextEditingController();
  final TextEditingController _pinnedCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  bool _settingsLoaded = false;

  static const double _entryExtent = 58;
  static const double _maxHistoryListHeight = 420;
  static const double _maxPinnedListHeight = 220;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_settingsLoaded) {
      _settingsLoaded = true;
      _loadSettings();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _pinnedCtrl.dispose();
    super.dispose();
  }

  void _loadSettings() {
    final s = SettingsProviderScope.of(context).settingsService;
    setState(() {
      _historyEnabled = s.clipboardHistoryEnabled;
      _watcherEnabled = s.clipboardWatcherEnabled;
      _autoPasteEnabled = s.autoPasteEnabled;
      _maxItems = s.clipboardHistoryMaxItems;
      _history = s.clipboardHistory;
    });
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final s = SettingsProviderScope.of(context).settingsService;
    setState(() {
      _history = s.clipboardHistory;
      _maxItems = s.clipboardHistoryMaxItems;
      _historyEnabled = s.clipboardHistoryEnabled;
      _watcherEnabled = s.clipboardWatcherEnabled;
      _autoPasteEnabled = s.autoPasteEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsProviderScope.of(context).settingsService;
    final q = _searchQuery;
    final items = q.isEmpty
        ? _history
        : _history.where((e) => e.text.toLowerCase().contains(q)).toList();
    final pinnedItems = _history.where((e) => e.isPinned).toList();

    return Column(
      children: [
        Expanded(
          child: Container(
            color: beeSurface(context),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── PREFERENCES ────────────────────────────────
                  const BeeGroupLabel(label: 'Preferences'),
                  BeeSettingsRow(
                    icon: Icons.history_rounded,
                    label: 'Enable Clipboard History',
                    description: 'Save processed transcriptions automatically',
                    trailing: BeeToggle(
                      value: _historyEnabled,
                      semanticLabel: 'Enable clipboard history',
                      onChanged: (v) async {
                        await settings.setClipboardHistoryEnabled(v);
                        setState(() => _historyEnabled = v);
                      },
                    ),
                  ),
                  BeeSettingsRow(
                    icon: Icons.visibility_rounded,
                    label: 'Watch System Clipboard',
                    description: 'Capture text copied from other apps',
                    trailing: BeeToggle(
                      value: _watcherEnabled,
                      semanticLabel: 'Watch system clipboard',
                      onChanged: (v) async {
                        await settings.setClipboardWatcherEnabled(v);
                        setState(() => _watcherEnabled = v);
                      },
                    ),
                  ),
                  BeeSettingsRow(
                    icon: Icons.keyboard_command_key_rounded,
                    label: 'Paste Automatically',
                    description: 'Paste after copying a transcription',
                    trailing: BeeToggle(
                      value: _autoPasteEnabled,
                      semanticLabel: 'Paste automatically',
                      onChanged: (v) async {
                        await settings.setAutoPasteEnabled(v);
                        setState(() => _autoPasteEnabled = v);
                      },
                    ),
                  ),
                  BeeSettingsRow(
                    icon: Icons.storage_rounded,
                    label: 'Max History Items',
                    description: '$_maxItems non-pinned items',
                    showDivider: false,
                    trailing: SizedBox(
                      width: 160,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: beeYellow(context),
                          inactiveTrackColor: beeYellow(context).withValues(
                            alpha: 0.15,
                          ),
                          thumbColor: beeYellow(context),
                          overlayColor: Colors.transparent,
                          trackHeight: 2,
                        ),
                        child: Slider(
                          value: _maxItems.toDouble(),
                          min: 10,
                          max: 200,
                          divisions: 190,
                          onChanged: (v) =>
                              setState(() => _maxItems = v.round()),
                          onChangeEnd: (v) async {
                            await settings.setClipboardHistoryMaxItems(
                              v.round(),
                            );
                            await _reload();
                          },
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── PINNED ─────────────────────────────────────
                  const BeeGroupLabel(label: 'Pinned Prompts'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: _buildPinnedField(settings)),
                      const SizedBox(width: 10),
                      BeeActionChip(
                        label: 'Pin',
                        icon: Icons.push_pin_rounded,
                        onTap: () => _pinPrompt(settings),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPinnedPanel(pinnedItems, settings),

                  const SizedBox(height: 28),

                  // ── HISTORY ────────────────────────────────────
                  Row(
                    children: [
                      const Expanded(child: BeeGroupLabel(label: 'History')),
                      BeeActionChip(
                        label: 'Clear',
                        icon: Icons.delete_sweep_outlined,
                        color: beeTextMuted(context),
                        tooltip: 'Clear non-pinned clipboard history',
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        onTap: () => _confirmClearHistory(settings),
                      ),
                    ],
                  ),
                                                  // Unified history panel
                                                  _buildHistoryPanel(items, settings),

                                                  const SizedBox(height: 16),

                                                  // ── FOOTNOTE (moved from Privacy) ──────────────
                                                  _buildSecretFilteringFootnote(),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  /// Plain text footnote — no bordered container.
                                  Widget _buildSecretFilteringFootnote() {
                                    return Text(
                                      'Clipboard history automatically skips common API keys, bearer tokens, private keys, and password-style assignments before saving entries.',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: beeTextMuted(context),
                                        height: 1.5,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    );
                                  }

  Future<void> _pinPrompt(SettingsService settings) async {
    final text = _pinnedCtrl.text.trim();
    if (text.isEmpty) return;

    await settings.addPinnedClipboardPrompt(text);
    _pinnedCtrl.clear();
    await _reload();
    _showSnack('Pinned prompt added');
  }

  Widget _buildPinnedField(SettingsService settings) {
    return TextField(
      controller: _pinnedCtrl,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _pinPrompt(settings),
      style: GoogleFonts.inter(fontSize: 13, color: beeText(context)),
      decoration: InputDecoration(
        hintText: 'Type a snippet to pin...',
        hintStyle: GoogleFonts.inter(fontSize: 13, color: beeTextMuted(context)),
        filled: true,
        fillColor: beeText(context).withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBeeRadiusSm),
          borderSide: BorderSide(color: beeDivider(context).withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBeeRadiusSm),
          borderSide: BorderSide(color: beeDivider(context).withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBeeRadiusSm),
          // Use a subtle ink ring instead of yellow focus.
          borderSide: BorderSide(color: beeText(context).withValues(alpha: 0.30)),
        ),
        isDense: true,
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _search,
      onChanged: _onSearchChanged,
      style: GoogleFonts.inter(fontSize: 13, color: beeText(context)),
      decoration: InputDecoration(
        hintText: 'Search history...',
        hintStyle: GoogleFonts.inter(fontSize: 13, color: beeTextMuted(context)),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 16,
          color: beeTextMuted(context),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 0),
        suffixIcon: _search.text.isEmpty
            ? null
            : Tooltip(
                message: 'Clear search',
                child: IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: beeTextMuted(context),
                  ),
                  splashRadius: 14,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: _clearSearch,
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 0),
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    setState(() {});
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim().toLowerCase());
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _search.clear();
    setState(() => _searchQuery = '');
  }

  Widget _buildPinnedPanel(
    List<ClipboardHistoryEntry> items,
    SettingsService settings,
  ) {
    if (items.isEmpty) {
      return _buildCompactEmpty(
        icon: Icons.push_pin_outlined,
        title: 'No pinned prompts',
        subtitle: 'Pinned snippets stay available above history.',
      );
    }

    return _buildEntryListPanel(
      items: items,
      settings: settings,
      maxHeight: _maxPinnedListHeight,
    );
  }

  Widget _buildHistoryPanel(
    List<ClipboardHistoryEntry> items,
    SettingsService settings,
  ) {
    final total = _history.length;
    // Flat container: no border, no rounded corners, no tint. Just a thin
    // hairline above and below to bound the search/list area, matching the
    // simple row+divider pattern used elsewhere in the settings.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Embedded search field at top
        _buildSearchField(),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
          child: Text(
            _searchQuery.isEmpty
                ? '$total saved ${total == 1 ? 'entry' : 'entries'}'
                : '${items.length} of $total matching',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: beeTextMuted(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Single 1px hairline divider (was gradient).
            Container(height: 1, color: beeDivider(context).withValues(alpha: 0.55)),
        // Entries
        if (items.isEmpty)
          _buildCompactEmpty(
            icon: Icons.history_rounded,
            title: 'No entries',
            subtitle: _historyEnabled
                ? 'Processed text will appear here.'
                : 'Enable clipboard history to collect entries.',
          )
        else
          _buildEntryListPanel(
            items: items,
            settings: settings,
            maxHeight: _maxHistoryListHeight,
          ),
      ],
    );
  }

  Widget _buildCompactEmpty({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 28, color: beeTextMuted(context)),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: beeTextSub(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: 11, color: beeTextMuted(context)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryListPanel({
    required List<ClipboardHistoryEntry> items,
    required SettingsService settings,
    required double maxHeight,
  }) {
    final height = (items.length * _entryExtent + 12)
        .clamp(_entryExtent + 12, maxHeight)
        .toDouble();

    return SizedBox(
      height: height,
      child: ListView.builder(
        primary: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        itemExtent: _entryExtent,
        itemCount: items.length,
        itemBuilder: (context, index) => _entryCard(settings, items[index]),
      ),
    );
  }

  Widget _entryCard(SettingsService settings, ClipboardHistoryEntry entry) {
    return _EntryCard(
      entry: entry,
      onTap: () {
        unawaited(_copyEntry(entry));
      },
      onTogglePin: () async {
        await settings.setClipboardEntryPinned(entry.id, !entry.isPinned);
        await _reload();
        _showSnack(entry.isPinned ? 'Prompt unpinned' : 'Prompt pinned');
      },
      onDelete: () async {
        await _deleteEntry(settings, entry);
      },
    );
  }

  Future<void> _copyEntry(ClipboardHistoryEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.text));
    _showSnack('Copied to clipboard');
  }

  Future<void> _deleteEntry(
    SettingsService settings,
    ClipboardHistoryEntry entry,
  ) async {
    await settings.removeClipboardEntry(entry.id);
    await _reload();
    _showSnack(
      entry.isPinned ? 'Pinned prompt deleted' : 'Clipboard entry deleted',
      actionLabel: 'Undo',
      onAction: () async {
        await settings.addClipboardEntry(entry.text, isPinned: entry.isPinned);
        await _reload();
      },
    );
  }

  Future<void> _confirmClearHistory(SettingsService settings) async {
    final removed = _history.where((entry) => !entry.isPinned).toList();
    if (removed.isEmpty) {
      _showSnack('No non-pinned history to clear');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: beeSurfaceRaised(context),
        shape: beeDialogShape(),
        title: Text(
          'Clear Clipboard History?',
          style: GoogleFonts.spaceGrotesk(
            color: beeText(context),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        content: Text(
          'This removes ${removed.length} non-pinned '
          '${removed.length == 1 ? 'entry' : 'entries'}. Pinned prompts stay.',
          style: GoogleFonts.inter(color: beeTextSub(context), fontSize: 14),
        ),
        actions: [
          TextButton(
            style: beeSecondaryButtonStyle(context),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: beePrimaryButtonStyle(
              context,
              backgroundColor: beeError(context),
              foregroundColor: beeText(context),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await settings.clearClipboardHistory();
    await _reload();
    _showSnack(
      'Clipboard history cleared',
      actionLabel: 'Undo',
      onAction: () async {
        for (final entry in removed.reversed) {
          await settings.addClipboardEntry(entry.text);
        }
        await _reload();
      },
    );
  }

    void _showSnack(
      String message, {
      String? actionLabel,
      Future<void> Function()? onAction,
    }) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: beeSurfaceHighest(context),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBeeRadiusMd),
          ),
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: beeYellow(context),
                  onPressed: () {
                    unawaited(onAction());
                  },
                ),
        ),
      );
    }
  }

class _EntryCard extends StatefulWidget {
  final ClipboardHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  const _EntryCard({
    required this.entry,
    required this.onTap,
    required this.onTogglePin,
    required this.onDelete,
  });

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    // Flat row — no card, just a subtle ink tint for pinned items. Entries
    // are separated by thin hairline dividers instead of card gaps.
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
        color: entry.isPinned
            ? beeText(context).withValues(alpha: 0.04)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: beeDivider(context).withValues(alpha: 0.45)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Copy to clipboard',
              child: Semantics(
                button: true,
                label: 'Copy clipboard entry',
                onTap: widget.onTap,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Focus(
                    child: Shortcuts(
                      shortcuts: const <ShortcutActivator, Intent>{
                        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (_) {
                              widget.onTap();
                              return null;
                            },
                          ),
                        },
                        child: GestureDetector(
                          excludeFromSemantics: true,
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onTap,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                            child: Row(
                              children: [
                                Icon(
                                  entry.isPinned
                                      ? Icons.push_pin
                                      : Icons.history_rounded,
                                  size: 12,
                                  color: entry.isPinned
                                      ? beeTextSub(context)
                                      : beeTextMuted(context),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    entry.text,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: beeText(context),
                                      height: 1.4,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                  Text(
                                    _ago(entry.updatedAt),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: beeTextMuted(context),
                                    ),
                                  ),
                                ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _iconBtn(
                  icon: entry.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: entry.isPinned ? beeYellow(context) : beeTextMuted(context),
                  tooltip: entry.isPinned ? 'Unpin prompt' : 'Pin prompt',
                  onTap: widget.onTogglePin,
                ),
                const SizedBox(width: 2),
                _iconBtn(
                  icon: Icons.delete_outline_rounded,
                  color: beeError(context),
                  tooltip: entry.isPinned
                      ? 'Delete pinned prompt'
                      : 'Delete clipboard entry',
                  onTap: widget.onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: IconButton(
          icon: Icon(icon, size: 14, color: color),
          onPressed: onTap,
          padding: EdgeInsets.zero,
          splashRadius: 14,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
      ),
    );
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
