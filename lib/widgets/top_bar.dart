import 'dart:ui';
import 'package:flutter/material.dart';

class PremiumTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String userName;
  final VoidCallback onSearchPressed;
  final VoidCallback onSyncPressed;

  const PremiumTopBar({
    super.key,
    required this.title,
    required this.userName,
    required this.onSearchPressed,
    required this.onSyncPressed,
  });

  @override
  Widget build(BuildContext context) {
    String getGreeting() {
      var hour = DateTime.now().hour;
      if (hour < 12) {
        return 'Good morning';
      } else if (hour < 17) {
        return 'Good afternoon';
      } else {
        return 'Good evening';
      }
    }

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          color: Colors.white.withOpacity(0.65),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "${getGreeting()}, $userName",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          onPressed: onSearchPressed,
                          icon: const Icon(Icons.search_rounded, color: Colors.blueAccent),
                          tooltip: "Search & Filter",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          onPressed: onSyncPressed,
                          icon: const Icon(Icons.calendar_month_rounded, color: Colors.blueAccent),
                          tooltip: "Sync with Device Calendar",
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(85.0);
}
