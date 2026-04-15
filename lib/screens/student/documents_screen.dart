import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/pdf_service.dart';
import '../../services/fee_service.dart';

class DocumentsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const DocumentsScreen({super.key, required this.userData});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen>
    with SingleTickerProviderStateMixin {
  final User _user = FirebaseAuth.instance.currentUser!;
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  // Track which certificate is currently downloading
  String? _downloadingCertId;

  // ── Animated shimmer for loading ─────────────────────────────
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _shimmerAnimation =
        Tween<double>(begin: 0.3, end: 1.0).animate(_shimmerController);
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  // ── Download the no-due certificate ──────────────────────────
  Future<void> _downloadCertificate(
      Map<String, dynamic> certData, String semester) async {
    final certDocId = '${_user.uid}_$semester';
    setState(() => _downloadingCertId = certDocId);

    try {
      // Fetch what fees were paid for that semester so the PDF is accurate
      final String dept = widget.userData['dept'] ?? 'CSE';
      final String quota = widget.userData['quotaCategory'] ?? 'Management';
      final String batch = widget.userData['batch'] ?? '';
      final String studentType =
          widget.userData['studentType'] ?? 'day_scholar';
      final String? busPlace = widget.userData['busPlace'];

      Map<String, double> feeComponents = {};
      var structure =
          await FeeService().getFeeComponents(dept, quota, batch, semester);
      if (structure != null) {
        if (structure['examFee'] != null &&
            (structure['examFee'] as num) > 0) {
          feeComponents['Exam Fee'] =
              (structure['examFee'] as num).toDouble();
        }
        Map<String, dynamic> rawComponents = structure['components'] ?? {};
        for (var entry in rawComponents.entries) {
          String feeType = entry.key;
          var feeValue = entry.value;
          if (feeType.toLowerCase().contains('hostel') &&
              studentType != 'hosteller') continue;
          if (feeType.toLowerCase().contains('bus')) {
            if (studentType != 'bus_user') continue;
            if (feeValue is Map) {
              if (busPlace != null && feeValue.containsKey(busPlace)) {
                feeComponents[feeType] =
                    (feeValue[busPlace] as num).toDouble();
              }
              continue;
            }
          }
          if (feeValue is num) feeComponents[feeType] = feeValue.toDouble();
        }
      }

      // Build paidFees map (only verified items)
      Map<String, double> paidFees = {};
      for (String feeType in feeComponents.keys) {
        String sanitizedType = feeType.replaceAll(' ', '_');
        String paymentId = '${_user.uid}_${semester}_$sanitizedType';
        try {
          var doc = await FirebaseFirestore.instance
              .collection('payments')
              .doc(paymentId)
              .get();
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['status'] == 'verified') {
              paidFees[feeType] = feeComponents[feeType]!;
            }
          }
        } catch (_) {}
      }

      // If paidFees is empty just use all fee components as a fallback
      if (paidFees.isEmpty) {
        paidFees = Map.from(feeComponents);
      }

      await PdfService().generateAndDownloadCertificate(
        certData['studentName'] ?? widget.userData['name'] ?? 'Student',
        certData['regNo'] ?? widget.userData['regNo'] ?? '',
        certData['dept'] ?? widget.userData['dept'] ?? 'CSE',
        certData['batch'] ?? widget.userData['batch'] ?? '',
        semester,
        paidFees,
        certId: certData['certId'] as String?,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download certificate: $e'),
            backgroundColor: customRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingCertId = null);
    }
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: customRed),
        title: Text(
          'My Documents',
          style: TextStyle(
            color: customRed,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero Banner ──────────────────────────────────────
          _buildHeroBanner(),

          // ── Section Title ────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.article_rounded, color: customRed, size: 20),
                const SizedBox(width: 8),
                Text(
                  'No-Due Certificates',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),

          // ── Certificate List ─────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('no_due_certificates')
                  .where('uid', isEqualTo: _user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingShimmer();
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return _buildEmptyState();
                }

                // Sort by semester number descending
                docs.sort((a, b) {
                  final sa = int.tryParse(
                          (a.data() as Map)['semester']?.toString() ?? '0') ??
                      0;
                  final sb = int.tryParse(
                          (b.data() as Map)['semester']?.toString() ?? '0') ??
                      0;
                  return sb.compareTo(sa);
                });

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data =
                        docs[index].data() as Map<String, dynamic>;
                    final semester =
                        data['semester']?.toString() ?? 'Unknown';
                    return _buildCertCard(data, semester);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Banner ───────────────────────────────────────────────
  Widget _buildHeroBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [customRed, customRed.withOpacity(0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: customRed.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Official Documents',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Download your No-Due Certificates for each semester at any time.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.folder_special_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }

  // ── Certificate card ──────────────────────────────────────────
  Widget _buildCertCard(Map<String, dynamic> data, String semester) {
    final String status = data['status'] ?? 'unknown';
    final String certDocId = '${_user.uid}_$semester';
    final bool isDownloading = _downloadingCertId == certDocId;

    // ── Status config ─────────────────────────────────────────
    final _StatusConfig cfg = _statusConfig(status);

    // ── Generated date ────────────────────────────────────────
    String dateStr = '—';
    try {
      if (data['generatedAt'] != null) {
        final ts = data['generatedAt'] as Timestamp;
        dateStr = DateFormat('dd MMM yyyy').format(ts.toDate());
      }
    } catch (_) {}

    final int generatedCount = (data['generatedCount'] as int?) ?? 1;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cfg.borderColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cfg.iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(cfg.icon, color: cfg.iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No-Due Certificate',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Semester $semester',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Status badge ──────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cfg.badgeBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    cfg.label,
                    style: TextStyle(
                      color: cfg.labelColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // ── Info row ──────────────────────────────────────
            Row(
              children: [
                _infoChip(Icons.calendar_today_rounded, 'Issued $dateStr'),
                const SizedBox(width: 10),
                _infoChip(Icons.file_copy_rounded,
                    '$generatedCount ${generatedCount == 1 ? 'Download' : 'Downloads'}'),
              ],
            ),

            const SizedBox(height: 16),

            // ── Action button ──────────────────────────────────
            if (status == 'issued')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isDownloading
                      ? null
                      : () => _downloadCertificate(data, semester),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: customRed,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: customRed.withOpacity(0.6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  icon: isDownloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    isDownloading
                        ? 'Preparing PDF...'
                        : 'Download Certificate',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              )
            else if (status == 'reissue_requested')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.orange.withOpacity(0.3), width: 1),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hourglass_top_rounded,
                        color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Reissue pending admin approval',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  cfg.helpText,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ── Loading shimmer ───────────────────────────────────────────
  Widget _buildLoadingShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: 3,
      itemBuilder: (_, __) => AnimatedBuilder(
        animation: _shimmerAnimation,
        builder: (context, child) => Opacity(
          opacity: _shimmerAnimation.value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: customRed.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.folder_open_rounded,
                size: 64, color: customRed.withOpacity(0.4)),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Documents Yet',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Once you clear all fees for a semester,\nyour No-Due Certificate will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status config helper ──────────────────────────────────────
  _StatusConfig _statusConfig(String status) {
    switch (status) {
      case 'issued':
        return _StatusConfig(
          icon: Icons.verified_rounded,
          iconColor: Colors.green,
          iconBg: Colors.green.withOpacity(0.1),
          borderColor: Colors.green,
          label: 'ISSUED',
          labelColor: Colors.green,
          badgeBg: Colors.green.withOpacity(0.1),
          helpText: '',
        );
      case 'reissue_requested':
        return _StatusConfig(
          icon: Icons.pending_rounded,
          iconColor: Colors.orange,
          iconBg: Colors.orange.withOpacity(0.1),
          borderColor: Colors.orange,
          label: 'REISSUE PENDING',
          labelColor: Colors.orange,
          badgeBg: Colors.orange.withOpacity(0.1),
          helpText: 'Waiting for admin to approve reissue request.',
        );
      case 'reissue_approved':
        return _StatusConfig(
          icon: Icons.check_circle_outline_rounded,
          iconColor: Colors.blue,
          iconBg: Colors.blue.withOpacity(0.1),
          borderColor: Colors.blue,
          label: 'REISSUE APPROVED',
          labelColor: Colors.blue,
          badgeBg: Colors.blue.withOpacity(0.1),
          helpText: 'Visit the Semester page to download the reissued certificate.',
        );
      default:
        return _StatusConfig(
          icon: Icons.description_rounded,
          iconColor: Colors.grey,
          iconBg: Colors.grey.withOpacity(0.1),
          borderColor: Colors.grey,
          label: status.toUpperCase(),
          labelColor: Colors.grey,
          badgeBg: Colors.grey.withOpacity(0.1),
          helpText: 'Certificate status: $status',
        );
    }
  }
}

// ── Helper data class ─────────────────────────────────────────────
class _StatusConfig {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color borderColor;
  final String label;
  final Color labelColor;
  final Color badgeBg;
  final String helpText;

  const _StatusConfig({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.borderColor,
    required this.label,
    required this.labelColor,
    required this.badgeBg,
    required this.helpText,
  });
}
