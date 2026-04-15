import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../login_screen.dart';

class AdminSideMenu extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final List<int> excludeIndices;

  const AdminSideMenu({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.excludeIndices = const [],
  });

  @override
  State<AdminSideMenu> createState() => _AdminSideMenuState();
}

class _AdminSideMenuState extends State<AdminSideMenu> {
  // PROFESSIONAL RED THEME COLOR
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: customRed),
            accountName: const Text("Admin Console", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            accountEmail: const Text("Manage your institution"),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.admin_panel_settings, size: 30, color: Color.fromARGB(255, 198, 55, 45)),
            ),
          ),
          
          // Dashboard is always visible at index 0
          _buildNavItem(context, 0, "Dashboard", Icons.dashboard, customRed),
          const Divider(),

          // Main Management
          _buildNavItem(context, 2, "Overdue Payments", Icons.warning, customRed),
          _buildNavItem(context, 12, "Income Analytics", Icons.analytics, customRed),
          _buildNavItem(context, 13, "No-Due Requests", Icons.verified_user, customRed),
          _buildNavItem(context, 1, "User Approvals", Icons.how_to_reg, customRed),
          _buildNavItem(context, 14, "Support Tickets", Icons.confirmation_number_rounded, customRed),
          
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text("Fee Management", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          _buildNavItem(context, 3, "Set New Fee", Icons.add_circle, customRed),
          _buildNavItem(context, 4, "View Fee Structures", Icons.visibility, customRed),
          _buildNavItem(context, 11, "Payment Settings", Icons.account_balance, customRed),
          
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text("Configuration", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          _buildNavItem(context, 5, "Academic Years", Icons.calendar_today, customRed),
          _buildNavItem(context, 6, "Departments", Icons.business, customRed),
          _buildNavItem(context, 7, "Student Quotas", Icons.pie_chart, customRed),
          _buildNavItem(context, 8, "Student Database", Icons.contact_phone, customRed),
          _buildNavItem(context, 9, "Staff Database", Icons.contact_mail, customRed),
          
          const Divider(),
          _buildNavItem(context, 10, "My Profile", Icons.person, customRed),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context, 
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// Builds a Nav Item only if its index is NOT in the excludeIndices list
  Widget _buildNavItem(BuildContext context, int index, String title, IconData icon, Color color) {
    // Logic to hide options already available in Quick Actions
    if (widget.excludeIndices.contains(index)) {
      return const SizedBox.shrink();
    }

    bool isSelected = widget.selectedIndex == index;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? customRed.withOpacity(0.1) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        leading: Icon(icon, color: isSelected ? customRed : Colors.blueGrey[700]),
        title: Text(
          title, 
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? customRed : Colors.black87,
            fontSize: 14,
          )
        ),
        onTap: () {
          // If the menu item is clicked, we update the parent state
          widget.onItemSelected(index);
        },
      ),
    );
  }
}