import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'esp32_client.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Controller',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: ESP32HomePage(),
    );
  }
}

class ESP32HomePage extends StatefulWidget {
  const ESP32HomePage({super.key});

  @override
  _ESP32HomePageState createState() => _ESP32HomePageState();
}

class _ESP32HomePageState extends State<ESP32HomePage> {
  final ESP32Client _esp32Client = ESP32Client();
  bool _isConnecting = false;
  bool _isLoggingIn = false;
  bool _isWifiConnected = false;
  bool _isLoggedIn = false;
  String _statusMessage = 'Not connected';
  Map<String, dynamic>? _systemStatus;
  Map<String, dynamic>? _sensorData;
  Map<String, dynamic>? _mqttConfig;
  Map<String, dynamic>? _gpioConfig;
  Map<String, dynamic>? _networkInfo;

  // ✨ Computed property for overall connection status
  bool get _isConnected => _isWifiConnected && _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.location.request();
      await Permission.nearbyWifiDevices.request();
    }
  }

  Future<void> _connectToESP32() async {
    setState(() {
      _isConnecting = true;
      _isLoggingIn = false;
      _isWifiConnected = false;
      _isLoggedIn = false;
      _statusMessage = 'Connecting to ESP32 WiFi...';
    });

    try {
      // Use the new native connection method
      final success = await _esp32Client.connectAndLoginNative();

      setState(() {
        _isConnecting = false;
        _isWifiConnected =
            true; // WiFi connection part succeeded if we got here
        _isLoggedIn = success;

        if (success) {
          _statusMessage = 'Connected & Logged In! 🎉';
        } else {
          _statusMessage = 'WiFi connected but login failed ❌';
        }
      });

      if (success) {
        // Load all ESP32 data
        await _loadAllData();
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isWifiConnected = false;
        _isLoggedIn = false;
        _statusMessage = 'Connection failed: $e';
      });
    }
  }

  /// ✨ NEW: Retry login only (when WiFi is connected but login failed)
  Future<void> _retryLogin() async {
    if (!_isWifiConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('WiFi not connected. Please connect first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoggingIn = true;
      _statusMessage = 'Retrying login...';
    });

    try {
      // Try to login again using existing WiFi connection
      final success = await _esp32Client.connectAndLoginNative();

      setState(() {
        _isLoggingIn = false;
        _isLoggedIn = success;
        _statusMessage = success
            ? 'Login successful! 🎉'
            : 'Login failed again ❌';
      });

      if (success) {
        await _loadAllData();
      }
    } catch (e) {
      setState(() {
        _isLoggingIn = false;
        _statusMessage = 'Login retry failed: $e';
      });
    }
  }

  Future<void> _loadAllData() async {
    print('📊 Loading all ESP32 data...');

    try {
      // Load system status
      final systemStatus = await _esp32Client.getSystemStatus();
      print('✅ System Status: $systemStatus');

      // Load sensor data
      final sensorData = await _esp32Client.getSensorData();
      print('✅ Sensor Data: $sensorData');

      // ✨ UPDATED: getMQTTConfig() -> getMQTTStatus() to match ESP32ApiService
      final mqttConfig = await _esp32Client.getMQTTStatus();
      print('✅ MQTT Config: $mqttConfig');

      // Load GPIO config
      final gpioConfig = await _esp32Client.getGPIOConfig();
      print('✅ GPIO Config: $gpioConfig');

      // Load network info
      final networkInfo = await _esp32Client.getNetworkInfo();
      print('✅ Network Info: $networkInfo');

      setState(() {
        _systemStatus = systemStatus;
        _sensorData = sensorData;
        _mqttConfig = mqttConfig;
        _gpioConfig = gpioConfig;
        _networkInfo = networkInfo;
      });
    } catch (e) {
      print('❌ Error loading data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshData() async {
    if (!_isConnected) return;

    setState(() {
      _statusMessage = 'Refreshing data...';
    });

    await _loadAllData();

    setState(() {
      _statusMessage = 'Connected & Logged In! 🎉';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Data refreshed!'), backgroundColor: Colors.green),
    );
  }

  Future<void> _publishTestMessage() async {
    if (!_isConnected) return;

    // ✨ UPDATED: publishMQTT now takes (topic, message) instead of just message
    final defaultTopic = _mqttConfig?['topic'] ?? 'test/topic';
    final success = await _esp32Client.publishMQTT(
      defaultTopic,
      'Hello from Flutter at ${DateTime.now()}!',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'MQTT message published!' : 'Failed to publish MQTT',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _testGPIOTrigger() async {
    if (!_isConnected) return;

    // Trigger GPIO pin 2 (LED)
    final success = await _esp32Client.triggerGPIO('2');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'GPIO triggered!' : 'Failed to trigger GPIO'),
        backgroundColor: success ? Colors.orange : Colors.red,
      ),
    );
  }

  Future<void> _restartESP32() async {
    if (!_isConnected) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restart ESP32'),
        content: Text('Are you sure you want to restart the ESP32 device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Restart'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _esp32Client.restartESP32();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'ESP32 restart initiated!' : 'Failed to restart',
        ),
        backgroundColor: success ? Colors.orange : Colors.red,
      ),
    );

    if (success) {
      // Disconnect after restart
      await _disconnect();
    }
  }

  /// ✨ NEW: Factory reset with confirmation
  Future<void> _factoryReset() async {
    if (!_isConnected) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Factory Reset'),
        content: Text(
          'This will reset all settings to factory defaults. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _esp32Client.factoryReset();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Factory reset initiated!' : 'Failed to factory reset',
        ),
        backgroundColor: success ? Colors.orange : Colors.red,
      ),
    );

    if (success) {
      await _disconnect();
    }
  }

  Future<void> _disconnect() async {
    await _esp32Client.disconnect();
    setState(() {
      _isWifiConnected = false;
      _isLoggedIn = false;
      _statusMessage = 'Disconnected';
      _systemStatus = null;
      _sensorData = null;
      _mqttConfig = null;
      _gpioConfig = null;
      _networkInfo = null;
    });
  }

  Widget _buildInfoCard(
    String title,
    Map<String, dynamic>? data, {
    Color? color,
  }) {
    return Card(
      color: color,
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            if (data != null) ...[
              ...data.entries
                  .map(
                    (entry) => Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${entry.key}: ${entry.value}',
                        style: TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  )
                  .toList(),
            ] else ...[
              Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSystemStatusCard() {
    if (_systemStatus == null) return _buildInfoCard('System Status', null);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'System Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Firmware: ${_systemStatus!['firmware'] ?? 'Unknown'}'),
            Text('Free Heap: ${_systemStatus!['freeHeapKB'] ?? 'Unknown'} KB'),
            if (_systemStatus!['uptime'] != null) ...[
              Text(
                'Uptime: ${_systemStatus!['uptime']?['days'] ?? 0}d ${_systemStatus!['uptime']?['hours'] ?? 0}h ${_systemStatus!['uptime']?['minutes'] ?? 0}m',
              ),
            ],
            Text('CPU Temp: ${_systemStatus!['temperature'] ?? 'Unknown'}°C'),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorDataCard() {
    if (_sensorData == null) return _buildInfoCard('Sensor Data', null);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sensor Data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            if (_sensorData!['sensorDetected'] == true) ...[
              Text(
                'Temperature: ${_sensorData!['temperature']?.toStringAsFixed(1) ?? 'N/A'}°C',
              ),
              Text(
                'Humidity: ${_sensorData!['humidity']?.toStringAsFixed(1) ?? 'N/A'}%',
              ),
            ] else ...[
              Text('No sensor detected'),
            ],
          ],
        ),
      ),
    );
  }

  /// ✨ NEW: Build connection status with detailed states
  Widget _buildConnectionStatusCard() {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (_isConnected) {
      statusColor = Colors.green;
      statusIcon = Icons.wifi;
      statusText = 'Connected & Logged In';
    } else if (_isWifiConnected && !_isLoggedIn) {
      statusColor = Colors.orange;
      statusIcon = Icons.wifi_protected_setup;
      statusText = 'WiFi Connected - Login Required';
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.wifi_off;
      statusText = 'Disconnected';
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(statusIcon, size: 48, color: statusColor),
            SizedBox(height: 8),
            Text(
              statusText,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              _statusMessage,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            SizedBox(height: 16),

            // Connection buttons
            if (!_isConnected) ...[
              if (!_isWifiConnected) ...[
                // Not connected to WiFi - show connect button
                ElevatedButton(
                  onPressed: _isConnecting ? null : _connectToESP32,
                  child: _isConnecting
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Connecting...'),
                          ],
                        )
                      : Text('Connect to ESP32'),
                ),
              ] else if (_isWifiConnected && !_isLoggedIn) ...[
                // WiFi connected but not logged in - show retry login button
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoggingIn ? null : _retryLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        child: _isLoggingIn
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Logging in...'),
                                ],
                              )
                            : Text('Retry Login'),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _disconnect,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                        ),
                        child: Text('Disconnect'),
                      ),
                    ),
                  ],
                ),
              ],
            ] else ...[
              // Fully connected - show disconnect button
              ElevatedButton(
                onPressed: _disconnect,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                child: Text('Disconnect'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ESP32 Controller'),
        backgroundColor: _isConnected
            ? Colors.green
            : (_isWifiConnected ? Colors.orange : Colors.red),
        actions: [
          if (_isConnected) ...[
            IconButton(
              onPressed: _refreshData,
              icon: Icon(Icons.refresh),
              tooltip: 'Refresh Data',
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ✨ UPDATED: Connection Status with retry login
            _buildConnectionStatusCard(),

            if (_isConnected) ...[
              SizedBox(height: 16),

              // System Status
              _buildSystemStatusCard(),

              SizedBox(height: 16),

              // Sensor Data
              _buildSensorDataCard(),

              SizedBox(height: 16),

              // MQTT Configuration
              if (_mqttConfig != null) ...[
                _buildInfoCard('MQTT Config', {
                  'Server': _mqttConfig!['server_primary'] ?? 'Unknown',
                  'Port': _mqttConfig!['port']?.toString() ?? 'Unknown',
                  'Topic': _mqttConfig!['topic'] ?? 'Unknown',
                  'Client ID': _mqttConfig!['client_id'] ?? 'Unknown',
                }, color: Colors.blue[50]),
                SizedBox(height: 16),
              ],

              // GPIO Configuration
              if (_gpioConfig != null) ...[
                _buildInfoCard(
                  'GPIO Config',
                  _gpioConfig!,
                  color: Colors.orange[50],
                ),
                SizedBox(height: 16),
              ],

              // Network Information
              if (_networkInfo != null) ...[
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Network Info',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        if (_networkInfo!['link'] != null) ...[
                          Text('Interface: ${_networkInfo!['link']['ifName']}'),
                          Text(
                            'IP: ${(_networkInfo!['link']['addresses'] as List?)?.join(', ') ?? 'Unknown'}',
                          ),
                          Text(
                            'Open Ports: ${_networkInfo!['openPorts']?.join(', ') ?? 'None'}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
              ],

              // Control Buttons
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Controls',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _publishTestMessage,
                              child: Text('Test MQTT'),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _testGPIOTrigger,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                              ),
                              child: Text('Test GPIO'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _restartESP32,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: Text('Restart ESP32'),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _factoryReset,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[800],
                              ),
                              child: Text('Factory Reset'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],

            SizedBox(height: 20),

            // ESP32 Connection Info
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ESP32 Info:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('SSID: ${ESP32Client.ESP32_SSID}'),
                    Text('IP: ${ESP32Client.ESP32_DEFAULT_IP}'),
                    Text('Username: ${ESP32Client.ESP32_USERNAME}'),
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
