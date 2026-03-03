import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_edit_student.dart';

class AdminStudentList extends StatefulWidget {
  const AdminStudentList({super.key});

  @override
  State<AdminStudentList> createState() => _AdminStudentListState();
}

class _AdminStudentListState extends State<AdminStudentList> {
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
          padding: const EdgeInsets.all(12.0),
          color: Colors.grey[50],
          child: Column(
            children: [
              // Search Bar
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: "Search by Name or RegNo",
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
                          value: depts.contains(_selectedDept) ? _selectedDept : null,
                          decoration: InputDecoration(
                            labelText: "Department",
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text("All Depts")),
                            ...depts.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                          ],
                          onChanged: (val) => setState(() => _selectedDept = val),
                        );
                      }
                    ),
                  ),
                  const SizedBox(width: 10),
                  
                  // Batch Filter (Fetching from academic_years)
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('academic_years').snapshots(),
                      builder: (context, snapshot) {
                        List<String> batches = [];
                        if (snapshot.hasData) {
                          batches = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                          batches.sort((a, b) => b.compareTo(a)); // Newest first
                        }
                        return DropdownButtonFormField<String>(
                          value: _selectedBatch,
                          decoration: InputDecoration(
                            labelText: "Batch",
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            fillColor: Colors.white,
                            filled: true,
                          ),
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
              
              // Note: Case-insensitive search requires a helper library or normalized fields.
              // We'll keep search and batch filtering client-side for now, or suggest indexing.
              return query.snapshots();
            })(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No students registered."));
              }

              // Client-side Filter
              var docs = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                String name = (data['name'] ?? '').toString().toLowerCase();
                String regNo = (data['regNo'] ?? '').toString().toLowerCase();
                String dept = (data['dept'] ?? '');
                String batch = (data['batch'] ?? '');

                // 1. Search Filter
                bool matchSearch = name.contains(_searchQuery) || regNo.contains(_searchQuery);
                
                // 2. Dept Filter
                bool matchDept = _selectedDept == null || dept == _selectedDept;

                // 3. Batch Filter
                bool matchBatch = _selectedBatch == null || batch == _selectedBatch;

                return matchSearch && matchDept && matchBatch;
              }).toList();

              if (docs.isEmpty) {
                 return const Center(child: Text("No matching students found"));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var doc = docs[index];
                  var data = doc.data() as Map<String, dynamic>;

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo.shade100,
                        child: Text(
                          (data['name'] ?? '?')[0].toUpperCase(),
                          style: TextStyle(color: Colors.indigo.shade900),
                        ),
                      ),
                      title: Text(data['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${data['regNo']} | ${data['dept']} | ${data['batch']}"),
                          Text("Email: ${data['email'] ?? 'No email'}", style: TextStyle(fontSize: 12, color: Colors.indigo.shade300)),
                          Text("Parent: ${data['parentPhoneNumber'] ?? 'N/A'}", style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
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
