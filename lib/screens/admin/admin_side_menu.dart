import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../login_screen.dart';

class AdminSideMenu extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const AdminSideMenu({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Colors.indigo),
            accountName: Text("Admin Console", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            accountEmail: Text("Manage your institution"),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.admin_panel_settings, size: 30, color: Colors.indigo),
            ),
          ),
          _buildNavItem(context, 0, "Dashboard", Icons.dashboard, Colors.indigo),
          const Divider(),
          _buildNavItem(context, 2, "Overdue Payments", Icons.warning, Colors.redAccent),
          _buildNavItem(context, 12, "Income Analytics", Icons.analytics, Colors.indigoAccent),
          _buildNavItem(context, 13, "No-Due Requests", Icons.verified_user, Colors.teal),
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text("Fee Management", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          _buildNavItem(context, 3, "Set New Fee", Icons.add_circle, Colors.blueAccent),
          _buildNavItem(context, 4, "View Fee Structures", Icons.visibility, Colors.purpleAccent),
          _buildNavItem(context, 11, "Payment Settings", Icons.account_balance, Colors.green), // NEW
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text("Configuration", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          _buildNavItem(context, 5, "Academic Years", Icons.calendar_today, Colors.teal),
          _buildNavItem(context, 6, "Departments", Icons.business, Colors.indigo),
          _buildNavItem(context, 7, "Student Quotas", Icons.pie_chart, Colors.teal),
          _buildNavItem(context, 8, "Student Database", Icons.contact_phone, Colors.blueGrey), // NEW
          _buildNavItem(context, 9, "Staff Database", Icons.contact_mail, Colors.brown), // NEW
          const Divider(),
          _buildNavItem(context, 10, "My Profile", Icons.person, Colors.indigo),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, String title, IconData icon, Color color) {
    bool isSelected = selectedIndex == index;
    return Container(
      color: isSelected ? Colors.indigo.withOpacity(0.1) : null,
      child: ListTile(
        leading: Icon(icon, color: isSelected ? Colors.indigo : color),
        title: Text(
          title, 
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.indigo : null,
          )
        ),
        onTap: () {
          Navigator.pop(context); // Close drawer
          onItemSelected(index);
        },
      ),
    );
  }
}
