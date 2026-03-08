import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class QuotaScreen extends StatefulWidget {
  final Widget? drawer;
  const QuotaScreen({super.key, this.drawer});

  @override
  State<QuotaScreen> createState() => _QuotaScreenState();
}

class _QuotaScreenState extends State<QuotaScreen> {
  final Color primaryRed = const Color(0xFFD32F2F); // A-DACS Corporate Red

  Future<void> _addQuota() async {
    final TextEditingController quotaCtrl = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Add New Quota", style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: quotaCtrl,
          decoration: InputDecoration(
            labelText: "Quota Name (e.g. MQ, A-Category)",
            hintText: "Enter category name",
            labelStyle: TextStyle(color: primaryRed),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: primaryRed, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text("Cancel", style: TextStyle(color: Colors.grey[600]))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              if (quotaCtrl.text.trim().isNotEmpty) {
                await FirebaseFirestore.instance.collection('quotas').add({
                  'name': quotaCtrl.text.trim(),
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text("Save Quota", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  Future<void> _deleteQuota(String docId, String quotaName) async {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Quota?"),
        content: Text("Are you sure you want to remove '$quotaName'? This may affect fee structure matching."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryRed),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('quotas').doc(docId).delete();
              if (mounted) Navigator.pop(ctx);
            }, 
            child: const Text("Delete", style: TextStyle(color: Colors.white))
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      drawer: widget.drawer,
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Manage Quotas", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQuota,
        backgroundColor: primaryRed,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("ADD QUOTA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Corporate Header Accent
          Container(
            height: 20,
            decoration: BoxDecoration(
              color: primaryRed,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('quotas').orderBy('name').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFFD32F2F))));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.category_outlined, size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text("No quotas found", style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    String name = data['name'] ?? 'Unknown';
                    
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: Container(
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(
                            color: primaryRed.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              name[0].toUpperCase(), 
                              style: TextStyle(color: primaryRed, fontSize: 20, fontWeight: FontWeight.bold)
                            ),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: const Text("Active Category", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: primaryRed.withOpacity(0.7)),
                          onPressed: () => _deleteQuota(doc.id, name),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}