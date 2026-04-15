import 'package:flutter/material.dart';
import 'admin_side_menu.dart';
import 'fee_setup_screen.dart';
import 'view_fees_screen.dart';
import 'academic_year_screen.dart';
import 'overdue_payments_screen.dart';
import 'user_approval_screen.dart';
import '../profile_screen.dart';
import '../notifications_screen.dart';
import '../../widgets/notification_badge.dart';

import 'admin_payment_list.dart';
import 'admin_student_list.dart';
import 'admin_staff_list.dart';
import 'department_screen.dart';
import 'quota_screen.dart';
import 'admin_student_database.dart';
import 'admin_staff_database.dart';
import 'manage_payment_methods.dart'; 
import 'admin_analytics_screen.dart'; 
import 'admin_nodue_requests.dart'; 
import '../support_inbox_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0; 
  int _bottomNavIndex = 0; 
  
  // NEW: Controller to handle swiping logic
  late PageController _pageController;

  final Color customRed = const Color.fromARGB(255, 198, 55, 45);
  final Color backgroundWhite = const Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sideMenu = AdminSideMenu(
      selectedIndex: _selectedIndex,
      onItemSelected: (index) {
        setState(() => _selectedIndex = index);
        if (Navigator.canPop(context)) Navigator.pop(context);
      },
      excludeIndices: const [1, 3, 5, 11, 12], 
    );

    if (_selectedIndex == 0) {
      return Scaffold(
        backgroundColor: backgroundWhite,
        appBar: AppBar(
          title: const Text("Admin Console", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: customRed,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            NotificationBadge(
              child: const Icon(Icons.notifications),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
              },
            ),
            const SizedBox(width: 10),
          ],
        ),
        drawer: sideMenu,
        body: Column(
          children: [
            // Header remains static at the top
            Container(
              padding: const EdgeInsets.only(bottom: 25),
              decoration: BoxDecoration(
                color: customRed,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Quick Actions",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Row(
                      children: [
                        _buildQuickAction(Icons.settings_suggest, "Fee Setup", 3),

                        _buildQuickAction(Icons.analytics, "Analytics", 12),
                        _buildQuickAction(Icons.payment, "Methods", 11),
                        _buildQuickAction(Icons.calendar_month, "Acd. Year", 5),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // SWIPEABLE AREA
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _bottomNavIndex = index);
                },
                children: const [
                  PaymentListTab(isPending: true),
                  PaymentListTab(isPending: false),
                  AdminStudentList(),
                  AdminStaffList(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
          ),
          child: BottomNavigationBar(
            currentIndex: _bottomNavIndex,
            onTap: (index) {
              setState(() => _bottomNavIndex = index);
              // Animate to the page when a bottom icon is tapped
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            selectedItemColor: customRed,
            unselectedItemColor: Colors.grey[500],
            showUnselectedLabels: true,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.notifications_active_rounded), label: 'Pending'),
              BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: 'History'),
              BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'Students'),
              BottomNavigationBarItem(icon: Icon(Icons.work_rounded), label: 'Staffs'),
            ],
          ),
        ),
      );
    }

    // Sub-Pages
    Widget content;
    switch (_selectedIndex) {
      case 1: content = UserApprovalScreen(drawer: sideMenu); break;
      case 2: content = OverduePaymentsScreen(drawer: sideMenu); break;
      case 3: content = FeeSetupScreen(drawer: sideMenu); break;
      case 4: content = ViewFeesScreen(drawer: sideMenu); break;
      case 5: content = AcademicYearScreen(drawer: sideMenu); break;
      case 6: content = DepartmentScreen(drawer: sideMenu); break;
      case 7: content = QuotaScreen(drawer: sideMenu); break;
      case 8: content = AdminStudentDatabase(drawer: sideMenu); break; 
      case 9: content = AdminStaffDatabase(drawer: sideMenu); break;
      case 10: content = ProfileScreen(drawer: sideMenu, showLogout: false); break;
      case 11: content = ManagePaymentMethodsScreen(drawer: sideMenu); break;
      case 12: content = AdminAnalyticsScreen(drawer: sideMenu); break;
      case 13: content = AdminNoDueRequestsScreen(drawer: sideMenu); break;
      case 14: content = SupportInboxScreen(drawer: sideMenu); break;
      default: content = const Center(child: Text("Page not found"));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() => _selectedIndex = 0);
      },
      child: content,
    ); 
  }

  Widget _buildQuickAction(IconData icon, String label, int index) {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        width: 85,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: customRed.withOpacity(0.1),
              radius: 22,
              child: Icon(icon, color: customRed, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1),
          ],
        ),
      ),
    );
  }
}