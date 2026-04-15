import 'package:cloud_firestore/cloud_firestore.dart';

class FeeService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ADMIN: Set Comprehensive Fee Structure
  Future<void> setFeeComponents({
    required String academicYear,
    required String quotaCategory,
    required String dept,
    required String semester,
    required Map<String, dynamic> components,
    required double totalAmount,
    DateTime? deadline,
    double? examFee,
    DateTime? examDeadline,
  }) async {
    // 1. Create a deterministic document ID for this combination
    String sanitizedDept = dept.replaceAll(" ", "_");
    String sanitizedQuota = quotaCategory.replaceAll(" ", "_");
    String docId = "${academicYear}_${sanitizedDept}_${sanitizedQuota}_$semester";
    DocumentReference feeRef = _db.collection('fee_structures').doc(docId);
    
    // 2. Save/Update the structure (Overwrite to ensure deletions are reflected)
    // Check if it exists to preserve createdAt
    final docSnapshot = await feeRef.get();
    DateTime createdAt = DateTime.now();
    if (docSnapshot.exists) {
      final data = docSnapshot.data() as Map<String, dynamic>;
      if (data['createdAt'] != null) {
        createdAt = (data['createdAt'] as Timestamp).toDate();
      }
    }

    await feeRef.set({
      'academicYear': academicYear,
      'dept': dept,
      'quotaCategory': quotaCategory,
      'semester': semester,
      'components': components,
      'totalAmount': totalAmount,
      'deadline': deadline != null ? Timestamp.fromDate(deadline) : null,
      'examFee': examFee ?? 0.0,
      'examDeadline': examDeadline != null ? Timestamp.fromDate(examDeadline) : null,
      'isActive': true,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    // 3. Notify relevant students
    try {
      Query studentsQuery = _db.collection('users').where('role', isEqualTo: 'student').where('batch', isEqualTo: academicYear);
      
      if (dept != 'All') {
        studentsQuery = studentsQuery.where('dept', isEqualTo: dept);
      }
      if (quotaCategory != 'All') {
        studentsQuery = studentsQuery.where('quotaCategory', isEqualTo: quotaCategory);
      }
      
      final studentSnapshot = await studentsQuery.get();
      
      for (var studentDoc in studentSnapshot.docs) {
        await _db.collection('notifications').add({
          'userId': studentDoc.id,
          'title': 'New Fee Structure',
          'body': 'A new fee structure for Semester $semester ($academicYear) has been updated.',
          'type': 'payment_reminder',
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
          'received': false,
          'payload': {
            'semester': semester,
            'academicYear': academicYear,
          }
        });
      }
    } catch (e) {
      print("Error notifying students: $e");
    }
  }

  // STUDENT: Get Fee Components (Aggregated/Additive)
  // Uses deterministic doc IDs (same format as setFeeComponents) to avoid
  // compound queries that need composite indexes and cause PERMISSION_DENIED.
  Future<Map<String, dynamic>?> getFeeComponents(String dept, String quotaCategory, String batch, String semester) async {
    // We want to fetch all matching configurations and merge them.
    // Order: General -> Specific (Specific overrides General if key matches)
    //
    // Doc ID format (matches setFeeComponents):
    //   {batch}_{sanitizedDept}_{sanitizedQuota}_{semester}
    String sanitizedDept   = dept.replaceAll(' ', '_');
    String sanitizedQuota  = quotaCategory.replaceAll(' ', '_');

    List<String> docIds = [
      '${batch}_All_All_$semester',                              // 1. Most General
      '${batch}_${sanitizedDept}_All_$semester',                 // 2. Specific Dept
      '${batch}_All_${sanitizedQuota}_$semester',                // 3. Specific Quota
      '${batch}_${sanitizedDept}_${sanitizedQuota}_$semester',   // 4. Most Specific
    ];
    
    Map<String, dynamic> combinedComponents = {};
    DateTime? latestDeadline;
    double? examFee;
    DateTime? examDeadline;

    bool foundAny = false;

    for (var docId in docIds) {
      try {
        final docSnap = await _db.collection('fee_structures').doc(docId).get();

        if (docSnap.exists) {
          final data = docSnap.data() as Map<String, dynamic>;

          // Skip inactive fee structures
          if (data['isActive'] == false) continue;

          foundAny = true;

          // Merge components
          if (data['components'] != null) {
            combinedComponents.addAll(Map<String, dynamic>.from(data['components']));
          }

          // Take the latest/most specific deadline if available
          if (data['deadline'] != null) {
            latestDeadline = (data['deadline'] as Timestamp?)?.toDate();
          }

          // Take exam fee/deadline if available (last one wins - specific overrides general)
          if (data['examFee'] != null) {
            examFee = (data['examFee'] as num).toDouble();
          }
          if (data['examDeadline'] != null) {
            examDeadline = (data['examDeadline'] as Timestamp?)?.toDate();
          }
        }
      } catch (e) {
        // Log but continue — an error on one level shouldn't block others
        print('FeeService: doc fetch for $docId failed: $e');
      }
    }
    
    if (!foundAny) return null;

    // Calculate total for the combined set
    double total = 0;
    combinedComponents.forEach((key, value) {
      if (value is Map) {
        // Bus fee logic (summing routes is standard here for total display, 
        // though student chooses one in detail screen)
        for (var amt in value.values) {
          total += (amt as num).toDouble();
        }
      } else {
        total += (value as num).toDouble();
      }
    });
    
    if (examFee != null) {
      total += examFee;
    }

    return {
      'academicYear': batch,
      'dept': dept,
      'quotaCategory': quotaCategory,
      'semester': semester,
      'components': combinedComponents,
      'examFee': examFee,
      'examDeadline': examDeadline != null ? Timestamp.fromDate(examDeadline) : null,
      'totalAmount': total,
      'deadline': latestDeadline != null ? Timestamp.fromDate(latestDeadline) : null,
      'isActive': true,
    };
  }

  // STUDENT: Submit Proof for Specific Component
  Future<void> submitComponentProof({
    required String uid,
    required String semester,
    required String feeType, // E.g., "Tuition Fee"
    required double amountExpected,
    required double amountPaid, 
    required String transactionId, 
    required String proofUrl,
    bool ocrVerified = false,
    bool isInstallment = false,
    int installmentNumber = 1,
    double walletUsedAmount = 0.0,
    Map<String, dynamic>? extraData, // Optional enrichment merged into the same set()
  }) async {
    // ID: uid_semester_feeType (Sanitized)
    String sanitizedType = feeType.replaceAll(" ", "_");
    String suffix = (isInstallment && installmentNumber == 2) ? "_inst2" : "";
    String paymentId = "${uid}_${semester}_$sanitizedType$suffix";
    
    // Build the base document data — 'studentId' is required by the Firestore
    // create rule: `request.resource.data.studentId == request.auth.uid`
    final Map<String, dynamic> docData = {
      'uid': uid,
      'studentId': uid,          // ← required for Firestore create rule
      'semester': semester,
      'feeType': feeType,
      'amountExpected': amountExpected,
      'amountPaid': amountPaid, 
      'walletUsedAmount': walletUsedAmount,
      'amount': amountPaid + walletUsedAmount, // Total value of this transaction
      'transactionId': transactionId, 
      'proofUrl': proofUrl,
      'status': 'under_review',
      'ocrVerified': ocrVerified,
      'submittedAt': FieldValue.serverTimestamp(),
      // Merge any extra enrichment fields (e.g. from payment_screen)
      // so we avoid a separate .update() call that requires admin rights
      if (extraData != null) ...extraData,
    };

    await _db.collection('payments').doc(paymentId).set(docData);
    
    // Notify all admins about new payment submission
    try {
      final adminSnapshot = await _db
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .where('approvalStatus', isEqualTo: 'approved')
          .get();

      // Get student name
      final studentDoc = await _db.collection('users').doc(uid).get();
      final studentName = studentDoc.data()?['name'] ?? 'Unknown Student';

      for (var adminDoc in adminSnapshot.docs) {
        await _db.collection('notifications').add({
          'userId': adminDoc.id,
          'title': 'New Payment Submission',
          'body': '$studentName submitted $feeType payment of ₹$amountPaid',
          'type': 'new_payment',
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
          'received': false,
          'payload': {
            'paymentId': paymentId,
            'studentId': uid,
            'studentName': studentName,
            'amount': amountPaid,
            'feeType': feeType,
          }
        });
      }
    } catch (e) {
      print("Error creating admin notifications: $e");
    }
  }

  // ADMIN: Verify Payment Component (Transactional)
  Future<void> verifyPaymentComponent(String paymentId, bool isApproved, {String? rejectionReason}) async {
    await _db.runTransaction((transaction) async {
      // 1. Read Payment Document
      DocumentReference paymentRef = _db.collection('payments').doc(paymentId);
      DocumentSnapshot paymentSnapshot = await transaction.get(paymentRef);

      if (!paymentSnapshot.exists) {
        throw Exception("Payment document not found!");
      }

      final paymentData = paymentSnapshot.data() as Map<String, dynamic>;
      
      // Prevent double verification
      if (paymentData['status'] == 'verified' && isApproved) {
        return; // Already verified, no change needed
      }

      final studentId = paymentData['studentId'] ?? paymentData['uid'];
      final amount = (paymentData['amount'] ?? paymentData['amountPaid'] ?? 0).toDouble();
      final feeType = paymentData['feeType'] ?? 'Payment';

      // 2. Initial Reads (All reads must be before writes!)
      DocumentReference? userRef = studentId != null ? _db.collection('users').doc(studentId) : null;
      DocumentSnapshot? userSnapshot = userRef != null ? await transaction.get(userRef) : null;
      DocumentReference? walletRef = studentId != null ? _db.collection('wallets').doc(studentId) : null;
      DocumentSnapshot? walletSnapshot = walletRef != null ? await transaction.get(walletRef) : null;
      
      double surplus = 0.0;
      double walletUsed = (paymentData['walletUsedAmount'] as num?)?.toDouble() ?? 0.0;
      double pocketAmount = (paymentData['amountPaid'] as num?)?.toDouble() ?? 0.0;
      
      // Use fullFeeAmount (original total fee) for surplus calculation.
      double fullFee = (paymentData['fullFeeAmount'] as num?)?.toDouble()
          ?? ((paymentData['amountExpected'] as num?)?.toDouble() ?? 0.0) + walletUsed;
      
      if (isApproved) {
        // Fetch installments if approved to check for surplus
        String sem = paymentData['semester'] ?? '';
        String qType = (paymentData['feeType'] ?? '').toString().replaceAll(" ", "_");
        String p1Id = "${studentId}_${sem}_$qType";
        String p2Id = "${studentId}_${sem}_${qType}_inst2";
        
        DocumentSnapshot s1 = await transaction.get(_db.collection('payments').doc(p1Id));
        DocumentSnapshot s2 = await transaction.get(_db.collection('payments').doc(p2Id));

        double totalSubmittedValue = 0.0;
        if (s1.exists && (s1.data() as Map)['status'] == 'verified') {
           totalSubmittedValue += ((s1.data() as Map)['amount'] as num).toDouble();
        } else if (p1Id == paymentId) {
           totalSubmittedValue += (pocketAmount + walletUsed);
        }
        
        if (s2.exists && (s2.data() as Map)['status'] == 'verified') {
           totalSubmittedValue += ((s2.data() as Map)['amount'] as num).toDouble();
        } else if (p2Id == paymentId) {
           totalSubmittedValue += (pocketAmount + walletUsed);
        }

        if (totalSubmittedValue > fullFee) {
           double previousTotal = totalSubmittedValue - (pocketAmount + walletUsed);
           if (previousTotal >= fullFee) {
              surplus = (pocketAmount + walletUsed);
           } else {
              surplus = totalSubmittedValue - fullFee;
           }
        }
      }

      // 3. All Updates (Writes must follow all reads)
      transaction.update(paymentRef, {
        'status': isApproved ? 'verified' : 'rejected',
        'rejectionReason': rejectionReason,
        'verifiedAt': FieldValue.serverTimestamp(),
        if (isApproved) 'surplusCredited': surplus,
      });

      if (isApproved && userRef != null && walletRef != null) {
        // Update user's aggregate paid fee
        transaction.update(userRef, {
          'paidFee': FieldValue.increment(pocketAmount + walletUsed),
          'lastPaymentDate': FieldValue.serverTimestamp(),
          'lastPaymentId': paymentId,
        });

        // Handle Wallet Balance Update (Dedicated Collection)
        if (walletUsed > 0 || surplus > 0) {
          if (walletSnapshot != null && walletSnapshot.exists) {
            transaction.update(walletRef, {
              'balance': FieldValue.increment(surplus - walletUsed),
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          } else {
            // Migration Logic: Check for legacy balance in users doc
            double legacyBalance = 0.0;
            if (userSnapshot != null && userSnapshot.exists) {
              legacyBalance = (userSnapshot.data() as Map?)?['walletBalance']?.toDouble() ?? 0.0;
            }

            transaction.set(walletRef, {
              'uid': studentId,
              'balance': legacyBalance + surplus - walletUsed,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          }

          // Log Wallet Transactions
          if (walletUsed > 0) {
            transaction.set(_db.collection('wallet_transactions').doc(), {
              'uid': studentId,
              'amount': -walletUsed,
              'type': 'debit',
              'reason': 'fee_payment',
              'paymentId': paymentId,
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
          if (surplus > 0) {
            transaction.set(_db.collection('wallet_transactions').doc(), {
              'uid': studentId,
              'amount': surplus,
              'type': 'credit',
              'reason': 'overpayment_surplus',
              'paymentId': paymentId,
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      // 5. Create Notification (Note: Transaction writes must be at the end)
      // Notifications are less critical, so we can do them here effectively
      if (studentId != null) {
        DocumentReference notifRef = _db.collection('notifications').doc();
        transaction.set(notifRef, {
           'userId': studentId,
           'title': isApproved ? 'Payment Verified ✓' : 'Payment Rejected',
           'body': isApproved 
             ? 'Your $feeType payment of ₹$amount has been verified successfully.'
             : 'Your $feeType payment of ₹$amount was rejected. Reason: ${rejectionReason ?? "Please contact admin"}',
           'type': isApproved ? 'payment_verified' : 'payment_rejected',
           'timestamp': FieldValue.serverTimestamp(),
           'read': false,
           'received': false,
           'payload': {
             'paymentId': paymentId,
             'amount': amount,
             'feeType': feeType,
           }
        });
      }
    });
  }

  Future<void> revertPayment(String paymentId) async {
    await _db.runTransaction((transaction) async {
      DocumentReference paymentRef = _db.collection('payments').doc(paymentId);
      DocumentSnapshot paymentSnapshot = await transaction.get(paymentRef);

      if (!paymentSnapshot.exists) return;

      final paymentData = paymentSnapshot.data() as Map<String, dynamic>;
      final String? status = paymentData['status'];
      final String? studentId = paymentData['studentId'] ?? paymentData['uid'];

      if (status == 'under_review') return; // Nothing to revert

      // If it was verified, we need to undo balance changes
      if (status == 'verified' && studentId != null) {
        DocumentReference userRef = _db.collection('users').doc(studentId);
        DocumentReference walletRef = _db.collection('wallets').doc(studentId);
        
        final double walletUsed = (paymentData['walletUsedAmount'] as num?)?.toDouble() ?? 0.0;
        final double pocketAmount = (paymentData['amountPaid'] as num?)?.toDouble() ?? 0.0;
        final double surplus = (paymentData['surplusCredited'] as num?)?.toDouble() ?? 0.0;

        transaction.update(userRef, {
          'paidFee': FieldValue.increment(-(pocketAmount + walletUsed)),
        });

        if (walletUsed > 0 || surplus > 0) {
          transaction.update(walletRef, {
            'balance': FieldValue.increment(walletUsed - surplus),
            'lastUpdated': FieldValue.serverTimestamp(),
          });

          // Log Reversal Transactions
          transaction.set(_db.collection('wallet_transactions').doc(), {
            'uid': studentId,
            'amount': walletUsed - surplus,
            'type': (walletUsed - surplus) > 0 ? 'credit' : 'debit',
            'reason': 'payment_reversal',
            'paymentId': paymentId,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      }

      // Reset payment status
      transaction.update(paymentRef, {
        'status': 'under_review',
        'verifiedAt': FieldValue.delete(),
        'rejectionReason': FieldValue.delete(),
        'surplusCredited': FieldValue.delete(),
      });
    });
  }

  // HELPER: Calculate Fee Amount for specific student type
  double calculateStudentFee({
    required Map<String, dynamic> feeStructure,
    required String studentType, // 'hosteller', 'bus_user', 'day_scholar'
    String? busPlace,
  }) {
    double total = 0.0;
    Map<String, dynamic> components = feeStructure['components'] as Map<String, dynamic>? ?? {};

    for (var entry in components.entries) {
      String feeType = entry.key;
      var feeValue = entry.value;

      // Skip hostel fee for non-hostellers
      if (feeType.toLowerCase().contains('hostel') && studentType != 'hosteller') {
        continue;
      }

      // Handle bus fee
      if (feeType.toLowerCase().contains('bus')) {
        if (studentType != 'bus_user') {
          continue; // Skip bus fee for non-bus users
        } else if (feeValue is Map) {
          // Bus fee is a map of places
          if (busPlace != null && feeValue.containsKey(busPlace)) {
            total += (feeValue[busPlace] as num).toDouble();
          }
          continue;
        }
      }

      // Add regular fees
      if (feeValue is num) {
        total += feeValue.toDouble();
      }
    }

    // Add Exam Fee if present
    if (feeStructure['examFee'] != null) {
      total += (feeStructure['examFee'] as num).toDouble();
    }

    return total;
  }
}