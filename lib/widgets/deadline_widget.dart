import 'package:flutter/material.dart';

/// Widget to display payment deadline with countdown and warnings
class DeadlineWidget extends StatelessWidget {
  final DateTime deadline;
  final bool isPaid;

  const DeadlineWidget({
    super.key,
    required this.deadline,
    this.isPaid = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysRemaining = deadline.difference(now).inDays;
    final isOverdue = daysRemaining < 0;
    final isUrgent = daysRemaining <= 3 && daysRemaining >= 0;
    final isWarning = daysRemaining <= 7 && daysRemaining > 3;

    // Don't show if already paid
    if (isPaid) {
      return const SizedBox.shrink();
    }

    Color backgroundColor;
    Color textColor;
    IconData icon;
    String message;

    if (isOverdue) {
      backgroundColor = Colors.red.shade100;
      textColor = Colors.red.shade900;
      icon = Icons.error;
      message = 'OVERDUE by ${daysRemaining.abs()} day${daysRemaining.abs() == 1 ? '' : 's'}!';
    } else if (isUrgent) {
      backgroundColor = Colors.orange.shade100;
      textColor = Colors.orange.shade900;
      icon = Icons.warning;
      message = 'URGENT: $daysRemaining day${daysRemaining == 1 ? '' : 's'} remaining!';
    } else if (isWarning) {
      backgroundColor = Colors.yellow.shade100;
      textColor = Colors.orange.shade800;
      icon = Icons.info;
      message = '$daysRemaining days remaining';
    } else {
      backgroundColor = Colors.blue.shade50;
      textColor = Colors.blue.shade900;
      icon = Icons.calendar_today;
      message = '$daysRemaining days remaining';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: textColor.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Deadline',
                      style: TextStyle(
                        color: textColor.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.event, color: textColor.withOpacity(0.7), size: 16),
              const SizedBox(width: 8),
              Text(
                _formatDate(deadline),
                style: TextStyle(
                  color: textColor.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (isOverdue || isUrgent) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: textColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOverdue
                          ? 'Please submit payment immediately to avoid penalties'
                          : 'Submit your payment soon to avoid late fees',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// Compact deadline badge for list items
class DeadlineBadge extends StatelessWidget {
  final DateTime deadline;

  const DeadlineBadge({
    super.key,
    required this.deadline,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysRemaining = deadline.difference(now).inDays;
    final isOverdue = daysRemaining < 0;
    final isUrgent = daysRemaining <= 3 && daysRemaining >= 0;

    Color color;
    IconData icon;

    if (isOverdue) {
      color = Colors.red;
      icon = Icons.error;
    } else if (isUrgent) {
      color = Colors.orange;
      icon = Icons.warning;
    } else {
      color = Colors.blue;
      icon = Icons.schedule;
    }

    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(
        isOverdue
            ? 'Overdue'
            : '$daysRemaining day${daysRemaining == 1 ? '' : 's'}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
    );
  }
}
