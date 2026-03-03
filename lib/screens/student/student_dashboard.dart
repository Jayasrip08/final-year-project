import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'semester_detail_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Semesters"),
        backgroundColor: Colors.indigo,
        elevation: 0,
        actions: [
          NotificationBadge(
            child: const Icon(Icons.notifications),
            onTap: () {
               Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: "My Profile",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('semesters')
                .where('academicYear', isEqualTo: _userData!['batch'] ?? '')
                .where('isActive', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school_outlined, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No active semesters available',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Batch: ${_userData!['batch'] ?? "Not Assigned"}',
                        style: TextStyle(fontSize: 14, color: Colors.indigo, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please contact admin to activate your semester.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }

              final docs = snapshot.data!.docs.toList();
              // Sort in-memory to avoid missing index error
              docs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                return (aData['semesterNumber'] ?? 0).compareTo(bData['semesterNumber'] ?? 0);
              });

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildWalletCard(),
                  const SizedBox(height: 8),
                  ...docs.map((semesterDoc) {
                    var semesterData = semesterDoc.data() as Map<String, dynamic>;
                    String sem = semesterData['semesterNumber'].toString();
                    
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SemesterDetailScreen(
                                userData: _userData!,
                                semester: sem,
                              )
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Semester $sem", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                  const SizedBox(height: 4),
                                  if (semesterData['academicSession'] != null && semesterData['academicSession'].toString().isNotEmpty)
                                    Text(
                                      semesterData['academicSession'],
                                      style: TextStyle(
                                        color: Colors.indigo[300],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  // Display Date Range
                                  if (semesterData['startDate'] != null && semesterData['endDate'] != null)
                                    Builder(
                                      builder: (context) {
                                        final start = (semesterData['startDate'] as Timestamp).toDate();
                                        final end = (semesterData['endDate'] as Timestamp).toDate();
                                        final dateFormat = DateFormat('dd MMM yyyy');
                                        return Text(
                                          "${dateFormat.format(start)} - ${dateFormat.format(end)}",
                                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                        );
                                      }
                                    ),
                                  const SizedBox(height: 5),
                                  const Text("Tap to view fees & upload bills", style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                              const Icon(Icons.arrow_forward_ios, color: Colors.indigo),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
    );
  }

  Widget _buildWalletCard() {
    // Use a StreamBuilder so wallet balance updates in real-time
    // when admin credits the student's wallet — no page reload needed.
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final double balance = (data?['walletBalance'] as num?)?.toDouble() ?? 0.0;
        if (balance <= 0) return const SizedBox.shrink();

        return Card(
          elevation: 4,
          shadowColor: Colors.green.withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                colors: [Colors.green.shade600, Colors.green.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.white, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Wallet Balance",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      Text(
                        "₹${balance.toStringAsFixed(0)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "CREDIT",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}