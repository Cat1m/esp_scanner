import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:esp_scanner/esp_network_android.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

class ESP32Client {
  static const String ESP32_SSID = 'ESP32-781c3ccb04d7';
  static const String ESP32_WIFI_PASSWORD = '12345678';
  static const String ESP32_USERNAME = 'admin';
  static const String ESP32_PASSWORD = '1234';
  static const String ESP32_DEFAULT_IP = '192.168.4.1';

  String? baseUrl;
  String? sessionCookie;
  bool isConnected = false;
  bool _nativeNetworkBound = false;

  // ✨ NEW: Dio instance for better HTTP handling
  Dio? _dio;

  /// Helper to safely convert native responses from Map<object?, object?>
  Map<String, dynamic> _safeCastMap(dynamic input) {
    if (input == null) return {};
    if (input is Map<String, dynamic>) return input;
    if (input is Map) {
      // Handle Map<object?, object?> from native
      return Map<String, dynamic>.fromEntries(
        input.entries.map((e) => MapEntry(e.key?.toString() ?? '', e.value)),
      );
    }
    return {};
  }

  /// Initialize Dio with proper configuration and logging
  void _initializeDio() {
    if (baseUrl == null) return;

    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl!,
        connectTimeout: Duration(seconds: 5),
        receiveTimeout: Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Add session cookie interceptor
    if (sessionCookie != null) {
      _dio!.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers['Cookie'] = sessionCookie;
            handler.next(options);
          },
        ),
      );
    }

    // ✨ NEW: Add pretty dio logger for debugging
    _dio!.interceptors.add(
      PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
        error: true,
        compact: true,
        maxWidth: 90,
      ),
    );
  }

  /// NEW: Connect using native network binding + login
  Future<bool> connectAndLoginNative() async {
    try {
      print('🔍 Connecting to ESP32 via native network binding...');

      // Step 1: Native network binding
      final networkOk = await EspNetworkAndroid.connect(
        ssid: ESP32_SSID,
        password: ESP32_WIFI_PASSWORD,
        bindProcess: true,
      );

      if (!networkOk) {
        print('❌ Failed to bind to ESP32 network');
        return false;
      }

      _nativeNetworkBound = true;
      baseUrl = 'http://$ESP32_DEFAULT_IP';

      // Initialize Dio after setting baseUrl
      _initializeDio();

      // Step 2: Wait for network to stabilize
      await Future.delayed(Duration(milliseconds: 800));

      // Step 3: Test connectivity
      print('🔌 Testing socket connectivity...');
      final socketOk = await EspNetworkAndroid.rawSocketTest(
        ESP32_DEFAULT_IP,
        80,
      );
      if (!socketOk) {
        print('❌ Cannot reach ESP32 via socket');
        return false;
      }

      // Step 4: Test login page first
      print('🔍 Testing login page accessibility...');
      final loginPageResponse = _safeCastMap(
        await EspNetworkAndroid.httpGet('$baseUrl/login'),
      );
      print('🔍 Login page response: ${loginPageResponse['code']}');

      if (loginPageResponse['code'] != 200) {
        print('❌ Cannot access login page');
        return false;
      }

      // Step 5: Extract any CSRF token from login page
      final loginPageBody = loginPageResponse['body']?.toString() ?? '';
      String? csrfToken = _extractCSRFToken(loginPageBody);
      if (csrfToken != null) {
        print('🔍 Found CSRF token: ${csrfToken.substring(0, 10)}...');
      }

      // Step 6: Login via native HTTP
      print('🔐 Logging in to ESP32...');
      final loginSuccess = await _loginToESP32Native(csrfToken: csrfToken);
      if (!loginSuccess) {
        print('❌ Login failed');
        return false;
      }

      // Step 7: Re-initialize Dio with session cookie
      _initializeDio();

      isConnected = true;
      print('🎉 Successfully connected and logged in to ESP32!');
      return true;
    } catch (e) {
      print('❌ Connection error: $e');
      return false;
    }
  }

  /// Extract CSRF token from HTML if present
  String? _extractCSRFToken(String html) {
    final patterns = <RegExp>[
      RegExp(r'''<input[^>]*name=["']_token["'][^>]*value=["']([^"']+)["']'''),
      RegExp(r'''<input[^>]*value=["']([^"']+)["'][^>]*name=["']_token["']'''),
      RegExp(
        r'''csrf[_-]?token["']?\s*[:=]\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<meta[^>]*name=["']csrf-token["'][^>]*content=["']([^"']+)["']''',
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Login via native HTTP (using bound network)
  Future<bool> _loginToESP32Native({String? csrfToken}) async {
    try {
      // ✅ Use lowercase field names to match ESP32ApiService
      String loginData = 'username=$ESP32_USERNAME&password=$ESP32_PASSWORD';

      // Add CSRF token if found
      if (csrfToken != null) {
        loginData += '&_token=$csrfToken';
      }

      print('🔐 Attempting login with proper form encoding...');
      print('🔍 Login data: $loginData');

      // Use URL-encoded form data with FormBody (like working Dio code)
      var response = _safeCastMap(
        await EspNetworkAndroid.httpPostFormData('$baseUrl/login', loginData),
      );

      print('🔍 Login response: ${response['code']}');
      print('🔍 Response headers: ${response['headers']}');

      // Check for successful login (redirect or cookie)
      if (await _checkLoginSuccess(response)) {
        return true;
      }

      print('❌ Login failed with proper form encoding');
      return false;
    } catch (e) {
      print('❌ Login error: $e');
      return false;
    }
  }

  /// Check if login was successful and extract session cookie
  Future<bool> _checkLoginSuccess(Map<String, dynamic> response) async {
    // Check for redirect (302) or success with cookie
    if (response['code'] == 302) {
      print('✅ Got redirect - login successful');
      return await _extractSessionCookie(response);
    }

    // Check for 200 with set-cookie header
    if (response['code'] == 200) {
      final headerMap = _safeCastMap(response['headers']);
      final setCookieData = headerMap['set-cookie'];

      if (setCookieData != null) {
        print('✅ Got session cookie on 200 response');
        return await _extractSessionCookie(response);
      } else {
        // 200 without cookie = login form rendered again = failed
        final body = response['body']?.toString() ?? '';
        if (body.contains('<form') || body.contains('login')) {
          print('❌ Got login form again - credentials rejected');
          return false;
        }
      }
    }

    return false;
  }

  /// Extract session cookie from response headers
  Future<bool> _extractSessionCookie(Map<String, dynamic> response) async {
    final headerMap = _safeCastMap(response['headers']);
    final setCookieData = headerMap['set-cookie'];

    if (setCookieData != null) {
      List<String> setCookieList;

      if (setCookieData is List) {
        setCookieList = setCookieData.map((e) => e.toString()).toList();
      } else {
        setCookieList = [setCookieData.toString()];
      }

      // Look for session-related cookies (like working Dio code)
      for (final cookieStr in setCookieList) {
        print('🔍 Found cookie: $cookieStr');

        // Check for various session cookie patterns
        if (cookieStr.contains('session_id=') ||
            cookieStr.contains('PHPSESSID=') ||
            cookieStr.contains('sessionid=') ||
            cookieStr.contains('SESSION=') ||
            cookieStr.toLowerCase().contains('session')) {
          sessionCookie = cookieStr.split(';')[0]; // Get session part

          // ✅ FIX: Safe substring to avoid RangeError
          final cookiePreview = sessionCookie!.length > 30
              ? '${sessionCookie!.substring(0, 30)}...'
              : sessionCookie!;
          print('✅ Session cookie extracted: $cookiePreview');
          return true;
        }
      }

      // If no specific session cookie found, use the first one
      if (setCookieList.isNotEmpty) {
        sessionCookie = setCookieList.first.split(';')[0];

        // ✅ FIX: Safe substring here too
        final cookiePreview = sessionCookie!.length > 30
            ? '${sessionCookie!.substring(0, 30)}...'
            : sessionCookie!;
        print('✅ Using first cookie as session: $cookiePreview');
        return true;
      }
    }

    // Even without explicit cookie, 302 might mean success
    if (response['code'] == 302) {
      print('⚠️ 302 redirect but no session cookie found - proceeding anyway');
      return true;
    }

    print('❌ No session cookie found');
    return false;
  }

  /// ✨ NEW: Make API call using Dio (fallback to native if needed)
  Future<Map<String, dynamic>?> _makeApiCall(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool useDio = true,
  }) async {
    if (!isConnected || baseUrl == null) {
      print('❌ Not connected to ESP32');
      return null;
    }

    // Try Dio first if available and requested
    if (useDio && _dio != null) {
      try {
        Response response;
        switch (method.toUpperCase()) {
          case 'POST':
            response = await _dio!.post(endpoint, data: body);
            break;
          case 'GET':
          default:
            response = await _dio!.get(endpoint);
            break;
        }

        if (response.statusCode == 200) {
          print('✅ Dio API $endpoint success');
          return response.data is Map
              ? Map<String, dynamic>.from(response.data)
              : response.data;
        } else {
          print('❌ Dio API $endpoint failed: ${response.statusCode}');
          return null;
        }
      } on DioException catch (e) {
        print('❌ Dio API $endpoint error: ${e.message}');
        print('🔄 Falling back to native HTTP...');
        // Fall back to native
      } catch (e) {
        print('❌ Dio API $endpoint unexpected error: $e');
        print('🔄 Falling back to native HTTP...');
        // Fall back to native
      }
    }

    // Fallback to native HTTP
    return await _makeApiCallNative(endpoint, method: method, body: body);
  }

  /// Make authenticated API call via native HTTP (fallback method)
  Future<Map<String, dynamic>?> _makeApiCallNative(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (!_nativeNetworkBound || baseUrl == null) {
      print('❌ Native network not bound');
      return null;
    }

    try {
      final url = '$baseUrl$endpoint';

      final headers = <String, String>{};
      if (sessionCookie != null) {
        headers['Cookie'] = sessionCookie!;
      }

      // Get response from native (safe casting)
      Map<String, dynamic> nativeResponse;

      switch (method.toUpperCase()) {
        case 'POST':
          final jsonBody = body != null ? json.encode(body) : '{}';
          nativeResponse = _safeCastMap(
            await EspNetworkAndroid.httpPostJsonWithHeaders(
              url,
              jsonBody,
              headers,
            ),
          );
          break;
        case 'GET':
        default:
          nativeResponse = _safeCastMap(
            await EspNetworkAndroid.httpGetWithHeaders(url, headers),
          );
          break;
      }

      print('🔍 Native API $endpoint response: ${nativeResponse['code']}');

      if (nativeResponse['code'] == 200) {
        try {
          final bodyStr = nativeResponse['body']?.toString() ?? '{}';
          final jsonData = json.decode(bodyStr);

          // Ensure we return Map<String, dynamic>
          if (jsonData is Map) {
            return Map<String, dynamic>.from(jsonData);
          } else {
            print('❌ API $endpoint returned non-map JSON: $jsonData');
            return null;
          }
        } catch (e) {
          print('❌ JSON parse error for $endpoint: $e');
          print('❌ Raw body: ${nativeResponse['body']}');
          return null;
        }
      } else {
        print('❌ Native API $endpoint failed: ${nativeResponse['code']}');
        print('❌ Error body: ${nativeResponse['body']}');
        return null;
      }
    } catch (e) {
      print('❌ Native API call error for $endpoint: $e');
      return null;
    }
  }

  // ===== ESP32 API Methods (Updated endpoints to match ESP32ApiService) =====

  /// Get system status - Updated endpoint
  Future<Map<String, dynamic>?> getSystemStatus() async {
    return await _makeApiCall(
      '/api/system-status',
    ); // Changed from /api/system/status
  }

  /// Get sensor data - Updated endpoint
  Future<Map<String, dynamic>?> getSensorData() async {
    return await _makeApiCall(
      '/api/get-sensor',
    ); // Changed from /api/sensor/data
  }

  /// Get MQTT status - Updated endpoint
  Future<Map<String, dynamic>?> getMQTTStatus() async {
    return await _makeApiCall('/api/get-mqtt'); // Changed from /api/mqtt/get
  }

  /// Update MQTT configuration - Updated endpoint
  Future<bool> updateMQTTConfig({
    required String serverPrimary,
    String? serverSecondary,
    String? serverThird,
    int port = 1883,
    required String topic,
    String? username,
    String? password,
    String? clientId,
  }) async {
    final body = {
      'server_primary': serverPrimary,
      'server_secondary': serverSecondary ?? '',
      'server_third': serverThird ?? '',
      'port': port,
      'topic': topic,
      'username': username ?? '',
      'password': password ?? '',
      'client_id': clientId ?? '',
    };

    final response = await _makeApiCall(
      '/api/update-mqtt', // Changed from /api/mqtt/update
      method: 'POST',
      body: body,
    );
    return response?['success'] ?? false;
  }

  /// Get GPIO configuration - Updated endpoint
  Future<Map<String, dynamic>?> getGPIOConfig() async {
    return await _makeApiCall('/api/get-gpio'); // Changed from /api/gpio/get
  }

  /// Trigger GPIO - Updated endpoint
  Future<bool> triggerGPIO(String pin) async {
    final response = await _makeApiCall(
      '/api/trigger-gpio', // Changed from /api/gpio/trigger
      method: 'POST',
      body: {'pin': pin},
    );
    return response?['success'] ?? false;
  }

  /// Update GPIO configuration - New method to match ESP32ApiService
  Future<bool> updateGPIOConfig(Map<String, dynamic> config) async {
    final response = await _makeApiCall(
      '/api/update-gpio',
      method: 'POST',
      body: config,
    );
    return response?['success'] ?? false;
  }

  /// Publish MQTT message - Updated endpoint
  Future<bool> publishMQTT(String topic, String message) async {
    final response = await _makeApiCall(
      '/api/publish-mqtt', // Changed from /api/mqtt/publish
      method: 'POST',
      body: {'topic': topic, 'message': message},
    );
    return response?['success'] ?? false;
  }

  /// Restart ESP32 - Updated endpoint
  Future<bool> restartESP32() async {
    final response = await _makeApiCall(
      '/api/restart', // Changed from /api/system/restart
      method: 'POST',
    );
    return response?['success'] ?? false;
  }

  // ✨ NEW: Additional methods to match ESP32ApiService

  /// Factory reset device
  Future<bool> factoryReset() async {
    final response = await _makeApiCall('/api/factory-reset', method: 'POST');
    return response?['success'] ?? false;
  }

  /// Get network configuration
  Future<Map<String, dynamic>?> getNetworkConfig() async {
    return await _makeApiCall('/api/get-network');
  }

  /// Update network configuration
  Future<bool> updateNetworkConfig(Map<String, dynamic> config) async {
    final response = await _makeApiCall(
      '/api/update-network',
      method: 'POST',
      body: config,
    );
    return response?['success'] ?? false;
  }

  /// Update password
  Future<bool> updatePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final response = await _makeApiCall(
      '/api/update-password',
      method: 'POST',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    return response?['success'] ?? false;
  }

  /// Get sensors configuration
  Future<Map<String, dynamic>?> getSensors() async {
    return await _makeApiCall('/api/get-sensors');
  }

  /// Save sensors configuration
  Future<bool> saveSensors(List<Map<String, dynamic>> sensors) async {
    final response = await _makeApiCall(
      '/api/save-sensors',
      method: 'POST',
      body: {'sensors': sensors},
    );
    return response?['success'] ?? false;
  }

  /// Publish individual sensor
  Future<bool> publishSensor(int index) async {
    final response = await _makeApiCall(
      '/api/publish-sensor',
      method: 'POST',
      body: {'index': index},
    );
    return response?['success'] ?? false;
  }

  /// Toggle sensor enable/disable
  Future<bool> toggleSensor(int index) async {
    final response = await _makeApiCall(
      '/api/toggle-sensor',
      method: 'POST',
      body: {'index': index},
    );
    return response?['success'] ?? false;
  }

  /// Publish all sensors
  Future<bool> publishAllSensors() async {
    final response = await _makeApiCall(
      '/api/publish-all-sensors',
      method: 'POST',
    );
    return response?['success'] ?? false;
  }

  /// Get network debug info (using native methods)
  Future<Map<String, dynamic>> getNetworkInfo() async {
    try {
      final linkInfo = await EspNetworkAndroid.linkInfo();
      final capInfo = await EspNetworkAndroid.capInfo();
      final openPorts = await EspNetworkAndroid.scanCommonPorts(
        ESP32_DEFAULT_IP,
      );

      return {
        'link': linkInfo,
        'capabilities': capInfo,
        'openPorts': openPorts,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Disconnect from ESP32
  Future<void> disconnect() async {
    isConnected = false;
    _nativeNetworkBound = false;
    baseUrl = null;
    sessionCookie = null;
    _dio = null;

    // Unbind native network
    await EspNetworkAndroid.unbind();
    print('🔌 Disconnected from ESP32');
  }
}
