import 'package:flutter/material.dart';

class CompactSnackBar extends StatelessWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;

  factory CompactSnackBar.error({required String message}) =>
      CompactSnackBar._(message: message, backgroundColor: const Color(0xFFE53935), icon: Icons.error_outline);

  factory CompactSnackBar.info({required String message}) =>
      CompactSnackBar._(message: message, backgroundColor: const Color(0xFF2196F3), icon: Icons.info_outline);

  factory CompactSnackBar.success({required String message}) =>
      CompactSnackBar._(message: message, backgroundColor: const Color(0xFF4CAF50), icon: Icons.check_circle_outline);

  factory CompactSnackBar.warning({required String message}) =>
      CompactSnackBar._(message: message, backgroundColor: const Color(0xFFFF9800), icon: Icons.warning_amber_outlined);

  const CompactSnackBar._({required this.message, required this.backgroundColor, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
            ),
          ),
        ],
      ),
    );
  }
}
