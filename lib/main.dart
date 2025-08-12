import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
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
    } else if (Platform.isIOS) {
      await Permission.location.request();
    }
  }

  /// ✨ UPDATED: Platform-aware connection method
  Future<void> _connectToESP32() async {
    // Show iOS-specific instructions if needed
    if (Platform.isIOS) {
      final shouldContinue = await _showIOSConnectionDialog();
      if (!shouldContinue) return;
    }

    setState(() {
      _isConnecting = true;
      _isLoggingIn = false;
      _isWifiConnected = false;
      _isLoggedIn = false;
      _statusMessage = Platform.isIOS
          ? 'Checking ESP32 connection...'
          : 'Connecting to ESP32 WiFi...';
    });

    try {
      final success = await _esp32Client.connectAndLoginNative();

      setState(() {
        _isConnecting = false;

        if (success) {
          _isWifiConnected = true;
          _isLoggedIn = true;
          _statusMessage = 'Connected & Logged In! 🎉';
        } else {
          _isWifiConnected = false;
          _isLoggedIn = false;

          if (Platform.isIOS) {
            _statusMessage =
                'Unable to reach ESP32. Please check WiFi connection.';
          } else {
            _statusMessage = 'Connection failed';
          }
        }
      });

      if (success) {
        await _loadAllData();
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isWifiConnected = false;
        _isLoggedIn = false;
        _statusMessage = Platform.isIOS
            ? 'Connection error. Make sure you\'re connected to ESP32 WiFi.'
            : 'Connection failed: $e';
      });
    }
  }

  /// ✨ UPDATED: iOS connection instructions dialog with WiFi settings navigation
  Future<bool> _showIOSConnectionDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.phone_iphone, color: Colors.blue),
                SizedBox(width: 8),
                Text('iOS Connection'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On iOS, you need to manually connect to the ESP32 WiFi:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text('1. Connect to "${ESP32Client.ESP32_SSID}"'),
                Text('2. Return to this app'),
                Text('3. Tap "Continue" below'),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'The app will then attempt to communicate with the ESP32 device.',
                    style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await AppSettings.openAppSettingsPanel(
                    AppSettingsPanelType.wifi,
                  );
                },
                icon: Icon(Icons.settings, size: 16),
                label: Text('Open WiFi Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// ✨ UPDATED: Retry logic works differently for iOS vs Android
  Future<void> _retryLogin() async {
    if (Platform.isIOS) {
      // iOS: Just retry the connection since it's all-in-one
      await _connectToESP32();
      return;
    }

    // Android: Original retry login logic
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

      // Load MQTT config
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
      await _disconnect();
    }
  }

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

  /// ✨ UPDATED: iOS-aware connection status card with WiFi settings navigation
  Widget _buildConnectionStatusCard() {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    String platformInfo = '';

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

    // Platform-specific info
    if (Platform.isIOS) {
      platformInfo = _isConnected
          ? 'iOS: Connected via manual WiFi'
          : 'iOS: Manual WiFi connection required';
    } else {
      platformInfo = _isConnected
          ? 'Android: Native connection active'
          : 'Android: Native connection available';
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
            SizedBox(height: 4),
            Text(
              platformInfo,
              style: TextStyle(fontSize: 12, color: Colors.blue[600]),
            ),
            SizedBox(height: 16),

            // Platform-specific instructions
            if (!_isConnected && Platform.isIOS) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, size: 16, color: Colors.blue[700]),
                        SizedBox(width: 4),
                        Text(
                          'iOS Connection Steps:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Connect to "${ESP32Client.ESP32_SSID}" in WiFi settings, then return to this app and tap Connect',
                      style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await AppSettings.openAppSettingsPanel(
                          AppSettingsPanelType.wifi,
                        );
                      },
                      icon: Icon(Icons.settings, size: 16),
                      label: Text('Open WiFi Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 36),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
            ],

            // Connection buttons
            if (!_isConnected) ...[
              if (!_isWifiConnected) ...[
                ElevatedButton(
                  onPressed: _isConnecting ? null : _connectToESP32,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Platform.isIOS ? Colors.blue : null,
                  ),
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
                            Text(
                              Platform.isIOS ? 'Checking...' : 'Connecting...',
                            ),
                          ],
                        )
                      : Text(
                          Platform.isIOS
                              ? 'Check ESP32 Connection'
                              : 'Connect to ESP32',
                        ),
                ),
              ] else if (_isWifiConnected && !_isLoggedIn) ...[
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
                            : Text(
                                Platform.isIOS
                                    ? 'Retry Connection'
                                    : 'Retry Login',
                              ),
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

  /// ✨ UPDATED: Network info card with iOS compatibility
  Widget _buildNetworkInfoCard() {
    if (_networkInfo == null) return _buildInfoCard('Network Info', null);

    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Network Info',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),

            // Platform info
            if (_networkInfo!['platform'] != null) ...[
              Text('Platform: ${_networkInfo!['platform']}'),
            ],

            // iOS-specific info
            if (Platform.isIOS) ...[
              if (_networkInfo!['connection_method'] != null)
                Text('Method: ${_networkInfo!['connection_method']}'),
              if (_networkInfo!['esp32_ip'] != null)
                Text('ESP32 IP: ${_networkInfo!['esp32_ip']}'),
              Text('Connected: ${_networkInfo!['connected'] ?? false}'),
            ] else ...[
              // Android-specific info (existing logic)
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
            // ✨ UPDATED: Connection Status with iOS support
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
                _buildNetworkInfoCard(),
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
                    Row(
                      children: [
                        Text(
                          'ESP32 Info:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Platform.isIOS ? Icons.phone_iphone : Icons.android,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                      ],
                    ),
                    Text('SSID: ${ESP32Client.ESP32_SSID}'),
                    Text('IP: ${ESP32Client.ESP32_DEFAULT_IP}'),
                    Text('Username: ${ESP32Client.ESP32_USERNAME}'),
                    if (Platform.isIOS) ...[
                      SizedBox(height: 4),
                      Text(
                        'Note: iOS requires manual WiFi connection',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
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
