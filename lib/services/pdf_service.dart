import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr/qr.dart';
import 'package:uuid/uuid.dart';

class PdfService {

  /// Builds a vector QR code as a pdf widget (no bitmap encoding needed).
  pw.Widget _buildQrWidget(String data, {double size = 90}) {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);
    final moduleCount = qrImage.moduleCount;
    final moduleSize = size / moduleCount;

    final List<pw.Widget> modules = [];
    for (int y = 0; y < moduleCount; y++) {
      for (int x = 0; x < moduleCount; x++) {
        if (qrImage.isDark(y, x)) {
          modules.add(pw.Positioned(
            left: x * moduleSize,
            top: y * moduleSize,
            child: pw.Container(
              width: moduleSize,
              height: moduleSize,
              color: PdfColors.black,
            ),
          ));
        }
      }
    }

    return pw.SizedBox(
      width: size,
      height: size,
      child: pw.Stack(children: [
        pw.Container(width: size, height: size, color: PdfColors.white),
        ...modules,
      ]),
    );
  }

  /// Builds a circular college seal for A-DACS (formerly APEC).
  pw.Widget _buildSeal({double size = 80}) {
    return pw.Container(
      width: size,
      height: size,
      padding: const pw.EdgeInsets.all(2),
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: PdfColors.indigo900, width: 2),
      ),
      child: pw.Container(
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          border: pw.Border.all(color: PdfColors.indigo900, width: 0.5),
        ),
        child: pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            // Symbolic Emblem (e.g., a simple star/shape representing APEC)
            pw.Icon(
              const pw.IconData(0xe838), // Star icon code (standard for PDF package)
              color: PdfColors.indigo900,
              size: size * 0.3,
            ),
            // Middle Text
            pw.Positioned(
              top: size * 0.15,
              child: pw.Text(
                "ADHIPARASAKTHI",
                style: pw.TextStyle(
                  fontSize: size * 0.08,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo900,
                ),
              ),
            ),
            pw.Positioned(
              bottom: size * 0.15,
              child: pw.Text(
                "A-DACS SEAL",
                style: pw.TextStyle(
                  fontSize: size * 0.08,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo900,
                ),
              ),
            ),
            // Outer ring text is hard with standard PDF widgets without extra math/rotation,
            // so we'll use a clean stacked design that looks official.
            pw.Center(
              child: pw.Container(
                width: size * 0.85,
                height: size * 0.85,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: PdfColors.indigo900, width: 0.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> generateAndDownloadCertificate(
    String studentName,
    String regNo,
    String dept,
    String batch,
    String semester,
    Map<String, double> paidFees, {
    String? certId,
  }) async {
    final id = certId ?? const Uuid().v4();
    final verifyUrl = 'https://a-dacs.web.app/verify?id=$id';

    final pdf = pw.Document();

    // Calculate total
    double totalPaid = paidFees.values.fold(0, (sum, val) => sum + val);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Header(level: 0, child: pw.Text("A-DACS")),
              pw.SizedBox(height: 20),
              pw.Text("DIGITAL NO-DUES CERTIFICATE", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.Text("SEMESTER $semester", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 30),
              pw.Text("This is to certify that", style: const pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 10),
              pw.Text(studentName.toUpperCase(), style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text("Register No: $regNo | Dept: $dept | Batch: $batch", style: const pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 30),
              pw.Text("Has successfully cleared the following dues for Semester $semester:",
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 15),

              // Fee Details Table
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Fee Component", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text("Amount Paid", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Divider(),
                    ...paidFees.entries.map((entry) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(entry.key),
                          pw.Text("Rs. ${entry.value.toStringAsFixed(0)}"),
                        ],
                      ),
                    )),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Total Paid", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                        pw.Text("Rs. ${totalPaid.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // Footer: Date + QR
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Date: ${DateTime.now().toString().split(' ')[0]}"),
                      pw.SizedBox(height: 10),
                      _buildSeal(size: 70), // Replaced VERIFIED container with official seal
                      pw.SizedBox(height: 5),
                      pw.Text("Accounts Officer Sign", style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  // QR Code block
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      _buildQrWidget(verifyUrl, size: 90),
                      pw.SizedBox(height: 4),
                      pw.Text("Scan to Verify", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                      pw.SizedBox(height: 2),
                      pw.Text("Cert ID: ${id.substring(0, 8).toUpperCase()}...", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'No-Dues-Certificate-$regNo-Sem$semester',
    );

    return id; // Return certId so caller can persist it
  }





  // Generate Department Fee Report
  Future<void> generateDeptReport(
    String dept,
    String? batch,
    String statusFilter,
    List<Map<String, dynamic>> students, // List of {name, regNo, batch, totalFee, paidFee, balance}
  ) async {
    final pdf = pw.Document();
    
    // Aggregates
    double totalExpected = 0;
    double totalCollected = 0;
    double totalPending = 0;
    
    for (var s in students) {
      totalExpected += (s['totalFee'] as num).toDouble();
      totalCollected += (s['verifiedPaid'] as num? ?? 0).toDouble();
      totalPending += (s['balance'] as num).toDouble();
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        orientation: pw.PageOrientation.landscape, // Wider for table
        build: (pw.Context context) {
          return [
            pw.Header(level: 0, child: pw.Text("ADHIPARASAKTHI ENGINEERING COLLEGE")),
            pw.Text("DEPARTMENT FEE STATUS REPORT (${dept.toUpperCase()})", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Generated: ${DateTime.now().toString().split('.')[0]}"),
                pw.Text("Batch: ${batch ?? 'All'} | Filter: $statusFilter"),
              ],
            ),
            pw.Divider(),
            pw.SizedBox(height: 10),
            
            // SUMMARY BOX
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(), color: PdfColors.grey100),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(children: [pw.Text("Total Students"), pw.Text("${students.length}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
                  pw.Column(children: [pw.Text("Total Expected"), pw.Text("Rs. ${totalExpected.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
                  pw.Column(children: [pw.Text("Verified Collected"), pw.Text("Rs. ${totalCollected.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green))]),
                  pw.Column(children: [pw.Text("Total Pending"), pw.Text("Rs. ${totalPending.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red))]),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // TABLE
            pw.Table.fromTextArray(
              context: context,
              headers: ['Reg No', 'Name', 'Batch', 'Total Fee', 'Verified', 'Pending', 'Balance', 'Status'],
              data: students.map((s) {
                final total = (s['totalFee'] as num).toDouble();
                final balance = (s['balance'] as num).toDouble();
                final verified = (s['verifiedPaid'] as num? ?? 0).toDouble();
                final pending = (s['pendingPaid'] as num? ?? 0).toDouble();
                
                String statusDict;
                PdfColor statusColor = PdfColors.black;

                if (total == 0) {
                   statusDict = "NO FEE";
                   statusColor = PdfColors.grey;
                } else if (balance <= 0) {
                   statusDict = "PAID";
                   statusColor = PdfColors.green;
                } else if (pending > 0) {
                   statusDict = "VERIFYING";
                   statusColor = PdfColors.orange;
                } else {
                   statusDict = "DUE";
                   statusColor = PdfColors.red;
                }

                return [
                  s['regNo'] ?? '-',
                  s['name'] ?? 'Unknown',
                  s['batch'] ?? '-',
                  total.toStringAsFixed(0),
                  verified.toStringAsFixed(0),
                  pending > 0 ? pending.toStringAsFixed(0) : '-',
                  balance.toStringAsFixed(0),
                  pw.Text(statusDict, style: pw.TextStyle(color: statusColor, fontWeight: pw.FontWeight.bold)),
                ];
              }).toList(),
              border: pw.TableBorder.all(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
              cellAlignment: pw.Alignment.center,
              cellAlignments: {
                1: pw.Alignment.centerLeft, // Name left aligned
              },
            ),
          ]; // End of children
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Fee-Report-${dept.replaceAll(' ', '')}-${DateTime.now().millisecondsSinceEpoch}',
    );
  }
  // Generate Individual Student Statement
  Future<void> generateStudentStatement(
    Map<String, dynamic> studentData,
    String semester,
    double totalFee,
    double totalPaid,
    double balance,
    List<Map<String, dynamic>> paymentHistory,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(child: pw.Header(level: 0, child: pw.Text("ADHIPARASAKTHI ENGINEERING COLLEGE"))),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text("STUDENT FEE STATEMENT", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
              pw.Center(child: pw.Text("Semester $semester", style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700))),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 20),

              // Student Info
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("Name: ${(studentData['name'] ?? 'Unknown').toUpperCase()}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text("Register No: ${studentData['regNo'] ?? '-'}"),
                    pw.Text("Department: ${studentData['dept'] ?? '-'}"),
                    pw.Text("Batch: ${studentData['batch'] ?? '-'}"),
                    pw.Text("Quota: ${studentData['quotaCategory'] ?? '-'}"),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Financial Summary
              pw.Text("Fee Summary", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              pw.Table.fromTextArray(
                context: context,
                headers: ['Description', 'Amount (Rs.)'],
                data: [
                  ['Total Fee Applicable', totalFee.toStringAsFixed(0)],
                  ['Total Paid (Verified)', totalPaid.toStringAsFixed(0)],
                  ['Balance Due', balance.toStringAsFixed(0)],
                ],
                border: pw.TableBorder.all(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
                cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
              ),
              pw.SizedBox(height: 20),

              // Payment History
              pw.Text("Payment History", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              if (paymentHistory.isEmpty)
                pw.Text("No payments recorded for this semester.", style: const pw.TextStyle(color: PdfColors.grey))
              else
                pw.Table.fromTextArray(
                  context: context,
                  headers: ['Date', 'Txn ID', 'Amount (Rs.)', 'Status'],
                  data: paymentHistory.map((p) {
                    final date = p['date'] is Timestamp ? (p['date'] as Timestamp).toDate().toString().split(' ')[0] : (p['date']?.toString() ?? '-');
                    return [
                      date,
                      p['transactionId'] ?? 'N/A',
                      (p['amount'] as num).toDouble().toStringAsFixed(0),
                      (p['status'] ?? 'pending').toString().toUpperCase(),
                    ];
                  }).toList(),
                  border: pw.TableBorder.all(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey700),
                  cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.center, 2: pw.Alignment.centerRight, 3: pw.Alignment.center},
                ),
              
              pw.Spacer(),
              pw.Divider(),
              pw.Text("Generated on: ${DateTime.now().toString().split('.')[0]}", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Statement-${studentData['regNo']}-Sem$semester',
    );
  }
}
