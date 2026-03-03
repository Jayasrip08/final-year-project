import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminStudentDatabase extends StatefulWidget {
  final Widget? drawer;
  const AdminStudentDatabase({super.key, this.drawer});

  @override
  State<AdminStudentDatabase> createState() => _AdminStudentDatabaseState();
}

class _AdminStudentDatabaseState extends State<AdminStudentDatabase> {
  bool _isUploading = false;
  List<List<dynamic>> _csvData = [];
  int _successCount = 0;
  int _failCount = 0;

  // Manual Entry Controllers
  final _regNoCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();

  String? _manualQuota;
  String? _manualBatch; // NEW

  Future<void> _pickAndParseCSV() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        if (kIsWeb) {
          // Web: Use bytes
          final bytes = result.files.single.bytes;
          if (bytes != null) {
             final decoded = utf8.decode(bytes);
             final fields = const CsvToListConverter().convert(decoded);
             setState(() {
               _csvData = fields;
               _successCount = 0;
               _failCount = 0;
             });
          }
        } else {
          // Mobile/Desktop: Use path
          File file = File(result.files.single.path!);
          final input = file.openRead();
          final fields = await input.transform(utf8.decoder).transform(const CsvToListConverter()).toList();

          setState(() {
            _csvData = fields;
            _successCount = 0;
            _failCount = 0;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error picking file: $e")));
    }
  }

  Future<void> _uploadToFirestore() async {
    if (_csvData.isEmpty) return;

    setState(() => _isUploading = true);
    
    final batchSize = 400; // Firestore batch limit is 500
    List<List<dynamic>> chunks = [];
    for (var i = 1; i < _csvData.length; i += batchSize) { // Skip header row 0
       chunks.add(_csvData.sublist(i, i + batchSize > _csvData.length ? _csvData.length : i + batchSize));
    }

    int uploaded = 0;
    int failed = 0;

    for (var chunk in chunks) {
      final batch = FirebaseFirestore.instance.batch();
      
      for (var row in chunk) {

        // Expected Format: RegNo, Name, Mobile, Dept, Quota, Batch (All Required)
        if (row.length < 6) {
          failed++;
          continue;
        }

        String regNo = row[0].toString().trim();
        String name = row[1].toString().trim();
        String mobile = row[2].toString().trim(); 
        String dept = row[3].toString().trim();
        String quota = row[4].toString().trim();
        String studentBatch = row[5].toString().trim(); // RENAMED from batch to studentBatch
        
        // Optional Columns
        String? type = row.length > 6 ? row[6].toString().trim() : null; // Hosteller/Day Scholar

        if (regNo.isEmpty || name.isEmpty || mobile.isEmpty || dept.isEmpty || quota.isEmpty || studentBatch.isEmpty) {
          failed++;
          continue;
        }

        if (!mobile.contains('+')) {
           mobile = '+91$mobile'; 
        }

        Map<String, dynamic> studentData = {
          'regNo': regNo,
          'name': name,
          'phone': mobile,
          'dept': dept,

          'quota': quota, // Required
          'batch': studentBatch, // Required
          'isRegistered': false, 
          'updatedAt': FieldValue.serverTimestamp(),
        };
        
        if (type != null && type.isNotEmpty) studentData['type'] = type;

        DocumentReference docRef = FirebaseFirestore.instance.collection('student_master_list').doc(regNo);
        batch.set(docRef, studentData);
        uploaded++;
      }
      
      await batch.commit();
    }

    setState(() {
      _isUploading = false;
      _successCount = uploaded;
      _failCount = failed;
      _csvData = []; // Clear after upload
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Upload Complete: $uploaded added, $failed failed/skipped")),
    );
  }

  Future<void> _addManualEntry() async {
    if (_regNoCtrl.text.isEmpty || _mobileCtrl.text.isEmpty) return;
    
    try {
      String mobile = _mobileCtrl.text.trim();
      if (!mobile.startsWith('+')) mobile = "+91$mobile";

      await FirebaseFirestore.instance.collection('student_master_list').doc(_regNoCtrl.text.trim()).set({
        'regNo': _regNoCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'phone': mobile,
        'dept': _deptCtrl.text.trim(),

        'quota': _manualQuota ?? '',
        'batch': _manualBatch ?? '', // NEW
        'isRegistered': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _regNoCtrl.clear();
      _mobileCtrl.clear();
      _nameCtrl.clear();
      _deptCtrl.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Student Added Successfully")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Student Master Database")),
      drawer: widget.drawer,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // MANUAL ENTRY CARD
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text("Add Single Student", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                         Expanded(child: TextField(controller: _regNoCtrl, decoration: const InputDecoration(labelText: "Reg No"))),
                         const SizedBox(width: 10),
                         Expanded(
                           child: StreamBuilder<QuerySnapshot>(
                             stream: FirebaseFirestore.instance.collection('departments').orderBy('name').snapshots(),
                             builder: (context, snapshot) {
                               List<String> depts = [];
                               if (snapshot.hasData) {
                                 depts = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                               }
                               return DropdownButtonFormField<String>(
                                 value: _deptCtrl.text.isNotEmpty && depts.contains(_deptCtrl.text) ? _deptCtrl.text : null,
                                 decoration: const InputDecoration(labelText: "Dept"),
                                 items: depts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                                 onChanged: (val) {
                                   if (val != null) setState(() => _deptCtrl.text = val);
                                 },
                                 validator: (val) => val == null ? "Required" : null,
                               );
                             }
                           ),
                         ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('quotas').orderBy('name').snapshots(),
                      builder: (context, snapshot) {
                        List<String> quotas = [];
                        if (snapshot.hasData) {
                          quotas = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                        }
                        return DropdownButtonFormField<String>(
                          value: _manualQuota,
                          decoration: const InputDecoration(labelText: "Quota (Required)", border: OutlineInputBorder()),
                          items: quotas.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (val) => setState(() => _manualQuota = val), 
                          validator: (val) => val == null ? "Required" : null,
                        );
                      }

                    ),

                    const SizedBox(height: 10),

                    // BATCH DROPDOWN
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('academic_years').where('isActive', isEqualTo: true).snapshots(),
                      builder: (context, snapshot) {
                        List<String> batches = [];
                        if (snapshot.hasData) {
                          batches = snapshot.data!.docs.map((d) => d['name'] as String).toList();
                          batches.sort(); // Sort client-side to avoid composite index requirement
                        }
                        return DropdownButtonFormField<String>(
                          value: _manualBatch,
                          decoration: const InputDecoration(labelText: "Batch (Required)", border: OutlineInputBorder()),
                          items: batches.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (val) => setState(() => _manualBatch = val), 
                          validator: (val) => val == null ? "Required" : null,
                        );
                      }
                    ),

                    const SizedBox(height: 10),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                         Expanded(child: TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Name"))),
                         const SizedBox(width: 10),
                         Expanded(child: TextField(controller: _mobileCtrl, decoration: const InputDecoration(labelText: "Mobile (+91...)"))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _addManualEntry,
                      child: const Text("Add Student"),
                    )
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),

            // BULK UPLOAD CARD
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.upload_file, size: 40, color: Colors.blue),
                    const SizedBox(height: 10),
                    const Text("Bulk Import from CSV", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Text("Format: RegNo, Name, Mobile, Dept, Quota, Batch", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isUploading ? null : _pickAndParseCSV,
                      icon: const Icon(Icons.folder_open),
                      label: const Text("Select CSV File"),
                    ),
                    
                    if (_csvData.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text("Preview: Found ${_csvData.length - 1} records (excluding header)"),
                      Container(
                        height: 150,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                        child: ListView.builder(
                          itemCount: _csvData.length > 5 ? 5 : _csvData.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              title: Text(_csvData[index].join(', ')),
                              dense: true,
                            );
                          },
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _isUploading ? null : _uploadToFirestore,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        child: _isUploading 
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("UPLOAD TO DATABASE"),
                      ),
                    ],
                    
                    if (_successCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text("Success: $_successCount, Failed: $_failCount", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
