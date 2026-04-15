import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Ensure Master Admin Exists
  Future<void> ensureMasterAdminExists() async {
    const String masterEmail = "sri17182021@gmail.com";
    const String masterPass = "ApecAdmin@2026";
    const String masterEmpId = "420422205001";
    
    try {
      // Step 1: Attempt to sign in to check if auth user exists
      try {
        await _auth.signInWithEmailAndPassword(email: masterEmail, password: masterPass);
        print("Master Admin signed in successfully (exists).");
        
        // Check if Firestore document exists, if not create it
        final user = _auth.currentUser;
        if (user != null) {
          final doc = await _db.collection('users').doc(user.uid).get();
          if (!doc.exists) {
            await _db.collection('users').doc(user.uid).set({
              'uid': user.uid,
              'name': 'A-DACS ADMIN',
              'email': masterEmail,
              'role': 'admin',
              'employeeId': masterEmpId,
              'dept': 'Administration', 
              'approvalStatus': 'approved',
              'isRegistered': true,
              'createdAt': FieldValue.serverTimestamp(),
            });
            print("Master Admin Firestore document created.");
          }
        }
        
        await _auth.signOut();
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          // User doesn't exist, proceed to create
          print("Master Admin not found, creating...");
        } else {
          // Some other auth error (e.g. wrong password, but user might exist)
          print("Auth check returned: ${e.code}. Skipping creation.");
          return;
        }
      }

      // Step 2: Create Authentication User
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: masterEmail, 
        password: masterPass
      );
      
      String uid = result.user!.uid;
      
      // Step 3: Create Firestore Doc
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'name': 'A-DACS ADMIN',
        'email': masterEmail,
        'role': 'admin',
        'employeeId': masterEmpId,
        'dept': 'Administration', 
        'approvalStatus': 'approved',
        'isRegistered': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      await _auth.signOut();
      print("Master Admin Created Successfully");
      
    } catch (e) {
      print("Check Master Admin Failed: $e");
    }
  }

  // 1. REGISTER: Create Auth User + Firestore Document
  Future<String?> registerUser({
    required String email,
    required String password,
    required String name,
    required String role, 
    String? regNo,
    String? dept,
    String? quotaCategory,
    String? employeeId, 
    String? batch, // NEW: Batch field (e.g. 2024-2028)
    String? studentType, // NEW: Student type (day_scholar/hosteller/bus_user)
    String? busPlace, // NEW: Bus place if bus_user
    String? phone, // NEW: Student/Staff phone
    String? parentPhoneNumber, // NEW: Parent's phone for SMS
    bool isApproved = false, // NEW: Support auto-approval
  }) async {
    try {
      // 1. Check for Duplicate RegNo/EmployeeId in Firestore BEFORE creating Auth User
      if (role == 'student' && regNo != null && regNo.isNotEmpty) {
        final duplicateCheck = await _db.collection('users').where('regNo', isEqualTo: regNo).limit(1).get();
        if (duplicateCheck.docs.isNotEmpty) {
          return "Register Number '$regNo' is already registered.";
        }
      }
      
      if ((role == 'staff' || role == 'admin') && employeeId != null && employeeId.isNotEmpty) {
        final duplicateCheck = await _db.collection('users').where('employeeId', isEqualTo: employeeId).limit(1).get();
        if (duplicateCheck.docs.isNotEmpty) {
           return "Employee ID '$employeeId' is already registered.";
        }
      }

      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email, 
        password: password
      );
      
      User? user = result.user;

      // 1. Check if ANY admin already exists
      QuerySnapshot adminQuery = await _db.collection('users').where('role', isEqualTo: 'admin').limit(1).get();
      bool firstAdmin = adminQuery.docs.isEmpty;

      // Determine approval status: 
      // - If isApproved is true (e.g. from OTP flow), they are approved
      // - First Admin: Approved (Auto)
      // - Meaning subsequent Admins/Staff without verification: Pending
      String approvalStatus = isApproved ? 'approved' : 'pending';
      // Only the very first admin is auto-approved
      if (role == 'admin' && firstAdmin) {
        approvalStatus = 'approved';
      }

      await _db.collection('users').doc(user!.uid).set({
        'uid': user.uid,
        'name': name,
        'email': email,
        'phone': phone ?? '', // NEW
        'parentPhoneNumber': parentPhoneNumber ?? '', // NEW
        'role': role,
        'approvalStatus': approvalStatus, // NEW: Approval workflow
        'regNo': regNo ?? '',
        'dept': dept ?? '',
        'employeeId': employeeId ?? '', 
        'quotaCategory': quotaCategory ?? 'Management',
        'batch': batch ?? '', // NEW
        'studentType': studentType ?? 'day_scholar', // NEW
        'busPlace': busPlace ?? '', // NEW
        'createdAt': FieldValue.serverTimestamp(),
        
        if (role == 'student') ...{
          'totalFee': 85000, 
          'paidFee': 0,
          'status': 'Pending'
        }
      });

      // Update Master List if Student
      if (role == 'student' && regNo != null && regNo.isNotEmpty) {
        await _db.collection('student_master_list').doc(regNo).update({'isRegistered': true});
      }
      
      // Update Master List if Staff
      if ((role == 'staff' || role == 'admin') && employeeId != null && employeeId.isNotEmpty) {
         // Note: Admin might not always be in staff list, but if they came through verification, they will be.
         // We should check if doc exists or just try update.
         // For now, assume if they have employeeId, they are in staff list.
         try {
            await _db.collection('staff_master_list').doc(employeeId).update({'isRegistered': true});
         } catch (e) {
            // Ignore if not found (e.g. first admin created manually without master list)
            print("Staff not in master list or error: $e");
         }
      }

      // Notify all admins about new registration (if pending approval)
      if (approvalStatus == 'pending') {
        try {
          final adminSnapshot = await _db
              .collection('users')
              .where('role', isEqualTo: 'admin')
              .where('approvalStatus', isEqualTo: 'approved')
              .get();
          
          for (var adminDoc in adminSnapshot.docs) {
            await _db.collection('notifications').add({
              'userId': adminDoc.id,
              'title': 'New ${role.toUpperCase()} Registration',
              'body': '$name has registered and requires approval.',
              'type': 'new_registration',
              'timestamp': FieldValue.serverTimestamp(),
              'read': false,
              'received': false,
              'payload': {
                'newUserId': user.uid,
                'role': role,
                'name': name,
                'email': email,
              }
            });
          }
        } catch (e) {
          print("Error creating admin notifications: $e");
        }
      }

      await _auth.signOut(); // Ensure fresh login is required
      return null; 
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return "An unknown error occurred";
    }
  }

  // 2. LOGIN: Check approval status
  Future<Map<String, dynamic>?> loginUser(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email, password: password);
      DocumentSnapshot doc = await _db.collection('users').doc(result.user!.uid).get();
      
      if (doc.exists) {
        Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
        
        // Check approval status
        String approvalStatus = userData['approvalStatus'] ?? 'approved';
        if (approvalStatus == 'pending') {
          // Sign out the user immediately
          await _auth.signOut();
          throw Exception('Your account is pending admin approval. Please wait for approval.');
        }
        
        return userData;
      }
      return null;
    } catch (e) {
      throw e.toString(); 
    }
  }


  // 5. Sign Out
  Future<void> signOut(dynamic context) async {
    await _auth.signOut();
    // We expect the UI to handle navigation to LoginScreen
  }
}