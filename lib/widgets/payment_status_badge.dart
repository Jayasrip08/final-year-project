import 'package:flutter/material.dart';

/// Reusable widget to display payment status with color coding
class PaymentStatusBadge extends StatelessWidget {
  final String status;
  final bool isLarge;

  const PaymentStatusBadge({
    super.key,
    required this.status,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor = Colors.white;
    IconData icon;
    String displayText;

    switch (status.toLowerCase()) {
      case 'pending':
        backgroundColor = Colors.orange;
        icon = Icons.pending;
        displayText = 'PENDING';
        break;
      case 'under_review':
      case 'under review':
        backgroundColor = Colors.blue;
        icon = Icons.hourglass_empty;
        displayText = 'UNDER REVIEW';
        break;
      case 'verified':
        backgroundColor = Colors.green;
        icon = Icons.check_circle;
        displayText = 'VERIFIED';
        break;
      case 'rejected':
        backgroundColor = Colors.red;
        icon = Icons.cancel;
        displayText = 'REJECTED';
        break;
      default:
        backgroundColor = Colors.grey;
        icon = Icons.help;
        displayText = status.toUpperCase();
    }

    if (isLarge) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: textColor, size: 24),
            const SizedBox(width: 8),
            Text(
              displayText,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Chip(
      avatar: Icon(icon, color: textColor, size: 18),
      label: Text(
        displayText,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      backgroundColor: backgroundColor,
      padding: EdgeInsets.zero,
    );
  }
}

/// Widget to show status explanation
class PaymentStatusExplanation extends StatelessWidget {
  final String status;

  const PaymentStatusExplanation({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    String explanation;
    IconData icon;
    Color color;

    switch (status.toLowerCase()) {
      case 'pending':
        explanation = 'Your payment receipt has been submitted and is waiting for admin review.';
        icon = Icons.info_outline;
        color = Colors.orange;
        break;
      case 'under_review':
      case 'under review':
        explanation = 'Admin is currently reviewing your payment receipt. You will be notified once verified.';
        icon = Icons.visibility;
        color = Colors.blue;
        break;
      case 'verified':
        explanation = 'Your payment has been verified successfully! You can now download your No-Dues certificate.';
        icon = Icons.check_circle_outline;
        color = Colors.green;
        break;
      case 'rejected':
        explanation = 'Your payment was rejected. Please check the reason and resubmit with correct details.';
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      default:
        explanation = 'Status: $status';
        icon = Icons.help_outline;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              explanation,
              style: TextStyle(
                color: color.withOpacity(0.9),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
