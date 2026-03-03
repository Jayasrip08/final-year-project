import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Ensure Master Admin Exists
  Future<void> ensureMasterAdminExists() async {
    const String masterEmail = "sri17182021@gmail.com";
    const String masterPass = "ApecAdmin@2026";
    const String masterEmpId = "420422205001";
    
    try {
      // Check if user exists in Firestore
      final query = await _db.collection('users').where('email', isEqualTo: masterEmail).get();
      
      if (query.docs.isEmpty) {
        // Create Authentication User
        try {
           await _auth.createUserWithEmailAndPassword(email: masterEmail, password: masterPass);
        } catch (e) {
           // Auth might already exist even if firestore doc doesn't
           print("Auth user might already exist: $e");
        }
        
        // Create/Update Firestore Doc using sign-in to get UID
        try {
           UserCredential cred = await _auth.signInWithEmailAndPassword(email: masterEmail, password: masterPass);
           String uid = cred.user!.uid;
           
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
           print("Error setting up master admin: $e");
        }
      }
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
        final duplicateCheck = await _db.collection('users').where('regNo', isEqualTo: regNo).get();
        if (duplicateCheck.docs.isNotEmpty) {
          return "Register Number '$regNo' is already registered.";
        }
      }
      
      if ((role == 'staff' || role == 'admin') && employeeId != null && employeeId.isNotEmpty) {
        final duplicateCheck = await _db.collection('users').where('employeeId', isEqualTo: employeeId).get();
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
  // 3. Google Sign-In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null; // The user canceled the sign-in

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google User Credential
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      print("Google Sign In Error: $e");
      return null;
    }
  }

  // 4. Create Firestore User (for Google Sign In or other providers)
  Future<void> createFirestoreUser({
    required User user,
    required String role,
    required String name,
    String? regNo,
    String? dept,
    String? employeeId,
    String? quotaCategory,
    String? batch,
    String? studentType,
    String? busPlace,
    String? phone,
    String? parentPhoneNumber,
  }) async {
    // Check if doc exists first
    DocumentSnapshot doc = await _db.collection('users').doc(user.uid).get();
    if (doc.exists) return; // User already has a profile

    // Check Admin approval
    QuerySnapshot adminQuery = await _db.collection('users').where('role', isEqualTo: 'admin').limit(1).get();
    bool firstAdmin = adminQuery.docs.isEmpty;
    String approvalStatus = (role == 'admin' && firstAdmin) ? 'approved' : 'pending';
    if (role == 'student') approvalStatus = 'approved';

    await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name,
        'email': user.email ?? '',
        'phone': phone ?? '',
        'parentPhoneNumber': parentPhoneNumber ?? '',
        'role': role,
        'approvalStatus': approvalStatus,
        'regNo': regNo ?? '',
        'dept': dept ?? '',
        'employeeId': employeeId ?? '', 
        'quotaCategory': quotaCategory ?? 'Management',
        'batch': batch ?? '',
        'studentType': studentType ?? 'day_scholar',
        'busPlace': busPlace ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        
        if (role == 'student') ...{
          'totalFee': 85000, 
          'paidFee': 0,
          'status': 'Pending'
        }
    });

    // Update Master List
    if (role == 'student' && regNo != null && regNo.isNotEmpty) {
       await _db.collection('student_master_list').doc(regNo).update({'isRegistered': true});
    }
    if ((role == 'staff' || role == 'admin') && employeeId != null && employeeId.isNotEmpty) {
        try {
           await _db.collection('staff_master_list').doc(employeeId).update({'isRegistered': true});
        } catch (_) {}
    }

  }

  // 5. Sign Out
  Future<void> signOut(dynamic context) async {
    await _auth.signOut();
    try {
      if (await GoogleSignIn().isSignedIn()) {
        await GoogleSignIn().signOut();
      }
    } catch (_) {}
    
    // We expect the UI to handle navigation to LoginScreen
  }
}