import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/error_handler.dart';
import '../../services/fee_service.dart';

enum PaymentMode { upi, dd }

class PaymentScreen extends StatefulWidget {
  final String feeType;
  final double amount;
  final String semester;

  const PaymentScreen({
    super.key,
    required this.feeType,
    required this.amount,
    required this.semester,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Map<String, dynamic>? _paymentDetails;
  bool _isLoadingDetails = true;

  int _currentStep = 0;
  PaymentMode _paymentMode = PaymentMode.upi;
  XFile? _imageFile;

  // ── Shared ─────────────────────────────────────────────────
  late TextEditingController _amountCtrl;
  final _dateCtrl = TextEditingController(); // UPI & DD

  // ── UPI-specific ────────────────────────────────────────────
  final _txnCtrl = TextEditingController();
  final _regNoCtrl = TextEditingController(); // pre-filled from OCR

  // ── DD-specific ─────────────────────────────────────────────
  final _ddNumberCtrl = TextEditingController();
  final _ddBankCtrl = TextEditingController();

  bool _isUploading = false;
  bool _isScanning = false;

  // OCR originals (what the scanner read — for comparison by admin)
  String? _ocrOriginalTxn;
  String? _ocrOriginalAmount;
  String? _ocrOriginalDate;
  String? _ocrOriginalRegNo;
  bool _ocrRan = false; // whether OCR was ever performed
  
  // ── Installment logic ──────────────────────────────────────
  bool _isInstallmentMode = false;
  int _installmentNumber = 1;
  double _paidInFirst = 0.0;
  bool _checkingExisting = true;

  // ── Wallet logic ───────────────────────────────────────────
  double _walletBalance = 0.0;
  double _walletToUse = 0.0;
  bool _isWalletFetching = true;

  @override
  void initState() {
    super.initState();
    _amountCtrl =
        TextEditingController(text: widget.amount.toStringAsFixed(0));
    _checkExistingInstallments();
    _fetchPaymentDetails();
    _fetchWalletBalance();
  }

  Future<void> _fetchWalletBalance() async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            _walletBalance = (doc.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
            _isWalletFetching = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching wallet balance: $e");
    } finally {
      if (mounted) setState(() => _isWalletFetching = false);
    }
  }

  Future<void> _checkExistingInstallments() async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      String sanitizedType = widget.feeType.replaceAll(" ", "_");
      String paymentId = "${user.uid}_${widget.semester}_$sanitizedType";
      
      var doc = await FirebaseFirestore.instance.collection('payments').doc(paymentId).get();
      if (doc.exists) {
        var data = doc.data()!;
        if (data['status'] == 'verified' || data['status'] == 'under_review') {
          // Installment 1 exists
          setState(() {
            _paidInFirst = (data['amountPaid'] ?? data['amount'] ?? 0).toDouble();
            _isInstallmentMode = true;
            _installmentNumber = 2;
            _amountCtrl.text = (widget.amount - _paidInFirst).toStringAsFixed(0);
          });
        }
      }
    } catch (e) {
      debugPrint("Error checking existing installments: $e");
    } finally {
      if (mounted) setState(() => _checkingExisting = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _dateCtrl.dispose();
    _txnCtrl.dispose();
    _regNoCtrl.dispose();
    _ddNumberCtrl.dispose();
    _ddBankCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPaymentDetails() async {
    try {
      var doc = await FirebaseFirestore.instance
          .collection('payment_methods')
          .doc(widget.feeType)
          .get();
      if (doc.exists) {
        if (mounted) setState(() => _paymentDetails = doc.data());
      } else {
        var d = await FirebaseFirestore.instance
            .collection('payment_methods')
            .doc("All Fees (Default)")
            .get();
        if (d.exists) {
          if (mounted) setState(() => _paymentDetails = d.data());
        }
      }
    } catch (e) {
      debugPrint("Error fetching payment details: $e");
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  // ── UPI REDIRECT ─────────────────────────────────────────────
  Future<void> _launchUPI() async {
    String pa = _paymentDetails?['upiId'] ?? "collegefees@sbi";
    String pn = _paymentDetails?['accountName'] ?? "A-DACS";
    if (pa.isEmpty) pa = "collegefees@sbi";
    if (pn.isEmpty) pn = "A-DACS";
    String upiUrl = "upi://pay?pa=$pa&pn=$pn&cu=INR&tn=${widget.feeType}";
    // Only pre-fill the exact amount if it's a full payment, so installments can be flexible
    if (!_isInstallmentMode) {
      upiUrl += "&am=${_amountCtrl.text.trim()}";
    }

    if (await canLaunchUrl(Uri.parse(upiUrl))) {
      await launchUrl(Uri.parse(upiUrl), mode: LaunchMode.externalApplication);
    } else {
      upiUrl = "upi://pay?pa=$pa&pn=$pn&cu=INR";
      if (await canLaunchUrl(Uri.parse(upiUrl))) {
        await launchUrl(Uri.parse(upiUrl),
            mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("No UPI App found. Please pay manually.")));
        }
      }
    }
  }

  // ── IMAGE PICKER (mobile only) ───────────────────────────────
  Future<void> _pickAndScanImage() async {
    if (kIsWeb) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(Icons.smartphone, color: Colors.orange[700]),
            const SizedBox(width: 10),
            const Text("Mobile Required"),
          ]),
          content: const Text(
            "Receipt scanning (OCR) is not supported on web.\n\n"
            "Please use the mobile app to upload your payment receipt.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK", style: TextStyle(color: Colors.indigo)),
            ),
          ],
        ),
      );
      return;
    }
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (pickedFile != null) {
      setState(() => _imageFile = pickedFile);
      await _performOCR(File(pickedFile.path));
    }
  }

  // ── OCR ──────────────────────────────────────────────────────
  Future<void> _performOCR(File image) async {
    setState(() {
      _isScanning = true;
      _ocrOriginalTxn = null;
      _ocrOriginalAmount = null;
      _ocrOriginalDate = null;
      _ocrOriginalRegNo = null;
      _ocrRan = false;
    });

    try {
      final inputImage = InputImage.fromFile(image);
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);
      final String text = recognizedText.text;
      textRecognizer.close();
      final String lowerText = text.toLowerCase();
      final List<String> lines = text.split('\n');

      // ── Validate receipt / DD ─────────────────────────────────
      if (_paymentMode == PaymentMode.dd) {
        // Stage 1: reject if this looks like a UPI digital receipt
        final upiExclusiveTerms = [
          'upi', 'phonepe', 'google pay', 'gpay', 'paytm', 'bhim', 'cred',
          'transaction id', 'txn id', 'utr', 'ref no', 'debit alert',
          'credited to', 'debited from', 'payment successful',
        ];
        bool looksLikeUpi = upiExclusiveTerms.any((t) => lowerText.contains(t));
        if (looksLikeUpi) {
          setState(() { _imageFile = null; _isScanning = false; });
          if (mounted) {
            ErrorHandler.showError(context,
                "This looks like a UPI/digital payment receipt, not a Demand Draft. "
                "Please upload a photo of the physical DD or its bank-issued copy.");
          }
          return;
        }

        // Stage 2: must contain at least one DD-specific term
        // Also accept college fee payment challans — students who pay in-person
        // at the college receive a challan which is a valid DD/cash proof.
        final ddTerms = [
          'demand draft', 'dd no', 'd.d', 'draft no', 'drawn on',
          'payable at', 'payable', 'favour', 'favor',
          'cheque', 'chq', 'instrument', 'drawee', 'remitter',
          'micr', 'amount in words', 'rupees only', 'being the amount',
          // Additional DD/bank payment instrument terms
          'remittance', 'bank receipt', 'pay order', 'treasury challan',
          'bank draft', 'payment order', 'draft amount',
          // College fee payment challans (valid as DD-mode proof)
          'challan', 'student copy', 'fee collection', 'fee code',
          'fee payment', 'total rs', 'regn. no', 'admission no',
        ];
        bool hasAnyDdTerm = ddTerms.any((t) => lowerText.contains(t));
        // Also count bank name as a DD indicator when combined with a number
        bool hasBankAndNumber = (lowerText.contains('bank') ||
                lowerText.contains('branch') ||
                lowerText.contains('sbi') ||
                lowerText.contains('hdfc') ||
                lowerText.contains('icici') ||
                lowerText.contains('axis')) &&
            RegExp(r'\d{5,}').hasMatch(text);
        if (!hasAnyDdTerm && !hasBankAndNumber) {
          setState(() { _imageFile = null; _isScanning = false; });
          if (mounted) {
            ErrorHandler.showError(context,
                "Invalid DD Image: Could not identify this as a Demand Draft or bank copy. "
                "Please upload a clear photo of your DD or its bank-issued copy.");
          }
          return;
        }
      } else {
        // UPI mode — check if this is a college fee challan.
        // Previously we rejected challans in UPI mode, but some students pay via
        // the college portal/office and receive a challan that is valid UPI proof.
        // Now we ACCEPT challan images in UPI mode with an informational message.
        final challanIndicators = [
          'challan', 'student copy', 'fee collection', 'fee code',
          'course of study', 'college seal', 'admission no',
          'authorised signatory', 'for bank use',
        ];
        bool looksLikeChallan = challanIndicators.any((t) => lowerText.contains(t));
        if (!looksLikeChallan) {
          looksLikeChallan = lowerText.contains('regn') &&
              (lowerText.contains('amount in words') || lowerText.contains('rupees only'));
        }
        // If it looks like a challan, show a helpful informational message but
        // do NOT reject — allow the student to proceed with the upload.
        if (looksLikeChallan && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
              "College challan detected. Fill in payment details manually if needed."),
            backgroundColor: Colors.orange[700],
            duration: const Duration(seconds: 4),
          ));
          // Don't return — let OCR continue to extract what it can
        }

        // UPI/general mode: require at least 1 payment-related keyword.
        // Extended list covers UPI apps, challans, and general fee receipts.
        final List<String> upiKeywords = [
          'payment', 'successful', 'paid', 'pay', 'transaction', 'upi',
          'ref', 'amount', 'date', 'google', 'phonepe', 'paytm', 'bhim', 'cred',
          // Challan / fee receipt keywords
          'challan', 'fee', 'receipt', 'total', 'college', 'tuition',
          'semester', 'admission', 'student',
        ];
        int kCount = upiKeywords.where((k) => lowerText.contains(k)).length;
        if (text.contains('₹') || lowerText.contains('rs.') || lowerText.contains('inr')) {
          kCount += 2; // currency symbol counts as strong evidence
        }
        if (kCount < 1) {
          setState(() { _imageFile = null; _isScanning = false; });
          if (mounted) {
            ErrorHandler.showError(context,
                "Invalid Receipt: Does not look like a payment receipt. "
                "Please upload a clear image of your UPI receipt, challan, or payment proof.");
          }
          return;
        }
      }

      // ── Date extraction (common) ─────────────────────────────
      String? extractedDate;
      final dateRegexes = [
        // slash or dash separated: 25/9/23, 25-9-2023
        RegExp(r'\b(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\b'),
        // DOT separated: 25.9.23 — common in handwritten Indian documents
        RegExp(r'\b(\d{1,2}\.\d{1,2}\.\d{2,4})\b'),
        // Month name: 25 Sep 2023 / 25 SEP 2023
        RegExp(
            r'\b(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4})\b',
            caseSensitive: false),
        // ISO: 2023-09-25
        RegExp(r'\b(\d{4}[\/\-]\d{2}[\/\-]\d{2})\b'),
      ];
      for (var r in dateRegexes) {
        final m = r.firstMatch(text);
        if (m != null) {
          extractedDate = m.group(1);
          break;
        }
      }

      // ── Amount extraction (common) ────────────────────────────
      // Strategy 1: labeled amounts  (₹ 15000 / Amount: 1,500 / Rs. 500 / Total Rs. 12000)
      // Also handles compound labels like "Total Rs." and "Amount Rs." common on challans.
      final labeledAmountRegex = RegExp(
          r'(?:Total\s+Rs\.?|Amount\s+Rs\.?|Rs\.?|INR|\u20b9|Total\s*(?:Amount)?|Amount\s*(?:Paid)?|Paid)'
          r'[:\.\.\-\s]*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false);
      // Strategy 2: comma-formatted unlabeled amounts only (1,500 / 10,000.00)
      // Plain bare integers are excluded to avoid date-fragment false positives
      final unlabeledCommaRegex = RegExp(
          r'(?<![\/\-\d])(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?)(?![\d\/\-])');

      String? bestAmount;
      double maxScore = -1;

      void scoreCandidate(String raw, bool hasLabel) {
        final valStr = raw.replaceAll(",", "");
        final val = double.tryParse(valStr);
        if (val == null || val < 10 || val > 10000000) return;
        // Reject compact-date look-alikes: 6-digit YYYYMM or 8-digit YYYYMMDD
        if (valStr.length == 6 || valStr.length == 8) {
          final maybeYear = int.tryParse(valStr.substring(0, 4));
          if (maybeYear != null && maybeYear >= 2000 && maybeYear <= 2099) return;
        }
        double score = 0;
        if ((val - widget.amount).abs() < 1) score += 100;
        if (hasLabel) score += 20;
        if (score > maxScore) {
          maxScore = score;
          bestAmount = valStr;
        }
      }

      for (var m in labeledAmountRegex.allMatches(text)) {
        scoreCandidate(m.group(1) ?? "", true);
      }
      for (var m in unlabeledCommaRegex.allMatches(text)) {
        scoreCandidate(m.group(1) ?? "", false);
      }
      // Fallback: plain unlabeled integers on lines with a currency keyword
      // (handles "₹ 15000" where the ₹ is on the same line but no comma)
      if (bestAmount == null) {
        final amountLineKeyword = RegExp(
            r'(?:Rs\.?|INR|\u20b9|Total|Amount|Paid|Payment|Challan)',
            caseSensitive: false);
        final plainNumRegex = RegExp(r'\b(\d{2,7})\b');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!amountLineKeyword.hasMatch(line)) continue;
          // Check on the same line first
          for (var m in plainNumRegex.allMatches(line)) {
            scoreCandidate(m.group(1) ?? "", true);
          }
          // Also check the NEXT line — Google Pay / many UPI apps put ₹ on one
          // OCR line and the actual number (e.g. 400) on the very next line.
          if (bestAmount == null && i + 1 < lines.length) {
            final nextLine = lines[i + 1];
            for (var m in plainNumRegex.allMatches(nextLine)) {
              scoreCandidate(m.group(1) ?? "", true);
            }
          }
        }
      }

      // Last-resort: scan every number in the full text and pick the one
      // closest to widget.amount. For small amounts (< ₹500, e.g. ₹400)
      // use exact or near-exact match first, then fall back to ±50% tolerance.
      // This catches cases where the ₹ symbol is not OCR'd at all.
      if (bestAmount == null && widget.amount > 0) {
        final allNumRegex = RegExp(r'\b(\d{2,7})\b');
        // Wider tolerance for small amounts — 50% instead of 30%
        final tolerancePct = widget.amount < 500 ? 0.50 : 0.30;
        double closestDiff = double.infinity;
        String? closestNum;
        // Pass 1: look for an exact match first (handles ₹400 perfectly)
        for (var m in allNumRegex.allMatches(text)) {
          final raw = m.group(1) ?? '';
          final val = double.tryParse(raw);
          if (val == null || val < 10) continue;
          if (val >= 1900 && val <= 2099) continue;
          if ((val - widget.amount).abs() < 1) {
            closestNum = raw;
            break; // exact match wins immediately
          }
        }
        // Pass 2: closest within tolerance
        if (closestNum == null) {
          for (var m in allNumRegex.allMatches(text)) {
            final raw = m.group(1) ?? '';
            final val = double.tryParse(raw);
            if (val == null || val < 10) continue;
            if (val >= 1900 && val <= 2099) continue;
            final diff = (val - widget.amount).abs();
            if (diff < widget.amount * tolerancePct && diff < closestDiff) {
              closestDiff = diff;
              closestNum = raw;
            }
          }
        }
        if (closestNum != null) bestAmount = closestNum;
      }

      if (_paymentMode == PaymentMode.dd) {
        // ── DD number / Cheque number / Instrument number ─────────
        String? ddNumber;

        // Pass 1: strictly labelled extraction
        // Matches: DD No 123456 / Cheque No: A1234 / Instrument No. 567890
        // Also matches "ALPHA CODE NO" and "A/C NO" labels used on physical DDs
        final ddNumLabelRegex = RegExp(
            r'(?:demand\s*draft|dd|d\.d\.?|draft|cheque|chq\.?|instrument|instr\.?|serial|sl\.?|alpha\s*code|a\/c)'
            r'[\s\-]*(?:no\.?|number|#)?[:\s\-#–]*([A-Z0-9]{5,18})(?![0-9])',
            caseSensitive: false);
        for (final m in ddNumLabelRegex.allMatches(text)) {
          final raw = m.group(1)?.trim() ?? '';
          // Must contain at least 5 digits and not be a date fragment
          final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.length >= 5) {
            // Skip if it looks like a year-month (2025XX)
            final maybeYear = int.tryParse(digits.substring(0, 4));
            if (maybeYear != null && maybeYear >= 2000 && maybeYear <= 2099) continue;
            ddNumber = raw;
            break;
          }
        }

        // Pass 2: any 6–15 digit standalone number on a relevant line
        // Skip phone numbers (10 digits, starting 6-9) and dates
        if (ddNumber == null) {
          final bareNumRegex = RegExp(r'\b(\d{6,15})\b');
          final ddLineKeys = [
            'dd', 'draft', 'cheque', 'chq', 'instrument',
            'serial', 'sl no', 'no.', 'no:', 'ref no', 'alpha', 'code'
          ];
          for (final line in lines) {
            final ll = line.toLowerCase();
            if (!ddLineKeys.any((k) => ll.contains(k))) continue;
            for (final m in bareNumRegex.allMatches(line)) {
              final n = m.group(1)!;
              if (n.length == 10 && RegExp(r'^[6-9]').hasMatch(n)) continue;
              final yr = int.tryParse(n.substring(0, 4));
              if (yr != null && yr >= 2000 && yr <= 2099 && n.length <= 8) continue;
              ddNumber = n;
              break;
            }
            if (ddNumber != null) break;
          }
        }

        // Pass 3: MICR strip at bottom — first standalone 6–9 digit group
        // Physical DDs encode the instrument number in the MICR band.
        // Look for the last line(s) which usually contain only digits and spaces.
        if (ddNumber == null) {
          final micrLineRegex = RegExp(r'^[\d\s\.\*\#]+$');
          final micrNumRegex = RegExp(r'\b(\d{6,9})\b');
          for (final line in lines.reversed) {
            if (!micrLineRegex.hasMatch(line.trim())) continue;
            for (final m in micrNumRegex.allMatches(line)) {
              final n = m.group(1)!;
              if (n.length == 10 && RegExp(r'^[6-9]').hasMatch(n)) continue;
              final yr = int.tryParse(n.substring(0, 4));
              if (yr != null && yr >= 2000 && yr <= 2099) continue;
              ddNumber = n;
              break;
            }
            if (ddNumber != null) break;
          }
        }

        // ── Bank / drawee bank ────────────────────────────────────
        // Priority: explicit label lines > specific bank name lines > generic 'bank' lines
        // Skip first 2 lines (usually issuing-bank header / watermark)
        String? bankName;
        final skipLines = lines.take(2).toSet();

        // Helper: trim a raw bank-name line to just the institution name.
        // Drops address text that follows the first comma, hyphen, newline, or
        // bracket (e.g. "Central Bank of India, Colaba Causeway, Mumbai" → "Central Bank of India")
        String _cleanBankName(String raw) {
          var name = raw.trim();
          // Remove common label prefixes like "Drawn On: " / "Payable At - "
          name = name.replaceFirst(
              RegExp(r'^(?:drawn\s*on|drawee|payable\s*at|issuing\s*bank)[:\s\-]*',
                  caseSensitive: false),
              '');
          // Truncate at first classic address delimiter
          final cut = name.indexOf(RegExp(r'[,\(\[/]'));
          if (cut > 4) name = name.substring(0, cut).trim();
          // Also truncate at two-or-more consecutive spaces (table-cell separator)
          // e.g. "CENTRAL BANK OF INDIA  1396202317" → "CENTRAL BANK OF INDIA"
          final spaceCut = name.indexOf(RegExp(r'\s{2,}'));
          if (spaceCut > 4) name = name.substring(0, spaceCut).trim();
          // Also truncate where alphabetic text transitions to a long digit string
          // e.g. "Central Bank 123456789" → "Central Bank"
          final digitCut = name.indexOf(RegExp(r'\s\d{6,}'));
          if (digitCut > 4) name = name.substring(0, digitCut).trim();
          // Hard cap at 50 chars
          if (name.length > 50) name = name.substring(0, 50).trim();
          return name;
        }

        // Priority 1: lines with drawee/drawn on/payable at label
        final labeledBankKeys = ['drawn on', 'drawee', 'payable at', 'issuing bank'];
        for (final line in lines) {
          if (skipLines.contains(line)) continue;
          final ll = line.toLowerCase();
          if (labeledBankKeys.any((k) => ll.contains(k))) {
            bankName = _cleanBankName(line);
            break;
          }
        }

        // Priority 2: line containing a known bank name
        if (bankName == null) {
          final knownBanks = [
            'state bank', 'sbi', 'hdfc bank', 'icici bank', 'axis bank',
            'canara bank', 'union bank', 'pnb', 'punjab national', 'kotak mahindra',
            'idbi bank', 'bank of baroda', 'bob', 'indian bank', 'bank of india',
            'syndicate bank', 'allahabad bank', 'central bank', 'dena bank',
            'vijaya bank', 'yes bank', 'federal bank', 'karnataka bank',
          ];
          // Use the matching known-bank keyword as the extracted name directly
          // when the full line is too long (address embedded).
          final knownBankNames = {
            'state bank': 'State Bank of India',
            'sbi': 'State Bank of India',
            'hdfc bank': 'HDFC Bank',
            'icici bank': 'ICICI Bank',
            'axis bank': 'Axis Bank',
            'canara bank': 'Canara Bank',
            'union bank': 'Union Bank of India',
            'pnb': 'Punjab National Bank',
            'punjab national': 'Punjab National Bank',
            'kotak mahindra': 'Kotak Mahindra Bank',
            'idbi bank': 'IDBI Bank',
            'bank of baroda': 'Bank of Baroda',
            'bob': 'Bank of Baroda',
            'indian bank': 'Indian Bank',
            'bank of india': 'Bank of India',
            'syndicate bank': 'Syndicate Bank',
            'allahabad bank': 'Allahabad Bank',
            'central bank': 'Central Bank of India',
            'dena bank': 'Dena Bank',
            'vijaya bank': 'Vijaya Bank',
            'yes bank': 'Yes Bank',
            'federal bank': 'Federal Bank',
            'karnataka bank': 'Karnataka Bank',
          };
          for (final line in lines) {
            if (skipLines.contains(line)) continue;
            final ll = line.toLowerCase();
            String? matched;
            for (final k in knownBanks) {
              if (ll.contains(k)) { matched = k; break; }
            }
            if (matched != null) {
              final cleaned = _cleanBankName(line);
              // If cleaning left a short/garbled result, fall back to canonical name
              bankName = cleaned.length >= 4 ? cleaned : (knownBankNames[matched] ?? cleaned);
              break;
            }
          }
        }

        // Priority 3: any line with 'bank' (excluding header lines)
        if (bankName == null) {
          for (final line in lines) {
            if (skipLines.contains(line)) continue;
            final ll = line.toLowerCase();
            if (ll.contains('bank') && line.trim().length > 4) {
              bankName = _cleanBankName(line);
              break;
            }
          }
        }

        // ── DD-specific amount: also try lines with Rs./₹ + a number ─
        // Handles: "Rs. 15,000/-"  "₹15000"  "NOT OVER 21878/-"  MICR encoded amount
        if (bestAmount == null) {
          // Pattern A: Rs./₹/INR prefix
          final ddAmtRegex = RegExp(
              r'(?:Rs\.?|₹|INR)[\s]*(\d[\d,\.]*\d)\s*(?:\/\-)?',
              caseSensitive: false);
          for (final m in ddAmtRegex.allMatches(text)) {
            scoreCandidate(m.group(1) ?? '', true);
          }
        }
        // Pattern B: "NOT OVER 21878/-" — common DD overwriting line
        if (bestAmount == null) {
          final notOverRegex = RegExp(
              r'NOT\s*OVER[\s]*(\d[\d,\.]*\d)\s*(?:\/\-)?',
              caseSensitive: false);
          for (final m in notOverRegex.allMatches(text)) {
            scoreCandidate(m.group(1) ?? '', true);
          }
        }
        // Pattern C: MICR strip amount encoding (e.g. "0000021878000" → 21878)
        // MICR amounts are zero-padded: leading zeros = integer part,
        // last 3 digits = paise (usually 000).
        if (bestAmount == null) {
          final micrAmtRegex = RegExp(r'0{3,}(\d{3,8})0{2,3}\b');
          for (final line in lines) {
            final m = micrAmtRegex.firstMatch(line);
            if (m != null) {
              scoreCandidate(m.group(1) ?? '', true);
            }
          }
        }

        // Pre-fill controllers
        if (ddNumber != null) _ddNumberCtrl.text = ddNumber;
        if (bankName != null) _ddBankCtrl.text = bankName;
        if (extractedDate != null) _dateCtrl.text = extractedDate;
        if (bestAmount != null) _amountCtrl.text = bestAmount!;

        _ocrOriginalTxn = ddNumber;
        _ocrOriginalAmount = bestAmount;
        _ocrOriginalDate = extractedDate;
      } else {
        // ── UPI: transaction ID + reg no ──────────────────────────
        String? extractedTxn;

        // Priority 1: gateway-prefixed IDs (Razorpay/Cashfree: order_xxx, pay_xxx, txn_xxx)
        final gatewayRegex = RegExp(
            r'\b(order_|pay_|txn_|razorpay_)[a-zA-Z0-9]{8,30}\b',
            caseSensitive: false);
        for (final line in lines) {
          final m = gatewayRegex.firstMatch(line);
          if (m != null) { extractedTxn = m.group(0); break; }
        }

        // Priority 2: UTR / UPI Ref — 12-digit number on a labelled line
        if (extractedTxn == null) {
          final utrLabelRegex = RegExp(
              r'(?:utr|upi\s*ref(?:erence)?|transaction\s*id|txn\s*id|ref(?:erence)?\s*(?:no\.?|id)?)'  
              r'[:\s#–]*(\d{10,15}|[A-Z0-9]{10,20})',
              caseSensitive: false);
          for (final line in lines) {
            final m = utrLabelRegex.firstMatch(line);
            if (m != null) { extractedTxn = m.group(1); break; }
          }
        }

        // Priority 3: any standalone 12-digit number (UTR format) on a non-mobile/reg line
        if (extractedTxn == null) {
          final upiRefRegex = RegExp(r'\b(\d{12})\b');
          for (final line in lines) {
            final ll = line.toLowerCase();
            if (ll.contains('mobile') || ll.contains('reg') ||
                ll.contains('roll') || ll.contains('student')) continue;
            final m = upiRefRegex.firstMatch(line);
            if (m != null) { extractedTxn = m.group(1); break; }
          }
        }

        // Priority 4: alphanumeric transaction IDs (e.g. PhonePe: Pxxxxxxxxxx)
        if (extractedTxn == null) {
          final alphaNumTxnRegex = RegExp(
              r'\b([A-Z]{1,4}[0-9]{8,16})\b');
          for (final line in lines) {
            final m = alphaNumTxnRegex.firstMatch(line);
            if (m != null) { extractedTxn = m.group(1); break; }
          }
        }

        // ── Reg No ────────────────────────────────────────────────
        String? extractedRegNo;
        final regNoRegex = RegExp(
            r'(?:reg(?:ister)?(?:\s?no\.?|:|\s)|roll\s?(?:no\.?|:|\s))?\s?(\d{9,15})\b',
            caseSensitive: false);
        for (final line in lines) {
          final ll = line.toLowerCase();
          if (ll.contains('reg') || ll.contains('roll') || ll.contains('student')) {
            final m = regNoRegex.firstMatch(line);
            if (m != null) { extractedRegNo = m.group(1); break; }
          }
        }

        // Pre-fill controllers
        if (extractedTxn != null) _txnCtrl.text = extractedTxn;
        if (bestAmount != null) _amountCtrl.text = bestAmount!;
        if (extractedDate != null) _dateCtrl.text = extractedDate;
        if (extractedRegNo != null) _regNoCtrl.text = extractedRegNo;

        _ocrOriginalTxn = extractedTxn;
        _ocrOriginalAmount = bestAmount;
        _ocrOriginalDate = extractedDate;
        _ocrOriginalRegNo = extractedRegNo;
      }

      setState(() {
        _ocrRan = true;
        _isScanning = false;
      });

      if (mounted) {
        final anyFound = _ocrOriginalTxn != null ||
            _ocrOriginalAmount != null ||
            _ocrOriginalDate != null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(anyFound
              ? "OCR Complete — details pre-filled in Verify step."
              : "Valid document but no clear details found. Please fill manually."),
          backgroundColor: anyFound ? Colors.green : Colors.orange,
        ));
      }
    } catch (e) {
      debugPrint("OCR Error: $e");
      setState(() => _isScanning = false);
    }
  }

  // ── SUBMIT ───────────────────────────────────────────────────
  Future<void> _submitPayment() async {
    if (_imageFile == null) {
      ErrorHandler.showError(context, 'Please upload a receipt / DD image');
      return;
    }

    // Validate
    String refId;
    if (_paymentMode == PaymentMode.dd) {
      refId = _ddNumberCtrl.text.trim();
      if (refId.isEmpty) {
        ErrorHandler.showError(context, 'Please enter the DD Number');
        return;
      }
      if (_ddBankCtrl.text.trim().isEmpty) {
        ErrorHandler.showError(context, 'Please enter the Bank Name');
        return;
      }
      if (_dateCtrl.text.trim().isEmpty) {
        ErrorHandler.showError(context, 'Please enter the DD Date');
        return;
      }
    } else {
      refId = _txnCtrl.text.trim();
      if (refId.isEmpty) {
        refId = "IMG-${DateTime.now().millisecondsSinceEpoch}";
      } else {
        final txnError = Validators.validateTransactionId(refId);
        if (txnError != null) {
          ErrorHandler.showError(context, txnError);
          return;
        }
      }
    }

    final amountError = Validators.validateAmount(_amountCtrl.text);
    if (amountError != null) {
      ErrorHandler.showError(context, amountError);
      return;
    }

    // Reg number is mandatory in both UPI and DD modes
    if (_regNoCtrl.text.trim().isEmpty) {
      ErrorHandler.showError(context,
          'Register / Roll Number is required.\nPlease enter it manually if not auto-filled.');
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      final isDuplicate = await ErrorHandler.checkDuplicatePayment(
        studentId: user.uid,
        transactionId: refId,
      );
      if (isDuplicate) {
        if (mounted) {
          ErrorHandler.showWarning(
              context, 'A payment with this Transaction ID already exists');
        }
        setState(() => _isUploading = false);
        return;
      }

      final storageRef = FirebaseStorage.instance
          .ref()
          .child(
              'receipts/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await storageRef.putFile(File(_imageFile!.path));
      final downloadUrl = await storageRef.getDownloadURL();

      // Fetch student data
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};
      final studentRegNo = (userData['regNo'] ?? '') as String;

      // Detect edits: compare final submitted values against OCR originals
      final finalTxn = _paymentMode == PaymentMode.dd
          ? _ddNumberCtrl.text.trim()
          : _txnCtrl.text.trim();
      final finalAmount = _amountCtrl.text.trim();
      final finalDate = _dateCtrl.text.trim();
      final finalRegNo = _regNoCtrl.text.trim();
      final finalBank =
          _paymentMode == PaymentMode.dd ? _ddBankCtrl.text.trim() : null;

      final txnEdited =
          _ocrOriginalTxn != null && finalTxn != _ocrOriginalTxn;
      final amountEdited =
          _ocrOriginalAmount != null && finalAmount != _ocrOriginalAmount;
      final dateEdited =
          _ocrOriginalDate != null && finalDate != _ocrOriginalDate;
      final regNoEdited =
          _ocrOriginalRegNo != null && finalRegNo != _ocrOriginalRegNo;
      final anyEdited =
          txnEdited || amountEdited || dateEdited || regNoEdited;

      // ocrVerified = OCR ran AND no fields were edited
      final ocrVerified = _ocrRan && !anyEdited;

      // The amount the student must physically pay via UPI/DD = total fee minus wallet contribution.
      final double netExpected = widget.amount - _walletToUse;

      // Submit via FeeService
      await FeeService().submitComponentProof(
        uid: user.uid,
        semester: widget.semester,
        feeType: widget.feeType,
        amountExpected: netExpected,   // net cash expected from UPI/DD
        amountPaid: double.parse(finalAmount),
        transactionId: refId,
        proofUrl: downloadUrl,
        ocrVerified: ocrVerified,
        isInstallment: _isInstallmentMode,
        installmentNumber: _installmentNumber,
        walletUsedAmount: _walletToUse,
      );

      // Enrich Firestore document with full audit trail
      String sanitizedType = widget.feeType.replaceAll(" ", "_");
      String suffix = (_isInstallmentMode && _installmentNumber == 2) ? "_inst2" : "";
      String paymentId = "${user.uid}_${widget.semester}_$sanitizedType$suffix";

      final Map<String, dynamic> enrichment = {
        'studentId': user.uid,
        'studentName': userData['name'],
        'studentRegNo': studentRegNo,
        'dept': userData['dept'],
        'quota': userData['quotaCategory'],
        'paymentMode': _paymentMode == PaymentMode.dd ? 'dd' : 'upi',
        'isInstallment': _isInstallmentMode,
        'installmentNumber': _isInstallmentMode ? _installmentNumber : 1,
        'totalInstallments': 2,
        // Full original fee (before wallet) — stored for admin reference & surplus calc
        'fullFeeAmount': widget.amount,
        'walletUsedAmount': _walletToUse,
        // Full OCR audit trail ...
        'ocr': {
          'ran': _ocrRan,
          'verified': ocrVerified,
          'anyFieldEdited': anyEdited,
          'platform': 'mobile',
          'scannedAt': FieldValue.serverTimestamp(),

          // Original values extracted from image
          'original': {
            'transactionId': _ocrOriginalTxn,
            'amount': _ocrOriginalAmount,
            'date': _ocrOriginalDate,
            'regNo': _ocrOriginalRegNo,
          },

          // Final values submitted by student (may differ if edited)
          'submitted': {
            'transactionId': finalTxn,
            'amount': finalAmount,
            'date': finalDate,
            'regNo': finalRegNo,
            if (finalBank != null) 'bankName': finalBank,
          },

          // Per-field edit flags (admin can see exactly what was changed)
          'edited': {
            'transactionId': txnEdited,
            'amount': amountEdited,
            'date': dateEdited,
            'regNo': regNoEdited,
          },

          // Ground-truth student reg no from users collection
          'studentRegNoGroundTruth': studentRegNo,
        },
      };

      if (_paymentMode == PaymentMode.dd) {
        enrichment['ddDetails'] = {
          'ddNumber': finalTxn,
          'bankName': finalBank,
          'ddDate': finalDate,
          'amount': finalAmount,
          'submittedAt': FieldValue.serverTimestamp(),
        };
      }

      await FirebaseFirestore.instance
          .collection('payments')
          .doc(paymentId)
          .update(enrichment);

      if (mounted) {
        ErrorHandler.showSuccess(
            context,
            _paymentMode == PaymentMode.dd
                ? 'DD details submitted! Please also deliver the physical DD '
                    'to the college accounts office. Admin will verify shortly.'
                : 'Receipt submitted successfully! Admin will review it soon.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ErrorHandler.showError(context, "Submission Failed: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pay & Verify")),
      body: _isLoadingDetails
          ? const Center(child: CircularProgressIndicator())
          : Stepper(
              currentStep: _currentStep,
              onStepContinue: () {
                if (_currentStep == 0) {
                  setState(() => _currentStep++);
                } else if (_currentStep == 1) {
                  if (_imageFile == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            "Please upload a receipt / DD photo first.")));
                    return;
                  }
                  setState(() => _currentStep++);
                } else {
                  _submitPayment();
                }
              },
              onStepCancel: () {
                if (_currentStep > 0) setState(() => _currentStep--);
              },
              controlsBuilder: (BuildContext context, ControlsDetails details) {
                String continueLabel = "Continue";
                if (_currentStep == 0) continueLabel = "Pay or Upload Receipt";
                if (_currentStep == 1) continueLabel = "Verify Details";
                if (_currentStep == 2) continueLabel = "Submit Receipt for Verification";

                return Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: details.onStepContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(continueLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      if (_currentStep > 0) ...[
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: details.onStepCancel,
                          child: const Text('Back'),
                        ),
                      ],
                    ],
                  ),
                );
              },
              steps: [
                // ── Step 1: Payment Method ──────────────────────
                Step(
                  title: const Text("Payment Method"),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_checkingExisting)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_installmentNumber == 1) ...[
                        // Option to choose between Full and Installment
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.indigo.withValues(alpha: 0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Payment Plan",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 12),
                              _planOption(
                                title: "Full Payment",
                                subtitle:
                                    "Pay the total amount of ₹${widget.amount.toStringAsFixed(0)}",
                                icon: Icons.account_balance_wallet,
                                selected: !_isInstallmentMode,
                                onTap: () => setState(() {
                                  _isInstallmentMode = false;
                                  _amountCtrl.text =
                                      widget.amount.toStringAsFixed(0);
                                }),
                              ),
                              const SizedBox(height: 10),
                              _planOption(
                                title: "Pay in 2 Installments",
                                subtitle: "Split the payment into two parts.",
                                icon: Icons.splitscreen,
                                selected: _isInstallmentMode,
                                onTap: () => setState(() {
                                  _isInstallmentMode = true;
                                  _amountCtrl.text =
                                      (widget.amount / 2).toStringAsFixed(0);
                                }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ] else ...[
                        // Installment 2 detected
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  color: Colors.orange),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Installment 2 of 2",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                        "You already paid ₹${_paidInFirst.toStringAsFixed(0)} in the first installment.",
                                        style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                      ],

                      // ── Wallet Section ──────────────────────────────
                      if (!_isWalletFetching && _walletBalance > 0) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.green.withValues(alpha: 0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.account_balance_wallet,
                                          color: Colors.green[700]),
                                      const SizedBox(width: 8),
                                      const Text("Wallet Balance",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  Text("₹${_walletBalance.toStringAsFixed(0)}",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green[700])),
                                ],
                              ),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                value: _walletToUse > 0,
                                title: const Text("Apply Wallet Balance",
                                    style: TextStyle(fontSize: 14)),
                                subtitle: Text(
                                  _walletToUse > 0
                                      ? "₹${_walletToUse.toStringAsFixed(0)} applied"
                                      : "Use your credit for this payment",
                                  style: const TextStyle(fontSize: 12),
                                ),
                                activeColor: Colors.green,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      double currentTotal = double.tryParse(
                                              _amountCtrl.text) ??
                                          0.0;
                                      _walletToUse =
                                          _walletBalance > currentTotal
                                              ? currentTotal
                                              : _walletBalance;
                                      _amountCtrl.text = (currentTotal -
                                              _walletToUse)
                                          .toStringAsFixed(0);
                                    } else {
                                      double currentTotal = double.tryParse(
                                              _amountCtrl.text) ??
                                          0.0;
                                      _amountCtrl.text = (currentTotal +
                                              _walletToUse)
                                          .toStringAsFixed(0);
                                      _walletToUse = 0.0;
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      const Text("Choose your preferred method",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      // Mode toggle
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            _modeTab("UPI / Online", Icons.phone_android,
                                PaymentMode.upi),
                            _modeTab("Demand Draft", Icons.account_balance,
                                PaymentMode.dd),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_paymentMode == PaymentMode.dd) ...[
                        // DD instructions
                        _infoBanner(
                          color: Colors.blue,
                          icon: Icons.info_outline,
                          title: "Demand Draft Instructions",
                          body: "• Get a DD payable to \"APEC College of Engineering\" from any bank\n"
                              "• Take a clear photo of the DD in the next step\n"
                              "• Also submit the physical DD to the college accounts office",
                        ),
                      ] else ...[
                        // UPI payment details
                        if (_paymentDetails == null)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              "No specific bank details found. Please verify with admin.",
                              style: TextStyle(color: Colors.orange),
                            ),
                          ),
                        if (_paymentDetails != null &&
                            _paymentDetails!['qrCodeUrl'] != null)
                          Center(
                            child: Column(children: [
                              Text("Scan to Pay",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo[900])),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.all(4),
                                child: Image.network(
                                  _paymentDetails!['qrCodeUrl'],
                                  height: 180,
                                  width: 180,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (ctx, child, progress) =>
                                      progress == null
                                          ? child
                                          : const SizedBox(
                                              height: 180,
                                              width: 180,
                                              child: Center(
                                                  child:
                                                      CircularProgressIndicator())),
                                  errorBuilder: (ctx, err, stack) =>
                                      const SizedBox(
                                          height: 180,
                                          width: 180,
                                          child: Center(
                                              child: Icon(Icons.broken_image,
                                                  size: 50,
                                                  color: Colors.grey))),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ]),
                          ),
                        Card(
                          elevation: 2,
                          color: Colors.indigo[50],
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow("Pay To",
                                    _paymentDetails?['accountName'] ??
                                        "A-DACS College"),
                                if (_paymentDetails?['bankName'] != null)
                                  _buildDetailRow(
                                      "Bank", _paymentDetails!['bankName']),
                                if (_paymentDetails?['accountNumber'] != null)
                                  _buildDetailRow("Account No",
                                      _paymentDetails!['accountNumber']),
                                if (_paymentDetails?['ifsc'] != null)
                                  _buildDetailRow(
                                      "IFSC", _paymentDetails!['ifsc']),
                                Divider(color: Colors.indigo[100]),
                                _buildDetailRow("UPI ID",
                                    _paymentDetails?['upiId'] ??
                                        "collegefees@sbi"),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: _launchUPI,
                            icon: const Icon(Icons.payment),
                            label: const Text("Open UPI App"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  isActive: _currentStep >= 0,
                ),

                // ── Step 2: Upload ──────────────────────────────
                Step(
                  title: Text(_paymentMode == PaymentMode.dd
                      ? "Upload DD Photo"
                      : "Upload Screenshot"),
                  content: Column(
                    children: [
                      if (kIsWeb)
                        _infoBanner(
                          color: Colors.orange,
                          icon: Icons.smartphone,
                          title: "Mobile Required",
                          body:
                              "Receipt scanning is not available on web. Please use the mobile app.",
                        ),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          _imageFile != null
                              ? Image.file(File(_imageFile!.path), height: 160)
                              : Container(
                                  height: 100,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                      child: Text(
                                    _paymentMode == PaymentMode.dd
                                        ? "No DD Photo"
                                        : "No Screenshot",
                                    style: const TextStyle(color: Colors.grey),
                                  ))),
                          if (_isScanning)
                            Container(
                              height: 160,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Center(
                                  child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                      color: Colors.white),
                                  SizedBox(height: 8),
                                  Text("Scanning...",
                                      style: TextStyle(color: Colors.white)),
                                ],
                              )),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        icon: Icon(_paymentMode == PaymentMode.dd
                            ? Icons.document_scanner
                            : Icons.camera_alt),
                        label: Text(kIsWeb
                            ? "Upload Not Available on Web"
                            : _paymentMode == PaymentMode.dd
                                ? "Take / Select DD Photo"
                                : "Select Screenshot"),
                        onPressed: _pickAndScanImage,
                        style: kIsWeb
                            ? TextButton.styleFrom(
                                foregroundColor: Colors.grey)
                            : null,
                      ),
                      if (_ocrRan && !_isScanning)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "OCR complete — check & edit details in the next step",
                            style: TextStyle(
                                color: Colors.green[700],
                                fontSize: 12,
                                fontStyle: FontStyle.italic),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                  isActive: _currentStep >= 1,
                ),

                // ── Step 3: Verify Details ──────────────────────
                Step(
                  title: const Text("Verify Details"),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_ocrRan) ...[
                        // ── OCR Extracted Values Card ─────────────
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            border: Border.all(color: Colors.green[300]!),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.document_scanner, color: Colors.green[700], size: 18),
                                  const SizedBox(width: 6),
                                  Text("OCR Extracted Values",
                                      style: TextStyle(fontWeight: FontWeight.bold,
                                          color: Colors.green[800], fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_paymentMode == PaymentMode.upi) ...[
                                if (_ocrOriginalTxn != null)
                                  _ocrRow("Transaction ID", _ocrOriginalTxn!),
                                if (_ocrOriginalAmount != null)
                                  _ocrRow("Amount", "₹ ${_ocrOriginalAmount!}"),
                                if (_ocrOriginalDate != null)
                                  _ocrRow("Date", _ocrOriginalDate!),
                                if (_ocrOriginalRegNo != null)
                                  _ocrRow("Reg No", _ocrOriginalRegNo!),
                              ] else ...[
                                if (_ocrOriginalTxn != null)
                                  _ocrRow("DD Number", _ocrOriginalTxn!),
                                if (_ocrOriginalAmount != null)
                                  _ocrRow("Amount", "₹ ${_ocrOriginalAmount!}"),
                                if (_ocrOriginalDate != null)
                                  _ocrRow("Date", _ocrOriginalDate!),
                              ],
                              if (_ocrOriginalTxn == null && _ocrOriginalAmount == null)
                                Text("No values could be auto-extracted. Please fill manually.",
                                    style: TextStyle(fontSize: 12, color: Colors.orange[800])),
                              const SizedBox(height: 6),
                              Text(
                                "⚠ Editing any field below will remove OCR-Verified status.",
                                style: TextStyle(fontSize: 11, color: Colors.orange[800],
                                    fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 4),

                      // ── UPI fields ────────────────────────────
                      if (_paymentMode == PaymentMode.upi) ...[
                        _labeledField(
                          label: "Transaction ID",
                          hint: "Enter UPI Transaction / Ref ID",
                          controller: _txnCtrl,
                          icon: Icons.receipt_long,
                          ocrValue: _ocrOriginalTxn,
                        ),
                        const SizedBox(height: 14),
                        _labeledField(
                          label: "Amount Paid (₹)",
                          hint: "Enter amount",
                          controller: _amountCtrl,
                          icon: Icons.currency_rupee,
                          keyboardType: TextInputType.number,
                          ocrValue: _ocrOriginalAmount,
                        ),
                        if (_isInstallmentMode) ...[
                          const SizedBox(height: 8),
                          _balanceInfo(),
                        ],
                        const SizedBox(height: 14),
                        _labeledField(
                          label: "Payment Date",
                          hint: "e.g. 23/02/2025",
                          controller: _dateCtrl,
                          icon: Icons.calendar_today,
                          ocrValue: _ocrOriginalDate,
                          onTap: _pickDate,
                        ),
                        const SizedBox(height: 14),
                        _labeledField(
                          label: "Register / Roll Number (from receipt)",
                          hint: "If shown on receipt",
                          controller: _regNoCtrl,
                          icon: Icons.badge,
                          ocrValue: _ocrOriginalRegNo,
                        ),
                      ],

                      // ── DD fields ─────────────────────────────
                      if (_paymentMode == PaymentMode.dd) ...[
                        _labeledField(
                          label: "DD Number",
                          hint: "Enter DD Number",
                          controller: _ddNumberCtrl,
                          icon: Icons.confirmation_number,
                          keyboardType: TextInputType.number,
                          ocrValue: _ocrOriginalTxn,
                        ),
                        const SizedBox(height: 14),
                        _labeledField(
                          label: "Bank Name",
                          hint: "e.g. State Bank of India, Chennai",
                          controller: _ddBankCtrl,
                          icon: Icons.account_balance,
                          ocrValue: _ocrRan ? (_ocrOriginalTxn != null ? _ddBankCtrl.text : null) : null,
                        ),
                        const SizedBox(height: 14),
                        _labeledField(
                          label: "DD Date",
                          hint: "Select DD Date",
                          controller: _dateCtrl,
                          icon: Icons.calendar_today,
                          ocrValue: _ocrOriginalDate,
                          onTap: _pickDate,
                        ),
                        const SizedBox(height: 14),
                        _labeledField(
                          label: "Amount (₹)",
                          hint: "Enter DD Amount",
                          controller: _amountCtrl,
                          icon: Icons.currency_rupee,
                          keyboardType: TextInputType.number,
                          ocrValue: _ocrOriginalAmount,
                        ),
                        if (_isInstallmentMode) ...[
                          const SizedBox(height: 8),
                          _balanceInfo(),
                        ],
                        const SizedBox(height: 14),
                        _labeledField(
                          label: "Register / Roll Number (from receipt)",
                          hint: "If shown on receipt",
                          controller: _regNoCtrl,
                          icon: Icons.badge,
                          ocrValue: _ocrOriginalRegNo,
                        ),
                        const SizedBox(height: 12),
                        _infoBanner(
                          color: Colors.amber,
                          icon: Icons.warning_amber,
                          title: "Important",
                          body:
                              "Remember to also submit the physical DD to the college accounts office.",
                        ),
                      ],

                      if (_isUploading) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                  isActive: _currentStep >= 2,
                ),
              ],
            ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _dateCtrl.text =
          "${picked.day.toString().padLeft(2, '0')}/"
          "${picked.month.toString().padLeft(2, '0')}/"
          "${picked.year}";
    }
  }

  Widget _modeTab(String label, IconData icon, PaymentMode mode) {
    final selected = _paymentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _paymentMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.indigo : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: selected ? Colors.white : Colors.grey[600], size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : Colors.grey[600],
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBanner({
    required MaterialColor color,
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color[50],
        border: Border.all(color: color[300]!),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color[700], size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color[800])),
          ]),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(fontSize: 12, height: 1.7)),
          ],
        ],
      ),
    );
  }

  /// Small row used inside the OCR Extracted Values summary card.
  Widget _ocrRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  /// A labeled text field that optionally shows a small "OCR: original value"
  /// hint below when the user has edited the field.
  Widget _labeledField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    String? ocrValue,
    TextInputType? keyboardType,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: onTap != null,
          onTap: onTap,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(icon),
            // Show a small OCR chip if value was originally extracted
            suffixIcon: ocrValue != null
                ? Tooltip(
                    message: "OCR extracted: $ocrValue",
                    child: const Icon(Icons.document_scanner,
                        size: 18, color: Colors.green),
                  )
                : null,
          ),
        ),
        // Show the original OCR value as helper text when field is edited
        if (ocrValue != null && controller.text != ocrValue)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              "Original (OCR): $ocrValue",
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange[800],
                  fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 100,
              child: Text(label,
                  style: TextStyle(
                      color: Colors.indigo[700],
                      fontWeight: FontWeight.bold))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
          if (label == 'Account No' || label == 'UPI ID' || label == 'IFSC')
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("Copied $value"),
                    duration: const Duration(seconds: 1)));
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Icon(Icons.copy, size: 16, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _planOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: selected ? Colors.indigo : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.indigo),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: selected ? Colors.white : Colors.indigo[900],
                          fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: TextStyle(
                          color: selected ? Colors.white70 : Colors.grey[600],
                          fontSize: 12)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _balanceInfo() {
    double entered = double.tryParse(_amountCtrl.text) ?? 0.0;
    double total = widget.amount;
    double alreadyPaid = _installmentNumber == 2 ? _paidInFirst : 0.0;
    double remaining = total - alreadyPaid - entered;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: remaining < 0
            ? Colors.red.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            remaining <= 0 ? "Full balance cleared" : "Remaining balance:",
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          Text(
            "₹${remaining.toStringAsFixed(0)}",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: remaining < 0 ? Colors.red : Colors.green[800],
            ),
          ),
        ],
      ),
    );
  }
}
