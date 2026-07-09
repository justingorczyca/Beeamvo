import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../models/hotkey_config.dart';
import 'settings/settings_shared.dart';

/// Widget for recording and displaying a global hotkey configuration.
///
/// Features:
/// - Displays current hotkey in a styled container
/// - Recording mode for capturing new key combinations
/// - Validation (requires at least one modifier)
/// - Reset to default button
class HotkeyRecorderWidget extends StatefulWidget {
  final HotkeyConfig currentHotkey;
  final ValueChanged<HotkeyConfig> onHotkeyChanged;
  final VoidCallback? onReset;

  const HotkeyRecorderWidget({
    super.key,
    required this.currentHotkey,
    required this.onHotkeyChanged,
    this.onReset,
  });

  @override
  State<HotkeyRecorderWidget> createState() => _HotkeyRecorderWidgetState();
}

class _HotkeyRecorderWidgetState extends State<HotkeyRecorderWidget>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  String? _errorMessage;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _errorMessage = null;
    });
    _pulseController.repeat(reverse: true);
    _focusNode.requestFocus();
  }

  void _stopRecording() {
    setState(() => _isRecording = false);
    _pulseController.stop();
    _pulseController.reset();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (!_isRecording) return;
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;

    // Escape is an explicit cancel action and must work without a modifier.
    if (key == LogicalKeyboardKey.escape) {
      _stopRecording();
      return;
    }

    // Ignore pure modifier key presses
    if (_isModifierKey(key)) return;

    // Collect current modifiers
    final modifiers = <HotKeyModifier>{};
    if (HardwareKeyboard.instance.isControlPressed) {
      modifiers.add(HotKeyModifier.control);
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      modifiers.add(HotKeyModifier.alt);
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      modifiers.add(HotKeyModifier.shift);
    }
    if (HardwareKeyboard.instance.isMetaPressed) {
      modifiers.add(HotKeyModifier.meta);
    }

    // Validate: require at least one modifier
    if (modifiers.isEmpty) {
      setState(() {
        _errorMessage =
            'Please include at least one modifier (Ctrl, Alt, Shift, or Win)';
      });
      return;
    }

    // Valid hotkey captured!
    final newConfig = HotkeyConfig(key: key, modifiers: modifiers);
    _stopRecording();
    widget.onHotkeyChanged(newConfig);
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  void _handleReset() {
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hotkey display/input area
        KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: GestureDetector(
            onTap: _isRecording ? _stopRecording : _startRecording,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: beePanelDecoration(
                    color: _isRecording
                        ? beeYellow(context).withValues(alpha: 0.08)
                        : beeSurfaceRaised(context),
                    radius: kBeeRadiusMd,
                    borderColor: _isRecording
                        ? beeYellow(context)
                        : beeBorder(context),
                    borderOpacity: _isRecording ? _pulseAnimation.value : 0.9,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isRecording
                            ? Icons.keyboard
                            : Icons.keyboard_command_key_rounded,
                        color: _isRecording
                            ? beeYellow(context)
                            : beeTextSub(context),
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isRecording
                                  ? 'Press your hotkey...'
                                  : widget.currentHotkey.displayString,
                              style: GoogleFonts.spaceGrotesk(
                                color: _isRecording
                                    ? beeYellow(context)
                                    : beeText(context),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _isRecording
                                  ? 'Press Esc to cancel'
                                  : 'Modifiers are required for global shortcuts',
                              style: GoogleFonts.inter(
                                color: beeTextMuted(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      BeeActionChip(
                        label: _isRecording ? 'Listening' : 'Change',
                        color: _isRecording
                            ? beeYellow(context)
                            : beeTextMuted(context),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),

        // Error message
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: beePanelDecoration(
              color: beeError(context).withValues(alpha: 0.08),
              radius: kBeeRadiusSm,
              borderColor: beeError(context),
              borderOpacity: 0.28,
            ),
            child: Row(
              children: [
                Icon(Icons.warning_rounded, color: beeError(context), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.inter(
                      color: beeError(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Reset button
        OutlinedButton.icon(
          onPressed: widget.currentHotkey == HotkeyConfig.defaultHotkey
              ? null
              : _handleReset,
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('Reset to Default'),
          style:
              OutlinedButton.styleFrom(
                foregroundColor: beeTextSub(context),
                side: BorderSide(color: beeBorder(context)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kBeeRadiusMd),
                ),
              ).copyWith(
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              ),
        ),

        const SizedBox(height: 12),

        // Help text
        Text(
          'Default: ${HotkeyConfig.defaultHotkey.displayString}',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: beeTextMuted(context), fontSize: 12),
        ),
      ],
    );
  }
}
