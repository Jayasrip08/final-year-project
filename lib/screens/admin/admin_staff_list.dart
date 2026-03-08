import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_edit_staff.dart';

class AdminStaffList extends StatefulWidget {
  const AdminStaffList({super.key});

  @override
  State<AdminStaffList> createState() => _AdminStaffListState();
}

class _AdminStaffListState extends State<AdminStaffList> {
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  
  String? _selectedDept;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // CONTROLS AREA
        Container(
          padding: const EdgeInsets.all(16.0),
          color: Colors.grey[50],
          child: Column(
            children: [
              // Search Bar
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: "Search Staff by Name",
                  prefixIcon: Icon(Icons.search, color: customRed),
                  suffixIcon: _searchQuery.isNotEmpty 
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = "");
                        },
                      ) 
                    : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: customRed, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              ),
              const SizedBox(height: 12),
              
              // Filters Row
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('departments').orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  List<String> depts = [];
                  if (snapshot.hasData) {
                    depts = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                  }

                  return DropdownButtonFormField<String>(
                    value: _selectedDept,
                    decoration: InputDecoration(
                      labelText: "Filter by Department",
                      labelStyle: TextStyle(color: Colors.grey[600]),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: customRed, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    icon: Icon(Icons.arrow_drop_down, color: customRed),
                    items: [
                      const DropdownMenuItem(value: null, child: Text("All Departments")),
                      ...depts.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                    ],
                    onChanged: (val) => setState(() => _selectedDept = val),
                  );
                }
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: (() {
              Query query = FirebaseFirestore.instance
                  .collection('users')
                  .where('role', whereIn: ['staff', 'hod']);
              
              if (_selectedDept != null) {
                query = query.where('dept', isEqualTo: _selectedDept);
              }
              
              return query.snapshots();
            })(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        "No staff members found.",
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              // Client-side Filter
              var docs = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                String name = (data['name'] ?? '').toString().toLowerCase();
                String dept = (data['dept'] ?? '');
                
                bool matchSearch = name.contains(_searchQuery);
                bool matchDept = _selectedDept == null || dept == _selectedDept;
                
                return matchSearch && matchDept;
              }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.filter_list_off, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        "No matching staff found",
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var doc = docs[index];
                  var data = doc.data() as Map<String, dynamic>;
                  String role = data['role'] ?? 'staff';

                  String subtitleText;
                  if (role == 'admin') {
                    subtitleText = (data['dept'] != null && data['dept'].toString().isNotEmpty) 
                        ? "ADMIN | ${data['dept']}" 
                        : "ADMIN";
                  } else {
                    subtitleText = "${role.toUpperCase()} | ${data['dept'] ?? 'Gen'}";
                  }

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: customRed.withOpacity(0.2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: role == 'admin' 
                                  ? customRed.withOpacity(0.1)
                                  : Colors.teal.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                role == 'admin' ? Icons.admin_panel_settings : Icons.person,
                                color: role == 'admin' ? customRed : Colors.teal,
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitleText,
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.email_outlined, size: 14, color: customRed.withOpacity(0.7)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        data['email'] ?? 'No email',
                                        style: TextStyle(fontSize: 12, color: customRed.withOpacity(0.7)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.phone_outlined, size: 14, color: Colors.green[700]),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Phone: ${data['phone'] ?? 'N/A'}",
                                      style: TextStyle(fontSize: 12, color: Colors.green[700]),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Edit button
                          IconButton(
                            icon: Icon(Icons.edit, color: customRed),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdminEditStaff(
                                    staffData: data,
                                    staffId: doc.id,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}