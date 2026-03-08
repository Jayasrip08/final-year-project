import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ViewFeesScreen extends StatefulWidget {
  final Widget? drawer;
  const ViewFeesScreen({super.key, this.drawer});

  @override
  State<ViewFeesScreen> createState() => _ViewFeesScreenState();
}

class _ViewFeesScreenState extends State<ViewFeesScreen> {
  final Color customRed = const Color.fromARGB(255, 198, 55, 45);

  List<String> _allBatches = [];
  String? _selectedBatch;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('academic_years')
        .orderBy('name', descending: true)
        .get();

    if (mounted) {
      setState(() {
        _allBatches = snapshot.docs.map((doc) => doc.id).toList();

        if (_selectedBatch == null && _allBatches.isNotEmpty) {
          _selectedBatch = _allBatches.first;
        }
      });
    }
  }

  Future<void> _deleteStructure(String docId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Fee Structure'),
        content: const Text('Are you sure you want to delete this fee structure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('fee_structures').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fee structure deleted')),
        );
      }
    }
  }

  void _editStructure(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final components = data['components'] as Map<String, dynamic>? ?? {};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Fee Structure'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Batch: ${data['academicYear']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Department: ${data['dept']}'),
              Text('Quota: ${data['quotaCategory']}'),
              Text('Semester: ${data['semester']}'),
              const Divider(),
              const Text('Fee Components:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...components.entries.map((entry) {
                final controller = TextEditingController(text: entry.value.toString());
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry.key)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            prefixText: '₹ ',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            components[entry.key] = double.tryParse(value.replaceAll(',', '')) ?? 0.0;
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }),

              if (data['examFee'] != null) ...[
                const SizedBox(height: 10),
                const Text('Exam Fee:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Expanded(child: Text("Exam Fee Amount")),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: TextEditingController(text: data['examFee'].toString()),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            prefixText: '₹ ',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            data['examFee'] = double.tryParse(value.replaceAll(',', '')) ?? 0.0;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: customRed)),
          ),
          ElevatedButton(
            onPressed: () async {
              double total = 0;
              components.forEach((key, value) {
                if (value is Map) {
                  total += (value.values.isNotEmpty) ? (value.values.first as num).toDouble() : 0.0;
                } else {
                  total += (value is num) ? value.toDouble() : 0.0;
                }
              });

              if (data['examFee'] != null) {
                total += (data['examFee'] as num).toDouble();
              }

              final updateData = {
                'components': components,
                'totalAmount': total,
                'lastUpdated': FieldValue.serverTimestamp(),
              };

              if (data['examFee'] != null) {
                updateData['examFee'] = data['examFee'];
              }

              await FirebaseFirestore.instance
                  .collection('fee_structures')
                  .doc(doc.id)
                  .update(updateData);

              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fee structure updated!')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: customRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Fee Structures'),
        backgroundColor: customRed,
        foregroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      drawer: widget.drawer,
      body: Column(
        children: [
          // Batch Filter Chip Bar
          if (_allBatches.isNotEmpty)
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _allBatches.length,
                itemBuilder: (context, index) {
                  final batch = _allBatches[index];
                  final isSelected = batch == _selectedBatch;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(batch),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedBatch = batch);
                      },
                      backgroundColor: Colors.grey[100],
                      selectedColor: customRed.withOpacity(0.2),
                      checkmarkColor: customRed,
                      labelStyle: TextStyle(
                        color: isSelected ? customRed : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? customRed : Colors.grey[300]!,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('fee_structures')
                  .where('isActive', isEqualTo: true)
                  .where('academicYear', isEqualTo: _selectedBatch)
                  .orderBy('lastUpdated', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text(
                          'No fee structures found',
                          style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  );
                }

                final displayedDocs = snapshot.data!.docs;

                if (displayedDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.filter_list_off, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text(
                          'No active fee structures found for this batch',
                          style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: displayedDocs.length,
                  itemBuilder: (context, index) {
                    final doc = displayedDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final components = data['components'] as Map<String, dynamic>? ?? {};
                    final total = data['totalAmount'] ?? data['amount'] ?? 0.0;

                    int componentCount = components.length;
                    if (data['examFee'] != null && (data['examFee'] as num) > 0) {
                      componentCount++;
                    }

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: customRed.withOpacity(0.2)),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: customRed,
                            child: Text(
                              data['semester'] ?? '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            '${data['academicYear'] ?? 'N/A'} - ${data['dept'] ?? 'All'} - ${data['quotaCategory'] ?? 'All'}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Total: ₹${total.toStringAsFixed(0)} • $componentCount components',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                          childrenPadding: const EdgeInsets.all(16),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, color: customRed),
                                onPressed: () => _editStructure(doc),
                                tooltip: 'Edit',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteStructure(doc.id),
                                tooltip: 'Delete',
                              ),
                            ],
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Fee Components:',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  if (data['deadline'] != null)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.orange[200]!),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.calendar_month, size: 16, color: Colors.orange[800]),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Deadline: ${DateFormat('dd MMM yyyy').format((data['deadline'] as Timestamp).toDate())}",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange[800],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (data['examDeadline'] != null)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.purple[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.purple[200]!),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.assignment_late, size: 16, color: Colors.purple[800]),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Exam Deadline: ${DateFormat('dd MMM yyyy').format((data['examDeadline'] as Timestamp).toDate())}",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple[800],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const Divider(),
                                  ...components.entries.map((entry) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            entry.key,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                          Text(
                                            '₹${entry.value}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: customRed,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  if (data['examFee'] != null && (data['examFee'] as num) > 0)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            "Exam Fee",
                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.purple),
                                          ),
                                          Text(
                                            '₹${data['examFee']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Colors.purple,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const Divider(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Total Amount:',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      Text(
                                        '₹${total.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: customRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
      ),
    );
  }
}