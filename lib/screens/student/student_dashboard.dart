import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'semester_detail_screen.dart';
import 'documents_screen.dart';
import 'clearance_screen.dart';
import 'fees_ledger_screen.dart';
import 'support_screen.dart';
import '../profile_screen.dart';
import '../notifications_screen.dart';
import '../../widgets/notification_badge.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final User user = FirebaseAuth.instance.currentUser!;
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  int _currentIndex = 0;

  // CUSTOM PROJECT COLOR
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      if (mounted) {
        setState(() {
          _userData = userDoc.data() as Map<String, dynamic>;
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    switch (_currentIndex) {
      case 1:
        return const NotificationsScreen();
      case 2:
        return const ProfileScreen();
      default:
        return _buildHomeContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Text(
          _currentIndex == 0 ? "A-DACS" : _currentIndex == 1 ? "Notice Board" : "Profile",
          style: TextStyle(color: customRed, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        actions: _currentIndex == 0 ? [
          NotificationBadge(
            child: Icon(Icons.notifications_none_rounded, color: Colors.grey[800]),
            onTap: () => setState(() => _currentIndex = 1),
          ),
          const SizedBox(width: 16),
        ] : null,
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: customRed,
        unselectedItemColor: Colors.grey[400],
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 20,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.campaign_outlined), label: "Notice"),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: "Profile"),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('semesters')
          .where('academicYear', isEqualTo: _userData!['batch'] ?? '')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            // ── GREETING & IDENTITY HEADER ────────────────────────
            _buildGreetingHeader(),
            
            const SizedBox(height: 24),
            _buildWalletCard(),
            
            const SizedBox(height: 32),
            // ── STATIC QUICK ACTIONS (ALWAYS VISIBLE) ──────────────
            const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildStaticQuickActions(),

            const SizedBox(height: 32),
            // ── DYNAMIC CLEARED HIGHLIGHTS ────────────────────────
            _buildDynamicClearedHighlights(),

            const SizedBox(height: 32),
            // ── SEMESTER LIST ─────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Active Semesters", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (docs.isNotEmpty)
                  Text("${docs.length} Active", style: TextStyle(color: customRed, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            
            if (docs.isEmpty) 
              _buildEmptyState()
            else
              ...docs.map((doc) => _buildSemesterCard(doc)),
            
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildGreetingHeader() {
    String firstName = _userData!['name']?.split(' ')[0] ?? 'Student';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Welcome back,", style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            Text(
              firstName,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: customRed.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _userData!['dept'] ?? 'N/A',
            style: TextStyle(color: customRed, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildStaticQuickActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _quickActionItem(
          Icons.history_edu_rounded, 
          "Clearance",
          color: Colors.blue,
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => ClearanceScreen(userData: _userData!)));
          },
        ),
        _quickActionItem(
          Icons.account_balance_rounded, 
          "Fees",
          color: Colors.green,
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => FeesLedgerScreen(userData: _userData!)));
          },
        ),
        _quickActionItem(
          Icons.file_present_rounded, 
          "Documents",
          color: Colors.orange,
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => DocumentsScreen(userData: _userData!)));
          },
        ),
        _quickActionItem(
          Icons.help_outline_rounded, 
          "Support",
          color: Colors.purple,
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => SupportScreen(userData: _userData!)));
          },
        ),
      ],
    );
  }

  Widget _buildDynamicClearedHighlights() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('no_due_certificates')
          .where('uid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'issued')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink(); 
        }

        final certificates = snapshot.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Achievement Highlights", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: certificates.length,
                itemBuilder: (context, index) {
                  final data = certificates[index].data() as Map<String, dynamic>;
                  final semNum = data['semester']?.toString() ?? '?';
                  return _clearedSemesterItem(semNum);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _clearedSemesterItem(String sem) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SemesterDetailScreen(userData: _userData!, semester: sem)),
        );
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
              child: const Icon(Icons.verified_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              "Semester $sem",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
            ),
            const Text("CLEARED", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.green)),
          ],
        ),
      ),
    );
  }

  Widget _quickActionItem(IconData icon, String label, {required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('wallets').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        double balance = 0.0;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          balance = (data?['balance'] as num?)?.toDouble() ?? 0.0;
        } else {
          // Fallback to legacy balance in users collection until first update
          balance = (_userData?['walletBalance'] as num?)?.toDouble() ?? 0.0;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade700, Colors.teal.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Wallet Balance", style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "₹${balance.toStringAsFixed(0)}",
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  const Icon(Icons.account_balance_wallet_rounded, color: Colors.white24, size: 48),
                ],
              ),
              const SizedBox(height: 12),
              const Text("Automatic Fee Deduction Enabled", style: TextStyle(color: Colors.white60, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSemesterCard(QueryDocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    String sem = data['semesterNumber'].toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(color: customRed.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(sem, style: TextStyle(color: customRed, fontWeight: FontWeight.bold, fontSize: 20))),
        ),
        title: Text("Semester $sem", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        subtitle: Text(data['academicSession'] ?? 'Active Session', style: TextStyle(color: Colors.grey[600])),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SemesterDetailScreen(userData: _userData!, semester: sem)),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Icon(Icons.school_outlined, size: 80, color: Colors.grey[200]),
        const SizedBox(height: 16),
        const Text("No Active Semesters", style: TextStyle(color: Colors.grey, fontSize: 16)),
        Text("Batch: ${_userData!['batch']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}