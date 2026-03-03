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
import 'admin_analytics_screen.dart'; // NEW
import 'admin_nodue_requests.dart'; // NEW

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // We pass the side menu to child screens so they can use it in their Scaffolds
    final sideMenu = AdminSideMenu(
      selectedIndex: _selectedIndex,
      onItemSelected: (index) => setState(() => _selectedIndex = index),
    );

    // Dashboard Home View
    if (_selectedIndex == 0) {
      return DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text("Admin Console"),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            actions: [
            NotificationBadge(
              child: const Icon(Icons.notifications),
              onTap: () {
                 Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
              },
            ),
            ],
            bottom: const TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(text: "Pending", icon: Icon(Icons.notifications_active)),
                Tab(text: "History", icon: Icon(Icons.history)),
                Tab(text: "Students", icon: Icon(Icons.people)), 
                Tab(text: "Staffs", icon: Icon(Icons.work)), 
              ],
            ),
          ),
          drawer: sideMenu,
          body: const TabBarView(
            children: [
              PaymentListTab(isPending: true),
              PaymentListTab(isPending: false),
              AdminStudentList(),
              AdminStaffList(),
            ],
          ),
        ),
      );
    }

    // Sub-Pages
    // We pass the 'sideMenu' to these screens. They need to be updated to accept it.
    // For now, if they don't accept it, they will just show a back arrow or no menu.
    // I will dynamically return the widget based on index.
    
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
      case 9: content = AdminStaffDatabase(drawer: sideMenu); break; // NEW
      case 10: content = ProfileScreen(drawer: sideMenu, showLogout: false); break;
      case 11: content = ManagePaymentMethodsScreen(drawer: sideMenu); break;
      case 12: content = AdminAnalyticsScreen(drawer: sideMenu); break; // NEW
      case 13: content = AdminNoDueRequestsScreen(drawer: sideMenu); break; // NEW
      default: content = const Center(child: Text("Page not found"));
    }

    // Wrap in a Scaffold if you want to enforce the Drawer here, 
    // BUT the child screens are likely Scaffolds themselves.
    // If we wrap them, we get double Scaffolds.
    // If we don't wrap them, we lose the Drawer unless we pass it.
    // For this refactor, I will attempt to inject the drawer via Constructor injection
    // But since I haven't updated them yet, I'll return them as is, 
    // AND I will use a special wrapper to ensure the side menu is accessible 
    // even if the child screen doesn't have a drawer property yet (by using a Stack or key hack? No.)
    
    // Proper way: Update the screens.
    // I strongly assume the next step is to update DepartmentScreen etc.
    return content; 
  }
}
