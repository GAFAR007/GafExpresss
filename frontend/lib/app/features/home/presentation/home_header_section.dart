/// lib/app/features/home/presentation/home_header_section.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Top header for the Home screen (location + notification).
///
/// WHY:
/// - Mirrors the reference layout and provides quick context.
/// - Keeps HomeScreen clean by extracting header markup.
///
/// HOW:
/// - Shows a location pill on the left and a bell button on the right.
/// - Parent provides tap callbacks for logging/navigation.
/// ------------------------------------------------------------

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';

class HomeHeaderSection extends StatelessWidget {
  final String locationLabel;
  final VoidCallback onNotificationTap;
  final int notificationCount;

  const HomeHeaderSection({
    super.key,
    required this.locationLabel,
    required this.onNotificationTap,
    required this.notificationCount,
  });

  @override
  Widget build(BuildContext context) {
    AppDebug.log("HOME_HEADER", "build()");

    return Row(
      children: [
        // WHY: Location pill adds quick context for the user.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                locationLabel,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white),
            ],
          ),
        ),
        const Spacer(),
        // WHY: Notification entry point is a common home affordance.
        IconButton(
          onPressed: () {
            AppDebug.log("HOME_HEADER", "Notification tapped");
            onNotificationTap();
          },
          icon: Stack(
            children: [
              const Icon(Icons.notifications, color: Colors.white),
              if (notificationCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    // WHY: Count signals unseen cart items globally.
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      notificationCount > 99 ? "99+" : "$notificationCount",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          tooltip: "Notifications",
        ),
      ],
    );
  }
}
