import 'package:flutter/material.dart';

enum NotifType { success, error, warning, info }

class AppNotification {
  static void show(
    BuildContext context, {
    required String message,
    NotifType type = NotifType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final (Color bg, IconData icon) = switch (type) {
      NotifType.success => (const Color(0xFF43A047), Icons.check_circle),
      NotifType.error   => (const Color(0xFFE53935), Icons.error),
      NotifType.warning => (const Color(0xFFFB8C00), Icons.warning_amber_rounded),
      NotifType.info    => (const Color(0xFF1E3A5F), Icons.info_outline),
    };

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: duration,
        ),
      );
  }
}
