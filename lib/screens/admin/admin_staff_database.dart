import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminStaffDatabase extends StatefulWidget {
  final Widget? drawer;
  const AdminStaffDatabase({super.key, this.drawer});

  @override
  State<AdminStaffDatabase> createState() => _AdminStaffDatabaseState();
}

class _AdminStaffDatabaseState extends State<AdminStaffDatabase> {
  // Professional Red Color
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  bool _isUploading = false;
  List<List<dynamic>> _csvData = [];
  int _successCount = 0;
  int _failCount = 0;

  // Manual Entry Controllers
  final _empIdCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();

  Future<void> _pickAndParseCSV() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        if (kIsWeb) {
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
    
    final batchSize = 400; 
    List<List<dynamic>> chunks = [];
    for (var i = 1; i < _csvData.length; i += batchSize) { 
       chunks.add(_csvData.sublist(i, i + batchSize > _csvData.length ? _csvData.length : i + batchSize));
    }

    int uploaded = 0;
    int failed = 0;

    for (var chunk in chunks) {
      final batch = FirebaseFirestore.instance.batch();
      
      for (var row in chunk) {
        // Expected Format: EmpID, Name, Mobile, Dept
        if (row.length < 4) {
          failed++;
          continue;
        }

        String empId = row[0].toString().trim();
        String name = row[1].toString().trim();
        String mobile = row[2].toString().trim(); 
        String dept = row[3].toString().trim();

        if (empId.isEmpty || mobile.isEmpty) {
          failed++;
          continue;
        }

        if (!mobile.contains('+')) {
           mobile = '+91$mobile'; 
        }

        DocumentReference docRef = FirebaseFirestore.instance.collection('staff_master_list').doc(empId);
        batch.set(docRef, {
          'employeeId': empId,
          'name': name,
          'phone': mobile,
          'dept': dept,
          'isRegistered': false, 
          'updatedAt': FieldValue.serverTimestamp(),
        });
        uploaded++;
      }
      
      await batch.commit();
    }

    setState(() {
      _isUploading = false;
      _successCount = uploaded;
      _failCount = failed;
      _csvData = []; 
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Upload Complete: $uploaded added, $failed failed/skipped")),
    );
  }

  Future<void> _addManualEntry() async {
    if (_empIdCtrl.text.isEmpty || _mobileCtrl.text.isEmpty) return;
    
    try {
      String mobile = _mobileCtrl.text.trim();
      if (!mobile.startsWith('+')) mobile = "+91$mobile";

      await FirebaseFirestore.instance.collection('staff_master_list').doc(_empIdCtrl.text.trim()).set({
        'employeeId': _empIdCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'phone': mobile,
        'dept': _deptCtrl.text.trim(),
        'isRegistered': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _empIdCtrl.clear();
      _mobileCtrl.clear();
      _nameCtrl.clear();
      _deptCtrl.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Staff Added Successfully")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Staff Master Database"),
        backgroundColor: customRed,
        foregroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      drawer: widget.drawer,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // MANUAL ENTRY CARD
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: customRed.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_add_alt_1, color: customRed, size: 28),
                        const SizedBox(width: 10),
                        const Text(
                          "Add Single Staff Member",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                         Expanded(
                           child: _buildTextField(_empIdCtrl, "Employee ID"),
                         ),
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
                                 decoration: _inputDecoration("Dept"),
                                 items: depts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                                 onChanged: (val) {
                                   if (val != null) setState(() => _deptCtrl.text = val);
                                 },
                               );
                             }
                           ),
                         ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                         Expanded(
                           child: _buildTextField(_nameCtrl, "Full Name"),
                         ),
                         const SizedBox(width: 10),
                         Expanded(
                           child: _buildTextField(_mobileCtrl, "Mobile (+91...)"),
                         ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _addManualEntry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: customRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        child: const Text("Add Staff", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),

            // BULK UPLOAD CARD
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: customRed.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_upload_outlined, color: customRed, size: 28),
                        const SizedBox(width: 10),
                        const Text(
                          "Bulk Import from CSV",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: customRed.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        "Format: EmpID, Name, Mobile, Dept",
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isUploading ? null : _pickAndParseCSV,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text("Select CSV File"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: customRed,
                          side: BorderSide(color: customRed),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    
                    if (_csvData.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: customRed.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "Preview: Found ${_csvData.length - 1} records (excluding header)",
                          style: TextStyle(fontWeight: FontWeight.w500, color: customRed),
                        ),
                      ),
                      Container(
                        height: 150,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView.builder(
                          itemCount: _csvData.length > 5 ? 5 : _csvData.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              title: Text(
                                _csvData[index].join(', '),
                                style: const TextStyle(fontSize: 12),
                              ),
                              dense: true,
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isUploading ? null : _uploadToFirestore,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: customRed,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 2,
                          ),
                          child: _isUploading 
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("UPLOAD TO DATABASE", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                    
                    if (_successCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, color: Colors.green[700]),
                              const SizedBox(width: 8),
                              Text(
                                "Success: $_successCount, Failed: $_failCount",
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      decoration: _inputDecoration(label),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: customRed, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}
