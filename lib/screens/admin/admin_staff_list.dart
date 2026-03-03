import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_edit_staff.dart';

class AdminStaffList extends StatefulWidget {
  const AdminStaffList({super.key});

  @override
  State<AdminStaffList> createState() => _AdminStaffListState();
}

class _AdminStaffListState extends State<AdminStaffList> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  
  String? _selectedDept;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // CONTROLS AREA
        Container(
          padding: const EdgeInsets.all(12.0),
          color: Colors.grey[50],
          child: Column(
            children: [
              // Search Bar
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: "Search Staff by Name",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty 
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = "");
                      }) 
                    : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              ),
              const SizedBox(height: 10),
              
              // Filters Row
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('departments').orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  List<String> depts = [];
                  if (snapshot.hasData) {
                    depts = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                  }

                  return DropdownButtonFormField<String>(
                    value: depts.contains(_selectedDept) ? _selectedDept : null,
                    decoration: InputDecoration(
                      labelText: "Filter by Department",
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      fillColor: Colors.white,
                      filled: true,
                    ),
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
                return const Center(child: Text("No staff members found."));
              }

              // Client-side Filter
              var docs = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                String name = (data['name'] ?? '').toString().toLowerCase();
                String dept = (data['dept'] ?? '');
                
                // 1. Search Filter
                bool matchSearch = name.contains(_searchQuery);
                
                // 2. Dept Filter
                bool matchDept = _selectedDept == null || dept == _selectedDept;
                
                return matchSearch && matchDept;
              }).toList();

              if (docs.isEmpty) {
                 return const Center(child: Text("No matching staff found"));
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
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: role == 'admin' ? Colors.red.shade100 : Colors.teal.shade100,
                        child: Icon(
                          role == 'admin' ? Icons.admin_panel_settings : Icons.person, 
                          color: role == 'admin' ? Colors.red.shade900 : Colors.teal.shade900
                        ),
                      ),
                      title: Text(data['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subtitleText),
                          Text("${data['email'] ?? 'No email'}", style: TextStyle(fontSize: 12, color: Colors.teal.shade300)),
                          Text("Phone: ${data['phone'] ?? 'N/A'}", style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
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
