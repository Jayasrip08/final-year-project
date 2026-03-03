import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/fee_service.dart';
import '../../services/notification_service.dart';

class FeeSetupScreen extends StatefulWidget {
  final Widget? drawer;
  const FeeSetupScreen({super.key, this.drawer});

  @override
  State<FeeSetupScreen> createState() => _FeeSetupScreenState();
}

class _FeeSetupScreenState extends State<FeeSetupScreen> {
  // Config
  String _batch = '';
  String _dept = 'All';
  String _quota = 'All';
  String _semester = '1';
  DateTime? _deadline;
  DateTime? _examDeadline; // NEW: Separate exam deadline

  // State
  bool _isLoading = false;
  List<String> _activeBatches = [];
  bool _loadingBatches = true;
  
  // Dynamic Fee Components: {"Component Name": Controller}
  final Map<String, TextEditingController> _controllers = {};
  
  // Bus Fee Places: {"Place Name": amount}
  final Map<String, TextEditingController> _busFeePlaces = {};
  
  // Exam Fee
  final TextEditingController _examFeeCtrl = TextEditingController();
  
  // Pre-defined suggestions
  final List<String> _commonFees = [
    'Tuition Fee', 'Hostel Fee', 
    'Library Fee', 'Association Fee', 'Training Fee', 'Book Fee'
  ];

  bool _isEditing = false;
  List<String> _activeSemesters = [];
  List<String> _activeDepts = ['All'];
  List<String> _activeQuotas = ['All'];
  bool _isLoadingMetaData = true;

  @override
  void initState() {
    super.initState();
    _loadActiveBatches();
    _loadDeptsAndQuotas();
    _resetControllers();
  }

  Future<void> _loadDeptsAndQuotas() async {
    try {
      final deptSnapshot = await FirebaseFirestore.instance.collection('departments').orderBy('name').get();
      final quotaSnapshot = await FirebaseFirestore.instance.collection('quotas').orderBy('name').get();

      if (mounted) {
        setState(() {
          _activeDepts = ['All', ...deptSnapshot.docs.map((d) => d['name'].toString())];
          _activeQuotas = ['All', ...quotaSnapshot.docs.map((d) => d['name'].toString())];
          _isLoadingMetaData = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading metadata: $e");
      if (mounted) setState(() => _isLoadingMetaData = false);
    }
  }

  Future<void> _loadActiveSemesters() async {
    if (_batch.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('semesters')
          .where('academicYear', isEqualTo: _batch) // REVERTED TO NAME
          .where('isActive', isEqualTo: true) // Allow seeing inactive semesters for setup
          //.orderBy('semesterNumber') // Removed to avoid index issues
          .get();

      if (mounted) {
        setState(() {
          // Use a Set to avoid duplicates if ID == Name or other overlap
          final semNumbers = <String>{};
          for (var d in snapshot.docs) {
            semNumbers.add(d['semesterNumber'].toString());
          }
          
          // Convert back to sorted list
          _activeSemesters = semNumbers.toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
          
          // Ensure selected semester is valid
          if (_activeSemesters.isNotEmpty) {
             if (!_activeSemesters.contains(_semester)) {
               _semester = _activeSemesters.first;
             }
          } else {
             _semester = ''; // No semesters available
          }
        });
        _loadExistingStructure(); // Reload structure for new semester
      }
    } catch (e) {
      debugPrint("Error loading semesters: $e");
    }
  }

  Future<void> _loadActiveBatches() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('academic_years')
          .where('isActive', isEqualTo: true)
          .get();
      
      if (mounted) {
        setState(() {
          _activeBatches = snapshot.docs.map((doc) => doc['name'] as String).toList();
          
          if (_activeBatches.isNotEmpty) {
            _batch = _activeBatches.first;
            _loadActiveSemesters(); // Load semesters for this batch
          }
          _loadingBatches = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingBatches = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading batches: $e')),
        );
      }
    }
  }

  Future<void> _loadExistingStructure() async {
    if (_batch.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    // Use deterministic ID for loading (Batch_Dept_Quota_Sem)
    String sanitizedDept = _dept.replaceAll(" ", "_");
    String sanitizedQuota = _quota.replaceAll(" ", "_");
    String docId = "${_batch}_${sanitizedDept}_${sanitizedQuota}_$_semester";
    
    try {
      final doc = await FirebaseFirestore.instance
          .collection('fee_structures')
          .doc(docId)
          .get();

      if (doc.exists && (doc.data()?['isActive'] ?? false)) {
        final data = doc.data()!;
        final components = data['components'] as Map<String, dynamic>? ?? {};
        final deadline = data['deadline'] as Timestamp?;
        final examFee = data['examFee'] as num?;
        final examDeadline = data['examDeadline'] as Timestamp?;

        setState(() {
          _isEditing = true; // Data loaded from DB
          _controllers.clear();
          _busFeePlaces.clear();
          _deadline = deadline?.toDate();
          _examDeadline = examDeadline?.toDate();
          _examFeeCtrl.text = examFee?.toString() ?? '';

          components.forEach((key, value) {
            if (key == 'Bus Fee' && value is Map) {
              value.forEach((place, amt) {
                _busFeePlaces[place] = TextEditingController(text: amt.toString());
              });
            } else if (value is num) {
              _controllers[key] = TextEditingController(text: value.toString());
            }
          });
          _isLoading = false;
        });
      } else {
        // No existing structure, reset to defaults
        setState(() {
          _isEditing = false; // Fresh start
          _resetControllers();
          _deadline = null;
          _examDeadline = null;
          _examFeeCtrl.clear();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading existing structure: $e');
    }
  }

  void _resetControllers() {
    _controllers.clear();
    _busFeePlaces.clear();
    // Default starter fees
    _addFeeComponent("Tuition Fee");
    _addBusFeePlace("City Center");
  }

  void _addBusFeePlace(String placeName) {
    if (!_busFeePlaces.containsKey(placeName)) {
      setState(() {
        _busFeePlaces[placeName] = TextEditingController();
      });
    }
  }

  void _removeBusFeePlace(String placeName) {
    setState(() {
      _busFeePlaces.remove(placeName);
    });
  }

  void _addFeeComponent(String name) {
    if (!_controllers.containsKey(name)) {
      setState(() {
        _controllers[name] = TextEditingController();
      });
    }
  }

  void _removeComponent(String name) {
    setState(() {
      _controllers.remove(name);
    });
  }

  void _saveFeeStructure() async {
    setState(() => _isLoading = true);

    Map<String, dynamic> components = {};
    
    // Add regular fee components
    _controllers.forEach((key, ctrl) {
      if (ctrl.text.isNotEmpty) {
        components[key] = double.tryParse(ctrl.text.replaceAll(',', '')) ?? 0.0;
      }
    });

    // Add bus fee places
    if (_busFeePlaces.isNotEmpty) {
      Map<String, double> busFeeMap = {};
      _busFeePlaces.forEach((place, ctrl) {
        if (ctrl.text.isNotEmpty) {
          busFeeMap[place] = double.tryParse(ctrl.text.replaceAll(',', '')) ?? 0.0;
        }
      });
      if (busFeeMap.isNotEmpty) {
        components['Bus Fee'] = busFeeMap;
      }
    }

    if (components.isEmpty) {
      NotificationService.showError('Please add at least one fee component');
      setState(() => _isLoading = false);
      return;
    }

    // Calculate total
    double total = 0;
    components.forEach((key, value) {
      if (value is Map) {
        value.values.forEach((amt) => total += (amt as num).toDouble());
      } else {
        total += (value as num).toDouble();
      }
    });

    double examFee = double.tryParse(_examFeeCtrl.text.replaceAll(',', '')) ?? 0.0;
    total += examFee;

    try {
      await FeeService().setFeeComponents(
        academicYear: _batch,
        dept: _dept,
        quotaCategory: _quota,
        semester: _semester,
        components: components,
        totalAmount: total,
        deadline: _deadline,
        examFee: double.tryParse(_examFeeCtrl.text.replaceAll(',', '')) ?? 0.0,
        examDeadline: _examDeadline,
      );

      setState(() => _isLoading = false);
      
      if (mounted) {
        NotificationService.showSuccess('Fee Structure Saved Successfully!');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        NotificationService.showError('Error saving: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configure Semester Fees")),
      drawer: widget.drawer,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // STATUS INDICATOR
            Align(
              alignment: Alignment.centerRight,
              child: Chip(
                label: Text(_isEditing ? "Editing Saved Fees" : "New Fee Structure", style: const TextStyle(fontWeight: FontWeight.bold)),
                backgroundColor: _isEditing ? Colors.amber[100] : Colors.green[100],
                avatar: Icon(_isEditing ? Icons.edit : Icons.add, size: 18, color: _isEditing ? Colors.orange : Colors.green),
              ),
            ),
            
            // FILTERS CARD
            Card(
              elevation: 4,
              color: Colors.indigo[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildRow(
                      _loadingBatches
                        ? const Center(child: CircularProgressIndicator())
                        : _activeBatches.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'No active batches',
                                style: TextStyle(color: Colors.orange, fontSize: 12),
                              ),
                            )
                          : _buildDropdown("Batch", _activeBatches, _batch, (v) {
                                setState(() => _batch = v!);
                                setState(() => _batch = v!);
                                _loadActiveSemesters();
                              }),
                      _isLoadingMetaData 
                          ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                          : _buildDropdown("Dept", _activeDepts, _dept, (v) {
                        setState(() => _dept = v!);
                        _loadExistingStructure();
                      }),
                    ),
                    const SizedBox(height: 10),
                    _buildRow(
                      _isLoadingMetaData
                          ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                          : _buildDropdown("Quota", _activeQuotas, _quota, (v) {
                        setState(() => _quota = v!);
                        _loadExistingStructure();
                      }),
                      // Semester Dropdown
                      _activeSemesters.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text("No Active Semesters found for this batch.", style: TextStyle(color: Colors.red)),
                            )
                          : _buildDropdown("Semester", _activeSemesters, _semester, (v) {
                              setState(() => _semester = v!);
                              _loadExistingStructure();
                            }),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      title: Text(_deadline == null ? "Set Payment Deadline" : "Deadline: ${DateFormat('dd MMM yyyy').format(_deadline!)}"),
                      trailing: const Icon(Icons.calendar_month, color: Colors.indigo),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _deadline ?? DateTime.now().add(const Duration(days: 30)),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _deadline = picked);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // DYNAMIC LIST
            const Text("Fee Breakdown", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            ..._controllers.keys.map((key) {
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _controllers[key],
                          decoration: const InputDecoration(
                            labelText: "Amount",
                            prefixText: "₹ ",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            // Optional: Add auto-formatting here if needed
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeComponent(key),
                      )
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),
            
            // BUS FEE PLACES SECTION
            Card(
              elevation: 4,
              color: Colors.teal[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Bus Fee (Place-Based)",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_location, color: Colors.teal),
                          tooltip: "Add Place",
                          onPressed: () async {
                            final placeController = TextEditingController();
                            final result = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Add Bus Route/Place'),
                                content: TextField(
                                  controller: placeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Place Name (e.g., City Center)',
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
                                    child: const Text('Add'),
                                  ),
                                ],
                              ),
                            );
                            if (result == true && placeController.text.isNotEmpty) {
                              _addBusFeePlace(placeController.text);
                            }
                          },
                        ),
                      ],
                    ),
                    const Divider(),
                    if (_busFeePlaces.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No bus routes added. Click + to add.'),
                      )
                    else
                      ..._busFeePlaces.keys.map((place) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.teal, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  place,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _busFeePlaces[place],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    prefixText: '₹ ',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    hintText: 'Amount',
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _removeBusFeePlace(place),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            
            // EXAM FEE SECTION
            Card(
              elevation: 4,
              color: Colors.purple[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.assignment, color: Colors.purple, size: 24),
                        SizedBox(width: 8),
                        Text(
                          "Exam Fee",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _examFeeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Exam Fee Amount',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                        hintText: 'Enter exam fee (e.g., 1000)',
                        helperText: 'Leave empty if no exam fee',
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _examDeadline == null 
                          ? "Set Exam Fee Deadline" 
                          : "Exam Deadline: ${DateFormat('dd MMM yyyy').format(_examDeadline!)}",
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      trailing: const Icon(Icons.calendar_today, color: Colors.purple),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _examDeadline ?? DateTime.now().add(const Duration(days: 45)),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _examDeadline = picked);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),
            // ADD MORE BUTTON
            Center(
              child: PopupMenuButton<String>(
                onSelected: _addFeeComponent,
                itemBuilder: (context) {
                  return _commonFees.map((fee) => PopupMenuItem(
                    value: fee,
                    child: Text(fee),
                  )).toList();
                },
                child: Chip(
                  avatar: const Icon(Icons.add_circle, color: Colors.white),
                  label: const Text("Add Another Fee Component"),
                  backgroundColor: Colors.indigo,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveFeeStructure,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  elevation: 5,
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("SAVE STRUCTURE", style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(Widget w1, Widget w2) {
    return Row(
      children: [
        Expanded(child: w1),
        const SizedBox(width: 10),
        Expanded(child: w2),
      ],
    );
  }

  Widget _buildDropdown(String label, List<String> items, String val, Function(String?) onChange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: items.contains(val) ? val : items.first,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChange,
        ),
      ],
    );
  }
}