import 'package:beeamvo/widgets/settings/settings_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the settings-sidebar "stale highlight" bug.
///
/// A `BeeInteractive` whose `onTap` is toggled to `null` (e.g. a nav item
/// becoming the selected category) used to unmount its internal
/// `MouseRegion`, freezing the `_isHovered` flag at `true`. When the item was
/// later deselected, the stale flag left it visually highlighted until the
/// pointer crossed it again. The fix mounts the `MouseRegion` unconditionally
/// and gates `active` by `enabled`, so tracked hover always matches the real
/// pointer position.
///
/// These tests pin that behaviour directly at the `BeeInteractive` level.
void main() {
  testWidgets(
    'disabled item reports active=false even while the pointer is over it',
    (tester) async {
      await tester.pumpWidget(const _HoverToggler(enabled: true));
      await tester.pumpAndSettle();
      expect(find.text('idle'), findsOneWidget,
          reason: 'an enabled, un-hovered item starts idle');

      // Hover the pointer over the item — should go active.
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(find.byKey(_contentKey)));
      await tester.pumpAndSettle();
      expect(find.text('active'), findsOneWidget,
          reason: 'hovering an enabled item should report active');

      // Simulate selection: onTap becomes null (the reed turns passive).
      await tester.pumpWidget(const _HoverToggler(enabled: false));
      await tester.pumpAndSettle();
      expect(find.text('idle'), findsOneWidget,
          reason: 'a disabled/selected item must pin to idle even while '
              'the pointer is still hovering it — this is the `active` '
              'gating contract');

      await gesture.removePointer();
    },
  );

  testWidgets(
    'no stale hover survives disable → pointer-out → re-enable',
    (tester) async {
      await tester.pumpWidget(const _HoverToggler(enabled: true));
      await tester.pumpAndSettle();

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(find.byKey(_contentKey)));
      await tester.pumpAndSettle();
      expect(find.text('active'), findsOneWidget,
          reason: 'hovering an enabled item should report active');

      // Select (disable) while the pointer is still over it.
      await tester.pumpWidget(const _HoverToggler(enabled: false));
      await tester.pumpAndSettle();

      // The user now moves the mouse off this item to pick a different
      // category. With the bug, the MouseRegion was unmounted at "disable",
      // so this pointer-out never cleared the frozen hover flag.
      await gesture.moveTo(const Offset(-100, -100));
      await tester.pumpAndSettle();

      // Deselect (re-enable). The pointer is no longer over the item, so it
      // must read idle immediately — never a stale "highlighted" state.
      await tester.pumpWidget(const _HoverToggler(enabled: true));
      await tester.pumpAndSettle();
      expect(find.text('idle'), findsOneWidget,
          reason: 'after disable → pointer-out → re-enable the item must not '
              'retain a stale "hovered" flag; it should read idle straight '
              'away without needing a hover-off');

      await gesture.removePointer();
    },
  );
}

const _contentKey = ValueKey('content');

/// Pumps a `BeeInteractive` whose `onTap` is present or null depending on
/// [enabled], surfacing the builder's `active` flag as plain text so a test
/// can assert it synchronously. Re-pumping with a different [enabled] keeps
/// the same widget position in the tree, so the underlying State (and its
/// hover/focus caches) persist across the transition — mirroring a sidebar
/// item flipping between interactive and selected.
class _HoverToggler extends StatelessWidget {
  const _HoverToggler({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: BeeInteractive(
            onTap: enabled ? () {} : null,
            builder: (context, active) {
              return SizedBox(
                key: _contentKey,
                width: 160,
                height: 48,
                child: Text(active ? 'active' : 'idle'),
              );
            },
          ),
        ),
      ),
    );
  }
}
