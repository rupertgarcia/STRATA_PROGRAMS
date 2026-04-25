import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'package:csv/csv.dart';
import 'dart:io';

class SavedScansScreen extends StatefulWidget {
  const SavedScansScreen({Key? key}) : super(key: key);

  @override
  _SavedScansState createState() => _SavedScansState();
}

class _SavedScansState extends State<SavedScansScreen> {
  List<Map<String, dynamic>> _scans = [];
  Set<int> _selectedIds = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadScans();
  }

  Future<void> _loadScans() async {
    final scans = await DatabaseHelper.instance.readAllScans();
    setState(() {
      _scans = scans;
      _isLoading = false;
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  String _formatTime(String isoTime) {
    try {
      final d = DateTime.parse(isoTime);
      return "${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}";
    } catch(e) { 
      return isoTime; 
    }
  }

  Widget _buildParamChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _deleteSelectedScans() async {
    if (_selectedIds.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1332),
        title: const Text('Delete Scans', style: TextStyle(color: Colors.redAccent)),
        content: Text('Are you sure you want to delete ${_selectedIds.length} scans?', style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(context);
              for (int id in _selectedIds) {
                await DatabaseHelper.instance.deleteScan(id);
              }
              setState(() {
                _selectedIds.clear();
              });
              _loadScans();
            },
            child: const Text('Delete'),
          ),
        ],
      )
    );
  }

  Future<void> _exportToCSV() async {
    if (_scans.isEmpty) return;

    final defaultName = _selectedIds.isNotEmpty 
          ? 'strato_selected_${DateTime.now().millisecondsSinceEpoch}'
          : 'strato_all_${DateTime.now().millisecondsSinceEpoch}';

    final TextEditingController nameController = TextEditingController(text: defaultName);

    final resultName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1332),
        title: const Text('Export CSV', style: TextStyle(color: Color(0xFFDFC424))),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'File Name',
            labelStyle: TextStyle(color: Colors.white54),
            suffixText: '.csv',
            suffixStyle: TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFDFC424))),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
             style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDFC424), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Export'),
          ),
        ],
      )
    );

    if (resultName == null || resultName.isEmpty) return;

    String finalFileName = resultName.endsWith('.csv') ? resultName : '$resultName.csv';

    List<Map<String, dynamic>> scansToExport = [];
    if (_selectedIds.isNotEmpty) {
      scansToExport = _scans.where((scan) => _selectedIds.contains(scan['id'])).toList();
    } else {
      scansToExport = _scans;
    }

    List<List<dynamic>> rows = [];
    rows.add(["ID", "Crop Name", "Soil Types", "Time", "Temp", "Moisture", "EC", "pH", "Nitrogen", "Phosphorus", "Potassium"]);

    for (var row in scansToExport) {
      rows.add([
        row['id'],
        row['cropName'],
        row['soilTypes'],
        _formatTime(row['time']),
        row['temp'],
        row['moisture'],
        row['ec'],
        row['ph'],
        row['nitrogen'],
        row['phosphorus'],
        row['potassium']
      ]);
    }

    String csv = Csv().encode(rows);

    try {
      final directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
          
      final file = File('${directory.path}/$finalFileName');
      await file.writeAsString(csv);
      
      if(mounted) {
        setState(() {
          _selectedIds.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Exported to ${file.path}', style: const TextStyle(fontWeight: FontWeight.bold)),
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to export: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelectionMode = _selectedIds.isNotEmpty;
    
    final filteredScans = _scans.where((scan) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final crop = (scan['cropName'] as String).toLowerCase();
      final soil = (scan['soilTypes'] as String).toLowerCase();
      return crop.contains(q) || soil.contains(q);
    }).toList();
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isSelectionMode ? '${_selectedIds.length} Selected' : 'Saved Scans'),
        leading: isSelectionMode 
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _selectedIds.clear()),
            )
          : null,
        actions: [
          if (isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _deleteSelectedScans,
              tooltip: 'Delete Selected',
            ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportToCSV,
            tooltip: isSelectionMode ? 'Export Selected to CSV' : 'Export All to CSV',
          )
        ],
      ),
      body: Column(
        children: [
          if (!isSelectionMode)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search Crop or Soil...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFDFC424)),
                  filled: true,
                  fillColor: const Color(0xFF1E1332),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFDFC424)))
              : filteredScans.isEmpty
                ? const Center(child: Text('No matching scans found.', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filteredScans.length,
                    itemBuilder: (context, index) {
                      final scan = filteredScans[index];
                      final id = scan['id'] as int;
                      final isSelected = _selectedIds.contains(id);
                      
                      return Card(
                        color: isSelected ? const Color(0xFF332052) : const Color(0xFF1E1332),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            if (isSelectionMode) {
                              _toggleSelection(id);
                            }
                          },
                          onLongPress: () {
                            if (!isSelectionMode) {
                              _toggleSelection(id);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isSelectionMode)
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: const Color(0xFFDFC424),
                                    checkColor: Colors.black,
                                    onChanged: (bool? value) => _toggleSelection(id),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text('${scan['cropName']}', 
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFDFC424)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(_formatTime(scan['time']), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text('${scan['soilTypes']}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 6.0,
                                        runSpacing: 6.0,
                                        children: [
                                          _buildParamChip('T', '${scan['temp']}°C', Colors.redAccent),
                                          _buildParamChip('M', '${scan['moisture']}%', Colors.blueAccent),
                                          _buildParamChip('pH', '${scan['ph']}', Colors.greenAccent),
                                          _buildParamChip('EC', '${scan['ec']}', Colors.tealAccent),
                                          _buildParamChip('N', '${scan['nitrogen']}', Colors.orangeAccent),
                                          _buildParamChip('P', '${scan['phosphorus']}', Colors.purpleAccent),
                                          _buildParamChip('K', '${scan['potassium']}', Colors.amberAccent),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
