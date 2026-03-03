import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// A public verification screen — no login required.
/// Opened when someone scans the QR on a no-due certificate.
/// Route: /verify?id=<certId>
class CertVerifyScreen extends StatelessWidget {
  final String certId;
  const CertVerifyScreen({super.key, required this.certId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: const Text("Certificate Verification"),
        centerTitle: true,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('no_due_certificates')
            .where('certId', isEqualTo: certId)
            .limit(1)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.indigo));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return _buildResult(
              context: context,
              isValid: false,
              title: "Certificate Not Found",
              subtitle: "This certificate ID does not exist in our records.\nIt may be forged or invalid.",
            );
          }

          final data = docs.first.data() as Map<String, dynamic>;
          final generatedAt = data['generatedAt'] != null
              ? DateFormat('dd MMMM yyyy, hh:mm a').format((data['generatedAt'] as Timestamp).toDate())
              : 'N/A';

          return _buildResult(
            context: context,
            isValid: true,
            title: "✅ Certificate Verified",
            subtitle: "This is an authentic No-Due Certificate issued by A-DACS.",
            data: {
              'Student Name': data['studentName'] ?? '-',
              'Register No': data['regNo'] ?? '-',
              'Department': data['dept'] ?? '-',
              'Batch': data['batch'] ?? '-',
              'Semester': data['semester'] ?? '-',
              'Issued On': generatedAt,
              'Certificate ID': certId,
            },
          );
        },
      ),
    );
  }

  Widget _buildResult({
    required BuildContext context,
    required bool isValid,
    required String title,
    required String subtitle,
    Map<String, String>? data,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status Icon
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isValid ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
              ),
              child: Icon(
                isValid ? Icons.verified_rounded : Icons.cancel_rounded,
                size: 60,
                color: isValid ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.white60), textAlign: TextAlign.center),

            if (data != null) ...[
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: data.entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(e.key, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                        ),
                        const Text(" : ", style: TextStyle(color: Colors.white60)),
                        Expanded(child: Text(e.value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ],

            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "ADHIPARASAKTHI ENGINEERING COLLEGE\nA-DACS Verification System",
                style: TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
