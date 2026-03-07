import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_edit_student.dart';

class AdminStudentList extends StatefulWidget {
  const AdminStudentList({super.key});

  @override
  State<AdminStudentList> createState() => _AdminStudentListState();
}

class _AdminStudentListState extends State<AdminStudentList> {
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  
  String? _selectedDept;
  String? _selectedBatch;

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
                  hintText: "Search by Name or RegNo",
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
              Row(
                children: [
                  // Dept Filter (Dynamic)
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('departments').orderBy('name').snapshots(),
                      builder: (context, snapshot) {
                        List<String> depts = [];
                        if (snapshot.hasData) {
                          depts = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                        }
                        
                        return DropdownButtonFormField<String>(
                          value: _selectedDept,
                          decoration: InputDecoration(
                            labelText: "Department",
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
                  ),
                  const SizedBox(width: 10),
                  
                  // Batch Filter
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('academic_years').snapshots(),
                      builder: (context, snapshot) {
                        List<String> batches = [];
                        if (snapshot.hasData) {
                          batches = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                          batches.sort((a, b) => b.compareTo(a));
                        }
                        return DropdownButtonFormField<String>(
                          value: _selectedBatch,
                          decoration: InputDecoration(
                            labelText: "Batch",
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
                            const DropdownMenuItem(value: null, child: Text("All Batches")),
                            ...batches.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                          ],
                          onChanged: (val) => setState(() => _selectedBatch = val),
                        );
                      }
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: (() {
              Query query = FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'student');
              
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
                        "No students registered.",
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              var docs = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                String name = (data['name'] ?? '').toString().toLowerCase();
                String regNo = (data['regNo'] ?? '').toString().toLowerCase();
                String dept = (data['dept'] ?? '');
                String batch = (data['batch'] ?? '');

                bool matchSearch = name.contains(_searchQuery) || regNo.contains(_searchQuery);
                bool matchDept = _selectedDept == null || dept == _selectedDept;
                bool matchBatch = _selectedBatch == null || batch == _selectedBatch;

                return matchSearch && matchDept && matchBatch;
              }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.filter_list_off, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        "No matching students found",
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
                              color: customRed.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                (data['name'] ?? '?')[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: customRed,
                                ),
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
                                  "${data['regNo']} | ${data['dept']} | ${data['batch']}",
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
                                      "Parent: ${data['parentPhoneNumber'] ?? 'N/A'}",
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
                                  builder: (_) => AdminEditStudent(
                                    studentData: data,
                                    studentId: doc.id,
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