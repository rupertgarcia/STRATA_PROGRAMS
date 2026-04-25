import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'saved_scans_screen.dart';
import 'database_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _cropController = TextEditingController();
  final List<TextEditingController> _soilControllers = [TextEditingController()];
  
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _triggerChar;
  BluetoothCharacteristic? _phChar;
  BluetoothCharacteristic? _moistureChar;
  BluetoothCharacteristic? _tempChar;
  BluetoothCharacteristic? _ecChar;
  BluetoothCharacteristic? _nitrogenChar;
  BluetoothCharacteristic? _phosphorusChar;
  BluetoothCharacteristic? _potassiumChar;

  bool _isConnecting = false;
  bool _isScanning = false;
  
  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.storage,
    ].request();
  }

  Future<void> _connectToPi() async {
    setState(() => _isConnecting = true);
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      
      FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          if (r.device.platformName == 'Strata' || r.device.advName == 'Strata') {
            await FlutterBluePlus.stopScan();
            await r.device.connect(license: License.free);
            setState(() => _connectedDevice = r.device);
            _discoverServices(r.device);
            break;
          }
        }
      });
      
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _connectedDevice == null) {
          setState(() => _isConnecting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not find Strata device. Make sure the Pi is active.')),
          );
        }
      });
    } catch (e) {
      setState(() => _isConnecting = false);
      print(e);
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      if (service.uuid.toString().toLowerCase() == "56c36f56-da27-464a-952a-9e6631168f6d") {
        for (var char in service.characteristics) {
          final uuidStr = char.uuid.toString().toLowerCase();
          if (uuidStr == "56c36f67-da27-464a-952a-9e6631168f6d") _triggerChar = char;
          if (uuidStr == "56c36f60-da27-464a-952a-9e6631168f6d") _phChar = char;
          if (uuidStr == "56c36f61-da27-464a-952a-9e6631168f6d") _moistureChar = char;
          if (uuidStr == "56c36f62-da27-464a-952a-9e6631168f6d") _tempChar = char;
          if (uuidStr == "56c36f63-da27-464a-952a-9e6631168f6d") _ecChar = char;
          if (uuidStr == "56c36f64-da27-464a-952a-9e6631168f6d") _nitrogenChar = char;
          if (uuidStr == "56c36f65-da27-464a-952a-9e6631168f6d") _phosphorusChar = char;
          if (uuidStr == "56c36f66-da27-464a-952a-9e6631168f6d") _potassiumChar = char;
        }
      }
    }
    setState(() => _isConnecting = false);
  }

  void _startScan() async {
    if (_isScanning) return;
    if (_connectedDevice == null || _triggerChar == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connect to Strata Device First!')));
      return;
    }
    
    setState(() => _isScanning = true);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1332),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Scanning hardware...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(seconds: 60),
              builder: (context, value, _) => Column(
                children: [
                  LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: const Color(0xFFDFC424),
                    backgroundColor: Colors.black45,
                  ),
                  const SizedBox(height: 8),
                  Text("${(value * 100).toInt()}% - Averaging 10 scans", style: const TextStyle(color: Colors.white70, fontSize: 12))
                ],
              ),
            ),
          ],
        )
      ),
    );
    
    try {
      // Enable notifications to "wait for what the server sends"
      for (var char in [_phChar, _moistureChar, _tempChar, _ecChar, _nitrogenChar, _phosphorusChar, _potassiumChar]) {
        try {
          await char?.setNotifyValue(true);
        } catch (_) {} 
      }

      await _triggerChar!.write([0x02], withoutResponse: false);
      await Future.delayed(const Duration(seconds: 60));
      final phBytes = await _phChar?.read();
      final moistureBytes = await _moistureChar?.read();
      final tempBytes = await _tempChar?.read();
      final ecBytes = await _ecChar?.read();
      final nitrogenBytes = await _nitrogenChar?.read();
      final phosphorusBytes = await _phosphorusChar?.read();
      final potassiumBytes = await _potassiumChar?.read();
      
      double parseMetric(List<int>? bytes) {
        if (bytes == null || bytes.isEmpty) return 0.0;
        final str = String.fromCharCodes(bytes);
        if (str == "Err") return 0.0;
        return double.tryParse(str) ?? 0.0;
      }
      
      final ph = parseMetric(phBytes);
      final moisture = parseMetric(moistureBytes);
      final temp = parseMetric(tempBytes);
      final ec = parseMetric(ecBytes);
      final nitrogen = parseMetric(nitrogenBytes);
      final phosphorus = parseMetric(phosphorusBytes);
      final potassium = parseMetric(potassiumBytes);
      
      if (_isScanning && mounted) {
        Navigator.pop(context); // Close loading
        setState(() => _isScanning = false);
      }
      
      final crop = _cropController.text.isEmpty ? "Unknown" : _cropController.text;
      final soilsList = _soilControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      final soils = soilsList.isEmpty ? "Unknown" : soilsList.join(", ");
        
      await DatabaseHelper.instance.insertScan({
        'cropName': crop,
        'soilTypes': soils,
        'time': DateTime.now().toIso8601String(),
        'temp': temp,
        'moisture': moisture,
        'ec': ec,
        'ph': ph,
        'nitrogen': nitrogen,
        'phosphorus': phosphorus,
        'potassium': potassium,
      });
      
      _showSuccessDialog();
    } catch (e) {
      if (_isScanning) {
        Navigator.pop(context); // Close loading
        setState(() => _isScanning = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error reading sensors: $e')));
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1332),
        title: const Text('Scan Complete', style: TextStyle(color: Color(0xFFDFC424))),
        content: const Text('10-scan average saved successfully. What would you like to do next?', style: TextStyle(color: Colors.white)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1332), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context); 
            },
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDFC424), foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _cropController.clear();
              for (var c in _soilControllers) {
                c.clear();
              }
              if (_soilControllers.length > 1) {
                setState(() {
                  _soilControllers.removeRange(1, _soilControllers.length);
                });
              }
            },
            child: const Text('Scan Again'),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Strato Scanner', style: TextStyle(color: Color(0xFFDFC424), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.list, color: Color(0xFFDFC424)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedScansScreen())),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset('assets/strato_logo.png', height: 120),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1332),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDFC424).withOpacity(0.4)),
              ),
              child: const Text(
                'This application is for data gathering purposes only. Gathered data will be processed and used exclusively for the main Strata app.',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            
            Row(
              children: [
                Icon(Icons.bluetooth, color: _connectedDevice != null ? Colors.greenAccent : Colors.grey),
                const SizedBox(width: 8),
                Text(
                  _connectedDevice != null ? 'Connected to Server' : 'Not Connected',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                if (_connectedDevice == null)
                  ElevatedButton(
                    onPressed: _isConnecting ? null : _connectToPi,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                    child: _isConnecting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Connect'),
                  ),
                if (_connectedDevice != null)
                  ElevatedButton(
                    onPressed: () {
                      _connectedDevice?.disconnect();
                      setState(() => _connectedDevice = null);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                    child: const Text('Disconnect', style: TextStyle(color: Colors.white)),
                  )
              ],
            ),
            const SizedBox(height: 24),
            
            TextField(
              controller: _cropController,
              decoration: const InputDecoration(labelText: 'Crop Name', labelStyle: TextStyle(color: Colors.white54)),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            
            const Text('Soil Types', style: TextStyle(color: Color(0xFFDFC424), fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            
            ..._soilControllers.asMap().entries.map((entry) {
              int idx = entry.key;
              return Padding(
                 padding: const EdgeInsets.only(bottom: 8.0),
                 child: Row(
                   children: [
                     Expanded(
                       child: TextField(
                         controller: entry.value,
                         decoration: InputDecoration(labelText: 'Soil Type ${idx + 1}', labelStyle: const TextStyle(color: Colors.white54)),
                         style: const TextStyle(color: Colors.white),
                       ),
                     ),
                     if (_soilControllers.length > 1) 
                       IconButton(
                         icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                         onPressed: () => setState(() => _soilControllers.removeAt(idx)),
                       )
                   ],
                 )
              );
            }).toList(),
            
            TextButton.icon(
              onPressed: () => setState(() => _soilControllers.add(TextEditingController())),
              icon: const Icon(Icons.add, color: Color(0xFFDFC424)),
              label: const Text('Add another soil type', style: TextStyle(color: Color(0xFFDFC424))),
            ),
            
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isScanning ? null : _startScan,
              child: const Text('START SCAN', style: TextStyle(fontSize: 16, letterSpacing: 1.2)),
            )
          ],
        ),
      ),
    );
  }
}
