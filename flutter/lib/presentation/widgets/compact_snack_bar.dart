import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CompactSnackBar extends StatelessWidget {
  final String message;
  final Color backgroundColor;
  final FaIconData icon;

  factory CompactSnackBar.error({required String message}) =>
      CompactSnackBar._(message: message, backgroundColor: const Color(0xFFE53935), icon: FontAwesomeIcons.circleExclamation);

  factory CompactSnackBar.info({required String message}) =>
      CompactSnackBar._(message: message, backgroundColor: const Color(0xFF2196F3), icon: FontAwesomeIcons.circleInfo);

  factory CompactSnackBar.success({required String message}) =>
      CompactSnackBar._(message: message, backgroundColor: const Color(0xFF4CAF50), icon: FontAwesomeIcons.circleCheck);

  factory CompactSnackBar.warning({required String message}) =>
      CompactSnackBar._(message: message, backgroundColor: const Color(0xFFFF9800), icon: FontAwesomeIcons.triangleExclamation);

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
          FaIcon(icon, color: Colors.white, size: 14),
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
