import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';

class SMSService {
  static final SMSService _instance = SMSService._internal();
  factory SMSService() => _instance;
  SMSService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Manually trigger an overdue SMS reminder for a specific student
  Future<bool> sendManualOverdueSMS({
    required String studentId,
    required double amount,
    required DateTime deadline,
    bool silent = false,
  }) async {
    try {
      final String deadlineText = DateFormat('dd/MM/yyyy').format(deadline);
      
      final result = await _functions.httpsCallable('triggerManualOverdueSMS').call({
        'studentId': studentId,
        'amount': amount.toStringAsFixed(0),
        'deadline': deadlineText,
      });

      if (result.data['success'] == true) {
        if (!silent) NotificationService.showSuccess("Overdue SMS sent to parent.");
        return true;
      } else {
        if (!silent) NotificationService.showError(result.data['message'] ?? "Failed to send SMS.");
        return false;
      }
    } on FirebaseFunctionsException catch (e) {
      if (!silent) NotificationService.showError("SMS Error: ${e.message}");
      return false;
    } catch (e) {
      if (!silent) NotificationService.showError("SMS Error: $e");
      return false;
    }
  }
}
