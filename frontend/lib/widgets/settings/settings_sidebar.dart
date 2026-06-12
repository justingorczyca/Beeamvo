import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/settings_provider.dart';
import 'settings_shared.dart';

/// Desktop navigation rail for settings.
class SettingsSidebar extends StatefulWidget {
  const SettingsSidebar({super.key});

  @override
  State<SettingsSidebar> createState() => _SettingsSidebarState();
}

class _SettingsSidebarState extends State<SettingsSidebar> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final provider = SettingsProviderScope.of(context);

    return AnimatedBuilder(
      animation: provider,
      builder: (context, _) {
        return Container(
          width: 216,
          decoration: BoxDecoration(
            // Flat tone matching the window title bar so the sidebar and the
            // title bar read as one continuous chrome layer around the page.
            color: beeSidebar(context),
            border: Border(
              right: BorderSide(color: beeText(context).withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 14),
              const _SidebarBrand(),
              const SizedBox(height: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    children: provider.availableCategories.indexed.map((pair) {
                      final i = pair.$1;
                      final cat = pair.$2;
                      // Add a gap before items that start a new group
                      final prevGroup =
                          i > 0 ? provider.availableCategories[i - 1].group : -1;
                      final addGap = cat.group != prevGroup && i > 0;

                      return Padding(
                        padding: EdgeInsets.only(top: addGap ? 10 : 0),
                        child: _NavItem(
                          category: cat,
                          isSelected: provider.selectedCategory == cat,
                          onTap: () {
                            if (cat == provider.selectedCategory) return;
                            provider.selectCategory(cat);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: FutureBuilder<PackageInfo>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    final version = snapshot.hasData
                        ? 'v${snapshot.data!.version}'
                        : '';
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        version,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: beeText(context).withValues(alpha: 0.42),
                          letterSpacing: 0.2,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(kBeeRadiusXs),
              child: Image.asset(
                'assets/beamvo_logo_transparent.png',
                width: 22,
                height: 22,
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Beeamvo',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                    color: beeText(context),
                    letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final SettingsCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = category.isEnabled;
    final isInteractive = enabled && !isSelected;

    const iconSize = 15.0;
    const fontSize = 12.5;

    return BeeInteractive(
      onTap: isInteractive ? onTap : null,
      semanticLabel: category.displayName,
      selected: isSelected,
      builder: (context, active) {
        // Only non-selected, enabled items respond to hover visually.
        // Selected & disabled states stay pinned to their idle alphas.
        final hoverable = !isSelected && enabled;

        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          tween: Tween<double>(
            begin: active ? 0.0 : 1.0,
            end: active ? 1.0 : 0.0,
          ),
          builder: (context, hoverT, child) {
            // Idle → hovered: text 0.66 → 0.92, icon 0.52 → 0.72.
            // Selected stays at 1.0 — hover never reaches selected
            // alpha, so the selection hierarchy remains readable.
            final textAlpha = hoverable
                ? 0.66 + (0.92 - 0.66) * hoverT
                : (isSelected ? 1.0 : 0.32);
            final iconAlpha = hoverable
                ? 0.52 + (0.72 - 0.52) * hoverT
                : (isSelected ? 1.0 : 0.28);

            return Container(
              height: 32,
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Icon(
                      category.icon,
                      size: iconSize,
                      color: beeText(context).withValues(alpha: iconAlpha),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      category.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: fontSize,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: beeText(context).withValues(alpha: textAlpha),
                        letterSpacing: -0.05,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
