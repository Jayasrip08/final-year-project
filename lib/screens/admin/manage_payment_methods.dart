import 'dart:io';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class ManagePaymentMethodsScreen extends StatefulWidget {
  final Widget? drawer; // NEW
  const ManagePaymentMethodsScreen({super.key, this.drawer});

  @override
  State<ManagePaymentMethodsScreen> createState() => _ManagePaymentMethodsScreenState();
}

class _ManagePaymentMethodsScreenState extends State<ManagePaymentMethodsScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: widget.drawer, // NEW
      appBar: AppBar(
        title: const Text("Manage Payment Details"),
        backgroundColor: Colors.indigo,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white, // Changed "blue pulse" (plus) to white
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('payment_methods').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.account_balance_wallet_outlined, size: 80, color: Colors.grey[400]),
                   const SizedBox(height: 16),
                   const Text("No Payment Details Added", style: TextStyle(color: Colors.grey, fontSize: 18)),
                   const Text("Tap + to add bank/UPI details for fees", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final feeType = doc.id.replaceAll('_', ' '); // Restore space for display? Or use stored name. No, ID is sanitized.
              
              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: data['qrCodeUrl'] != null 
                     ? Image.network(data['qrCodeUrl'], width: 50, height: 50, fit: BoxFit.cover)
                     : const Icon(Icons.qr_code_2, size: 40, color: Colors.indigo),
                  title: Text(data['feeType'] ?? feeType, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       if (data['bankName'] != null) Text("${data['bankName']} • ${data['accountNumber']}"),
                       if (data['upiId'] != null) Text("UPI: ${data['upiId']}"),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showAddEditDialog(doc: doc)),
                       IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteMethod(doc.id)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _deleteMethod(String id) async {
    final confirm = await showDialog<bool>(
       context: context, 
       builder: (ctx) => AlertDialog(
         title: const Text("Delete Payment Method"),
         content: const Text("Are you sure? Students will no longer see these payment details."),
         actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("Delete")),
         ],
       )
    );
    if (confirm == true) {
       await FirebaseFirestore.instance.collection('payment_methods').doc(id).delete();
    }
  }

  void _showAddEditDialog({DocumentSnapshot? doc}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddEditPaymentDialog(doc: doc),
    );
  }
}

class _AddEditPaymentDialog extends StatefulWidget {
  final DocumentSnapshot? doc;
  const _AddEditPaymentDialog({this.doc});

  @override
  State<_AddEditPaymentDialog> createState() => _AddEditPaymentDialogState();
}

class _AddEditPaymentDialogState extends State<_AddEditPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _feeTypeCtrl = TextEditingController();
  final _accNameCtrl = TextEditingController();
  final _accNumCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  
  XFile? _imageFile;
  String? _existingImageUrl;
  bool _isUploading = false;
  
  final List<String> _predefinedFees = ['Tuition Fee', 'Bus Fee', 'Hostel Fee', 'Exam Fee', 'Association Fee', 'Library Fee', 'Book Fee'];

  @override
  void initState() {
    super.initState();
    if (widget.doc != null) {
      final data = widget.doc!.data() as Map<String, dynamic>;
      _feeTypeCtrl.text = data['feeType'] ?? '';
      _accNameCtrl.text = data['accountName'] ?? '';
      _accNumCtrl.text = data['accountNumber'] ?? '';
      _ifscCtrl.text = data['ifsc'] ?? '';
      _bankCtrl.text = data['bankName'] ?? '';
      _upiCtrl.text = data['upiId'] ?? '';
      _existingImageUrl = data['qrCodeUrl'];
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null) setState(() => _imageFile = file);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isUploading = true);
    try {
       String? qrUrl = _existingImageUrl;
       
       // Upload Image if new one picked
       if (_imageFile != null) {
          final ref = FirebaseStorage.instance.ref().child('payment_qrs/${DateTime.now().millisecondsSinceEpoch}.jpg');
          if (kIsWeb) {
             await ref.putData(await _imageFile!.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
          } else {
             await ref.putFile(File(_imageFile!.path));
          }
          qrUrl = await ref.getDownloadURL();
       }

       final feeType = _feeTypeCtrl.text.trim();
       final docId = feeType; // Use Exact Fee Type Name as ID (e.g. "Tuition Fee")
       
       await FirebaseFirestore.instance.collection('payment_methods').doc(docId).set({
          'feeType': feeType,
          'accountName': _accNameCtrl.text.trim(),
          'accountNumber': _accNumCtrl.text.trim(),
          'ifsc': _ifscCtrl.text.trim(),
          'bankName': _bankCtrl.text.trim(),
          'upiId': _upiCtrl.text.trim(),
          'qrCodeUrl': qrUrl,
          'updatedAt': FieldValue.serverTimestamp(),
       });
       
       if (mounted) Navigator.pop(context);
    } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
       if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
            Text(widget.doc == null ? "Add Payment Method" : "Edit Payment Method"),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ],
      ),
      content: SizedBox(
        width: 500, // Improved width for web
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fee Type (Dropdown)
                DropdownButtonFormField<String>(
                  value: _predefinedFees.contains(_feeTypeCtrl.text) || _feeTypeCtrl.text == "All Fees (Default)" 
                      ? _feeTypeCtrl.text 
                      : null,
                  decoration: const InputDecoration(labelText: "Fee Name *", border: OutlineInputBorder()),
                  items: [
                     const DropdownMenuItem(value: "All Fees (Default)", child: Text("All Fees (Default)")),
                     ..._predefinedFees.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _feeTypeCtrl.text = val);
                  },
                  validator: (v) => v == null || v.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),
                
                // Bank Details Group
                const Text("Bank Details", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 8),
                TextFormField(controller: _accNameCtrl, decoration: const InputDecoration(labelText: "Account Holder Name", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextFormField(controller: _accNumCtrl, decoration: const InputDecoration(labelText: "Account Number", border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: _ifscCtrl, decoration: const InputDecoration(labelText: "IFSC Code", border: OutlineInputBorder()))),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _bankCtrl, decoration: const InputDecoration(labelText: "Bank Name", border: OutlineInputBorder())),
                
                const SizedBox(height: 16),
                const Text("UPI & QR", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 8),
                TextFormField(controller: _upiCtrl, decoration: const InputDecoration(labelText: "UPI ID (VPA)", border: OutlineInputBorder(), hintText: "college@upi", prefixIcon: Icon(Icons.qr_code))),
                const SizedBox(height: 16),
                
                // QR Code Upload Area
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      // Preview
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                        child: _imageFile != null 
                            ? (kIsWeb ? Image.network(_imageFile!.path, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.error)) 
                                      : Image.file(File(_imageFile!.path), fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.error)))
                            : (_existingImageUrl != null 
                                ? Image.network(_existingImageUrl!, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image))
                                : const Icon(Icons.qr_code, size: 40, color: Colors.grey)),
                      ),
                      const SizedBox(width: 16),
                      // Button
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_imageFile != null ? "New Image Selected" : "Upload QR Code Image", style: const TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            OutlinedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.upload_file),
                              label: const Text("Choose File"),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isUploading) const Padding(padding: EdgeInsets.only(top: 20), child: LinearProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: _isUploading ? null : _save, 
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          child: Text(_isUploading ? "Saving..." : "Save Details"),
        ),
      ],
    );
  }
}
