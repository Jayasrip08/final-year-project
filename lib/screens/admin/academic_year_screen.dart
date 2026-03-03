import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class AcademicYearScreen extends StatefulWidget {
  final Widget? drawer;
  const AcademicYearScreen({super.key, this.drawer});

  @override
  State<AcademicYearScreen> createState() => _AcademicYearScreenState();
}

class _AcademicYearScreenState extends State<AcademicYearScreen> {

  // Academic Year Creation
  Future<void> _createAcademicYear() async {
    final nameController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Academic Year'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Academic Year (e.g., 2024-2028)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('academic_years')
            .doc(nameController.text)
            .set({
          'name': nameController.text,
          'isActive': false,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': FirebaseAuth.instance.currentUser!.uid,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Academic year created')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  // Toggle Academic Year Active Status
  Future<void> _toggleAcademicYear(String docId, bool currentStatus) async {
    final newStatus = !currentStatus;
    
    try {
      // 1. Update the Batch Status
      await FirebaseFirestore.instance.collection('academic_years').doc(docId).update({
        'isActive': newStatus,
      });

      // 2. Cascade status to all Semesters under this Batch
      final semSnapshot = await FirebaseFirestore.instance
          .collection('semesters')
          .where('academicYear', isEqualTo: docId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in semSnapshot.docs) {
        batch.update(doc.reference, {'isActive': newStatus});
      }
      await batch.commit();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error updating status: $e')),
        );
      }
    }
  }

  // Delete Academic Year
  Future<void> _deleteAcademicYear(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Academic Year'),
        content: const Text('Are you sure? This will also delete all associated semesters.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Delete all semesters for this academic year
        final semesters = await FirebaseFirestore.instance
            .collection('semesters')
            .where('academicYear', isEqualTo: docId)
            .get();
        
        for (var doc in semesters.docs) {
          await doc.reference.delete();
        }

        // Delete academic year
        await FirebaseFirestore.instance
            .collection('academic_years')
            .doc(docId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Academic year deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  // Create Semester
  Future<void> _createSemester({String? preSelectedBatchId}) async {
    String? selectedBatchId = preSelectedBatchId;
    int? selectedSemesterNumber;
    DateTime? startDate;
    DateTime? endDate;

    // Fetch Active Batches
    final activeBatchesSnapshot = await FirebaseFirestore.instance
        .collection('academic_years')
        .where('isActive', isEqualTo: true)
        .get();

    final activeBatches = activeBatchesSnapshot.docs.map((doc) {
      return {'id': doc.id, 'name': doc['name'] as String};
    }).toList();

    if (activeBatches.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active batches found. Please activate a batch first.')),
        );
      }
      return;
    }

    // If preSelectedBatch is provided but not active, warn user?
    // Or just let them select from active ones.
    if (selectedBatchId != null && !activeBatches.any((b) => b['id'] == selectedBatchId)) {
        selectedBatchId = null; // Reset if not active
    }

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Semester'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Batch Selection
                DropdownButtonFormField<String>(
                  value: selectedBatchId,
                  decoration: const InputDecoration(
                    labelText: 'Select Batch',
                    border: OutlineInputBorder(),
                  ),
                  items: activeBatches.map((batch) {
                    return DropdownMenuItem<String>(
                      value: batch['id'],
                      child: Text(batch['name']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedBatchId = value);
                  },
                ),
                const SizedBox(height: 16),
                
                DropdownButtonFormField<int>(
                  value: selectedSemesterNumber,
                  decoration: const InputDecoration(
                    labelText: 'Semester Number',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(8, (index) => index + 1)
                      .map((num) => DropdownMenuItem(
                            value: num,
                            child: Text('Semester $num'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedSemesterNumber = value);
                  },
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                
                // Start Date Input
                TextFormField(
                  readOnly: true,
                  controller: TextEditingController(text: startDate != null ? DateFormat('dd/MM/yyyy').format(startDate!) : ''),
                  decoration: const InputDecoration(
                    labelText: 'Start Date (Format: DD/MM/YYYY)',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => startDate = picked);
                    }
                  },
                ),
                
                const SizedBox(height: 16),
                
                // End Date Input
                TextFormField(
                  readOnly: true,
                  controller: TextEditingController(text: endDate != null ? DateFormat('dd/MM/yyyy').format(endDate!) : ''),
                  decoration: const InputDecoration(
                    labelText: 'End Date (Format: DD/MM/YYYY)',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.event),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => endDate = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedBatchId != null && selectedSemesterNumber != null && startDate != null && endDate != null) {
      try {
        await FirebaseFirestore.instance
            .collection('semesters')
            .add({
          'academicYear': selectedBatchId,
          'semesterNumber': selectedSemesterNumber,
          'startDate': Timestamp.fromDate(startDate!),
          'endDate': Timestamp.fromDate(endDate!),
          'isActive': true, // Default to true since toggle is removed
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': FirebaseAuth.instance.currentUser!.uid,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Semester created')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  // Edit Semester
  Future<void> _editSemester(String docId, Map<String, dynamic> currentData) async {
    int? selectedSemesterNumber = currentData['semesterNumber'];
    DateTime? startDate = (currentData['startDate'] as Timestamp?)?.toDate();
    DateTime? endDate = (currentData['endDate'] as Timestamp?)?.toDate();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Semester'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedSemesterNumber,
                  decoration: const InputDecoration(
                    labelText: 'Semester Number',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(8, (index) => index + 1)
                      .map((num) => DropdownMenuItem(
                            value: num,
                            child: Text('Semester $num'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedSemesterNumber = value);
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Start Date'),
                  subtitle: Text(startDate != null ? DateFormat('dd/MM/yyyy').format(startDate!) : 'Not selected'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => startDate = picked);
                    }
                  },
                ),
                ListTile(
                  title: const Text('End Date'),
                  subtitle: Text(endDate != null ? DateFormat('dd/MM/yyyy').format(endDate!) : 'Not selected'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: endDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setDialogState(() => endDate = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedSemesterNumber != null && startDate != null && endDate != null) {
      try {
        await FirebaseFirestore.instance
            .collection('semesters')
            .doc(docId)
            .update({
          'semesterNumber': selectedSemesterNumber,
          'startDate': Timestamp.fromDate(startDate!),
          'endDate': Timestamp.fromDate(endDate!),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Semester updated')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  // Delete Semester
  Future<void> _deleteSemester(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Semester'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('semesters').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semester deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Academic Year Management'),
        backgroundColor: Colors.indigo,
      ),
      drawer: widget.drawer,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('academic_years')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No academic years found'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _createAcademicYear,
                    child: const Text('Create First Academic Year'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Existing Batches',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                           ElevatedButton.icon(
                            onPressed: () => _createSemester(),
                            icon: const Icon(Icons.add_circle, color: Colors.white),
                            label: const Text('New Semester'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _createAcademicYear,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Batch'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }

              final doc = snapshot.data!.docs[index - 1];
              final data = doc.data() as Map<String, dynamic>;
              final isActive = data['isActive'] ?? false;
              final academicYearId = doc.id;

              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: isActive ? Colors.green : Colors.grey,
                        child: Icon(
                          isActive ? Icons.check : Icons.close,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        data['name'],
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(isActive ? 'Active Batch' : 'Inactive Batch'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: isActive,
                            onChanged: (val) => _toggleAcademicYear(academicYearId, isActive),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteAcademicYear(academicYearId),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 0),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Semesters',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('semesters')
                                .where('academicYear', isEqualTo: academicYearId)
                                .snapshots(),
                            builder: (context, semSnapshot) {
                              if (semSnapshot.hasError) {
                                return Text('Error: ${semSnapshot.error}', style: const TextStyle(color: Colors.red, fontSize: 12));
                              }

                              if (semSnapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: LinearProgressIndicator());
                              }

                              if (!semSnapshot.hasData || semSnapshot.data!.docs.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: Text(
                                      'No semesters created yet',
                                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: semSnapshot.data!.docs.map((semDoc) {
                                  final semData = semDoc.data() as Map<String, dynamic>;
                                  final semIsActive = semData['isActive'] ?? false;
                                  final startDate = (semData['startDate'] as Timestamp?)?.toDate();
                                  final endDate = (semData['endDate'] as Timestamp?)?.toDate();

                                    // Premium Semester Card
                                    return Card(
                                      elevation: 2,
                                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(color: semIsActive ? Colors.teal.withOpacity(0.5) : Colors.grey.withOpacity(0.2)),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            // Icon / Number
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: semIsActive ? Colors.teal.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '${semData['semesterNumber']}',
                                                  style: TextStyle(
                                                    color: semIsActive ? Colors.teal : Colors.grey[700],
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
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
                                                    'Semester ${semData['semesterNumber']}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        startDate != null && endDate != null
                                                            ? '${DateFormat('MMM yyyy').format(startDate)} - ${DateFormat('MMM yyyy').format(endDate)}'
                                                            : 'Dates not set',
                                                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Actions
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Activation Switch Removed as per request
                                                IconButton(
                                                  icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blueAccent),
                                                  onPressed: () => _editSemester(semDoc.id, semData),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                ),
                                                const SizedBox(width: 12),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                                  onPressed: () => _deleteSemester(semDoc.id),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
