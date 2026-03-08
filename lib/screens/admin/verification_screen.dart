import 'package:flutter/material.dart';
import '../../services/fee_service.dart';

class VerificationScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId; // Payment Document ID
  final String studentId;

  const VerificationScreen({
    super.key, 
    required this.data, 
    required this.docId, 
    required this.studentId
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  bool _isProcessing = false;
  final _reasonCtrl = TextEditingController();

  Future<void> _verifyPayment() async {
    setState(() => _isProcessing = true);
    try {
      await FeeService().verifyPaymentComponent(widget.docId, true);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payment Verified! Payment Cleared.")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectPayment() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reject Payment"),
        content: TextField(
          controller: _reasonCtrl,
          decoration: const InputDecoration(labelText: "Reason for Rejection", hintText: "e.g., Invalid Receipt"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Reject"),
          )
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      await FeeService().verifyPaymentComponent(widget.docId, false, rejectionReason: _reasonCtrl.text);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String receiptUrl = widget.data['proofUrl'] ?? widget.data['receiptUrl'] ?? '';
    final double amount = (widget.data['amount'] as num?)?.toDouble() ?? 0.0;
    final String semester = widget.data['semester'] ?? '?';
    final String studentName = widget.data['studentName'] ?? 'Unknown';
    final String transactionId = widget.data['transactionId'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text("Verify Payment - $studentName"),
        backgroundColor: customRed,
        foregroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // IMAGE VIEW
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: receiptUrl.isNotEmpty && receiptUrl.startsWith('http') 
                  ? InteractiveViewer(
                      child: Image.network(
                        receiptUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Loading receipt image...',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          print('Image load error: $error');
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.broken_image, color: Colors.white, size: 50),
                                const SizedBox(height: 10),
                                const Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  error.toString(),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    )
                  : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                       const Icon(Icons.link_off, color: Colors.white, size: 50),
                       const SizedBox(height: 10),
                       const Text('Invalid or missing image URL', style: TextStyle(color: Colors.white)),
                       const SizedBox(height: 5),
                       Text("URL: $receiptUrl", style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
                    ],
                  ),
            ),
          ),
          
          // DATA VIEW
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Payment Verification",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "₹ $amount",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: customRed,
                      ),
                    ),
                    const SizedBox(height: 15),
                    
                    _detailRow(Icons.person, "Student: $studentName"),
                    _detailRow(
                      Icons.badge,
                      "Reg No: ${widget.data['studentRegNo'] ?? widget.data['ocr']?['studentRegNoGroundTruth'] ?? 'N/A'}",
                      color: customRed,
                    ),
                    _detailRow(Icons.category, "Fee Type: ${widget.data['feeType'] ?? 'Fee'}"),
                    _detailRow(Icons.school, "Semester: $semester"),
                    _detailRow(Icons.receipt, "TXN ID: $transactionId"),
                    _detailRow(
                      Icons.payment,
                      "Mode: ${(widget.data['paymentMode'] ?? 'upi').toString().toUpperCase()}",
                    ),
                    if (widget.data['walletUsedAmount'] != null &&
                        (widget.data['walletUsedAmount'] as num) > 0)
                      _detailRow(
                        Icons.account_balance_wallet,
                        "Wallet Applied: ₹${(widget.data['walletUsedAmount'] as num).toStringAsFixed(0)}",
                        color: Colors.green,
                      ),
                    if (widget.data['isInstallment'] == true)
                      _detailRow(
                        Icons.splitscreen,
                        "Plan: Installment ${widget.data['installmentNumber']} of 2",
                        color: Colors.blue,
                      ),

                    // ── OCR Audit Trail ──────────────────────────
                    if (widget.data['ocr'] != null) ...[
                      const Divider(height: 20),
                      _buildOcrAudit(),
                    ],
                    
                    const Divider(height: 30),
                    
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isProcessing ? null : _rejectPayment,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text("REJECT"),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isProcessing ? null : _verifyPayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isProcessing 
                              ? const CircularProgressIndicator(color: Colors.white) 
                              : const Text("APPROVE"),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 15, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOcrAudit() {
    final ocr = widget.data['ocr'] as Map<String, dynamic>;
    final original = ocr['original'] as Map<String, dynamic>? ?? {};
    final submitted = ocr['submitted'] as Map<String, dynamic>? ?? {};
    final edited = ocr['edited'] as Map<String, dynamic>? ?? {};
    final ocrVerified = ocr['verified'] == true;
    final ocrRan = ocr['ran'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              ocrVerified ? Icons.verified : Icons.edit_note,
              size: 18,
              color: ocrVerified ? Colors.green[700] : customRed,
            ),
            const SizedBox(width: 6),
            Text(
              ocrRan
                  ? (ocrVerified
                      ? "OCR Verified — student did not edit any fields"
                      : "OCR fields were edited by student")
                  : "OCR was not run",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: ocrVerified ? Colors.green[700] : customRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (ocrRan) ..._buildOcrRows(original, submitted, edited),
      ],
    );
  }

  List<Widget> _buildOcrRows(Map<String, dynamic> original, Map<String, dynamic> submitted, Map<String, dynamic> edited) {
    final rows = <Widget>[];
    void addRow(String field, String label) {
      final orig = original[field]?.toString();
      final sub = submitted[field]?.toString();
      final wasEdited = edited[field] == true;
      if (orig == null && sub == null) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (orig != null)
                      Text(
                        "OCR: $orig",
                        style: TextStyle(
                          fontSize: 12,
                          color: wasEdited ? customRed : Colors.green[700],
                        ),
                      ),
                    if (wasEdited && sub != null)
                      Text(
                        "Submitted: $sub",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),
              if (wasEdited)
                Icon(Icons.edit, size: 14, color: customRed),
            ],
          ),
        ),
      );
    }

    addRow('transactionId', 'TXN / DD No');
    addRow('amount', 'Amount');
    addRow('date', 'Date');
    addRow('regNo', 'Reg No');
    return rows;
  }
}