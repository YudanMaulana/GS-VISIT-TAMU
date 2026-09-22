import 'package:flutter/material.dart';

import '../models.dart';

/// The coloured status pill, mirroring the Android `QualityStatusBanner`
/// (Indonesian copy + colour come straight from the sidecar / Python).
class StatusBanner extends StatelessWidget {
  final DetectionState state;
  const StatusBanner({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final good = state.good;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: state.color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(good ? Icons.check_circle : Icons.info_outline,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              state.message.isEmpty ? '...' : state.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
