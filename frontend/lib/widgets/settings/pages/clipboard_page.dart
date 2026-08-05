import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/clipboard_history_entry.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/settings_service.dart';
import '../bee_input.dart';
import '../bee_page_header.dart';
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

  static const double _entryExtent = 44;
  static const double _maxHistoryListHeight = 400;
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
              padding: BeePageHeader.contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BeePageHeader(title: 'Clipboard'),
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
                          inactiveTrackColor: beeYellow(
                            context,
                          ).withValues(alpha: 0.15),
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

                  const SizedBox(height: BeePageHeader.groupGap),

                  // ── PINNED ─────────────────────────────────────
                  // Flat section: real input field + quiet list below.
                  // No hollow "card wrapping empty state" shells.
                  const BeeGroupLabel(label: 'Pinned Prompts'),
                  _buildPinnedComposer(settings),
                  if (pinnedItems.isEmpty)
                    _buildQuietHint(
                      'Pin snippets you reuse often. They stay above history.',
                    )
                  else ...[
                    const SizedBox(height: 8),
                    _buildEntryList(
                      items: pinnedItems,
                      settings: settings,
                      maxHeight: _maxPinnedListHeight,
                    ),
                  ],

                  const SizedBox(height: BeePageHeader.groupGap),

                  // ── HISTORY ────────────────────────────────────
                  Row(
                    children: [
                      const Expanded(child: BeeGroupLabel(label: 'History')),
                      _buildHistoryMeta(items.length),
                      const SizedBox(width: 8),
                      BeeActionChip(
                        label: 'Clear',
                        icon: Icons.delete_sweep_outlined,
                        color: beeTextMuted(context),
                        tooltip: 'Clear non-pinned clipboard history',
                        onTap: () => _confirmClearHistory(settings),
                      ),
                    ],
                  ),
                  _buildHistorySearchField(),
                  if (items.isEmpty)
                    _buildQuietHint(
                      _searchQuery.isNotEmpty
                          ? 'No matches for “${_search.text.trim()}”.'
                          : _historyEnabled
                          ? 'Processed transcriptions will show up here.'
                          : 'Turn on clipboard history above to start collecting entries.',
                    )
                  else ...[
                    const SizedBox(height: 8),
                    _buildEntryList(
                      items: items,
                      settings: settings,
                      maxHeight: _maxHistoryListHeight,
                    ),
                  ],

                  const SizedBox(height: 18),

                  // ── FOOTNOTE ───────────────────────────────────
                  _buildSecretFilteringFootnote(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecretFilteringFootnote() {
    return Text(
      'History automatically skips common API keys, bearer tokens, private keys, and password-style assignments.',
      style: GoogleFonts.inter(
        fontSize: 11,
        color: beeTextMuted(context),
        height: 1.45,
      ),
    );
  }

  Future<void> _pinPrompt(SettingsService settings) async {
    final text = _pinnedCtrl.text.trim();
    if (text.isEmpty) return;
    const maxLen = 2000;
    if (text.length > maxLen) {
      _showSnack('Snippets must be $maxLen characters or fewer');
      return;
    }

    await settings.addPinnedClipboardPrompt(text);
    _pinnedCtrl.clear();
    await _reload();
    _showSnack('Pinned prompt added');
  }

  /// Count chip in the History header — keeps meta out of the search field.
  Widget _buildHistoryMeta(int visibleCount) {
    final total = _history.length;
    final label = _searchQuery.isEmpty ? '$total' : '$visibleCount/$total';
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: beeTextMuted(context),
        letterSpacing: 0.2,
      ),
    );
  }

  /// One-line empty/helper copy — no icon wells, no second panel.
  Widget _buildQuietHint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 2),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: beeTextMuted(context),
          height: 1.4,
        ),
      ),
    );
  }

  // ── Composer / search fields ─────────────────────────────────────

  Widget _buildPinnedComposer(SettingsService settings) {
    final canPin = _pinnedCtrl.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _pinnedCtrl,
            maxLength: 2000,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _pinPrompt(settings),
            style: GoogleFonts.inter(fontSize: 13, color: beeText(context)),
            decoration: beeInputDecoration(
              context,
              hint: 'Type a snippet to pin…',
              prefixIcon: Icons.push_pin_outlined,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _PinActionButton(enabled: canPin, onTap: () => _pinPrompt(settings)),
      ],
    );
  }

  Widget _buildHistorySearchField() {
    return TextField(
      controller: _search,
      onChanged: _onSearchChanged,
      style: GoogleFonts.inter(fontSize: 13, color: beeText(context)),
      decoration: beeInputDecoration(
        context,
        hint: 'Search history…',
        prefixIcon: Icons.search_rounded,
        suffix: _search.text.isEmpty
            ? null
            : BeeInteractive(
                onTap: _clearSearch,
                semanticLabel: 'Clear search',
                tooltip: 'Clear search',
                builder: (context, focused) => Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: focused ? beeText(context) : beeTextMuted(context),
                ),
              ),
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

  /// Populated list only — recessed shell wraps rows (never empty states).
  Widget _buildEntryList({
    required List<ClipboardHistoryEntry> items,
    required SettingsService settings,
    required double maxHeight,
  }) {
    final height = (items.length * _entryExtent)
        .clamp(_entryExtent, maxHeight)
        .toDouble();

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: beeText(context).withValues(alpha: kBeeTintRecess),
        borderRadius: BorderRadius.circular(kBeeRadiusSm),
      ),
      child: SizedBox(
        height: height,
        child: ListView.builder(
          primary: false,
          padding: EdgeInsets.zero,
          itemExtent: _entryExtent,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final entry = items[index];
            final isLast = index == items.length - 1;
            return _EntryCard(
              entry: entry,
              showDivider: !isLast,
              onTap: () {
                unawaited(_copyEntry(entry));
              },
              onTogglePin: () async {
                await settings.setClipboardEntryPinned(
                  entry.id,
                  !entry.isPinned,
                );
                await _reload();
                _showSnack(
                  entry.isPinned ? 'Prompt unpinned' : 'Prompt pinned',
                );
              },
              onDelete: () async {
                await _deleteEntry(settings, entry);
              },
            );
          },
        ),
      ),
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

/// Pin control sized to the adjacent text field — solid when armed,
/// recessed when idle (native form-adjacent action).
class _PinActionButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _PinActionButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = beeYellow(context);
    final onAccent = beeBlack(context);
    return BeeInteractive(
      onTap: enabled ? onTap : null,
      semanticLabel: 'Pin prompt',
      tooltip: enabled ? 'Pin snippet' : 'Type a snippet first',
      builder: (context, focused) {
        final bg = !enabled
            ? beeSurfaceHighest(context)
            : focused
            ? accent.withValues(alpha: 0.88)
            : accent;
        final fg = enabled ? onAccent : beeTextMuted(context);
        final border = !enabled
            ? Border.all(
                color: beeBorder(
                  context,
                ).withValues(alpha: kBeeChromeBorderAlpha),
              )
            : null;
        return AnimatedContainer(
          duration: kBeeTransitionDuration,
          curve: kBeeTransitionCurve,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(kBeeRadiusMd),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.push_pin_rounded, size: 13, color: fg),
              const SizedBox(width: 6),
              Text(
                'Pin',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EntryCard extends StatefulWidget {
  final ClipboardHistoryEntry entry;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  const _EntryCard({
    required this.entry,
    required this.showDivider,
    required this.onTap,
    required this.onTogglePin,
    required this.onDelete,
  });

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _rowHovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    // Settings-row density: single-line primary text, trailing meta +
    // hover-revealed actions. Copy target is the text lane only.
    return MouseRegion(
      onEnter: (_) => setState(() => _rowHovered = true),
      onExit: (_) => setState(() => _rowHovered = false),
      child: AnimatedContainer(
        duration: kBeeTransitionDuration,
        curve: kBeeTransitionCurve,
        color: _rowHovered
            ? beeText(context).withValues(alpha: kBeeTintHover)
            : Colors.transparent,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: BeeInteractive(
                      onTap: widget.onTap,
                      semanticLabel: 'Copy clipboard entry',
                      tooltip: 'Copy to clipboard',
                      builder: (context, focused) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                          child: Row(
                            children: [
                              if (entry.isPinned) ...[
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 12,
                                  color: beeTextSub(context),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  entry.text.replaceAll(RegExp(r'\s+'), ' '),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: beeText(context),
                                    height: 1.25,
                                    letterSpacing: -0.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _ago(entry.updatedAt),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: beeTextMuted(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // Reveal actions on hover; keep pin visible when already pinned.
                  AnimatedOpacity(
                    duration: kBeeTransitionDuration,
                    curve: kBeeTransitionCurve,
                    opacity: _rowHovered || entry.isPinned ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !(_rowHovered || entry.isPinned),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _iconBtn(
                              icon: entry.isPinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              color: entry.isPinned
                                  ? beeText(context)
                                  : beeTextMuted(context),
                              tooltip: entry.isPinned
                                  ? 'Unpin prompt'
                                  : 'Pin prompt',
                              onTap: widget.onTogglePin,
                            ),
                            _iconBtn(
                              icon: Icons.delete_outline_rounded,
                              color: beeTextMuted(context),
                              tooltip: entry.isPinned
                                  ? 'Delete pinned prompt'
                                  : 'Delete clipboard entry',
                              onTap: widget.onDelete,
                              danger: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.showDivider)
              Padding(
                padding: EdgeInsets.only(left: entry.isPinned ? 32 : 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: beeDivider(context).withValues(alpha: 0.55),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return BeeInteractive(
      onTap: onTap,
      semanticLabel: tooltip,
      tooltip: tooltip,
      builder: (context, focused) {
        final fg = danger && focused ? beeError(context) : color;
        return AnimatedContainer(
          duration: kBeeTransitionDuration,
          curve: kBeeTransitionCurve,
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused
                ? beeText(context).withValues(alpha: kBeeTintActive)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kBeeRadiusXs),
          ),
          child: Icon(icon, size: 15, color: fg),
        );
      },
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
