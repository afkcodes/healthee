/// The account's straps. Tap one.
///
/// One `.card.flush` with hairline-divided `.list-row`s, never a card per
/// device — a list of two devices rendered as two cards is a card inside a card,
/// which the design forbids, and `FlushCard` draws the rule between rows rather
/// than asking each row to draw its own.
///
/// ## A row that has no name says so
///
/// The Zepp payload is not guaranteed to carry a display name, and this work
/// package had no real account to capture one from (`zepp_device.dart`). A row
/// without one shows the MAC as its title and "Zepp did not name this one"
/// underneath. That is worse-looking than printing "Amazfit Helio Strap" at
/// every row, and it is the only honest option: a label is a claim about which
/// device this is, and the wrong one gets the wrong strap paired.
library;

import 'package:flutter/material.dart';
import 'package:healthee/data/pairing/zepp_device.dart';
import 'package:healthee/shared/v02/list_row.dart';
import 'package:healthee/shared/v02/notices.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// Renders the device list from a Zepp account.
class DevicePicker extends StatelessWidget {
  /// [devices] is never empty — an empty account is a named failure instead.
  const DevicePicker({
    required this.devices,
    required this.onSelected,
    super.key,
  });

  /// The straps to choose from.
  final List<ZeppDevice> devices;

  /// Called with the tapped device.
  final ValueChanged<ZeppDevice> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SectionHead(title: 'Your Zepp devices'),
        const SmallProse(
          'Tap the strap you wear. Nothing is stored until you confirm it on '
          'the next screen.',
        ),
        const SizedBox(height: SectionGap.height),
        FlushCard(
          children: <Widget>[
            for (final ZeppDevice device in devices)
              ListRow(
                icon: SolarIconsOutline.watchRound,
                title: device.label,
                subtitle: device.hasVendorName
                    ? device.strap.mac
                    : 'Zepp did not name this one',
                onTap: () => onSelected(device),
                trailing: device.isActive
                    ? const HBadge('In use', kind: BadgeKind.accent)
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
