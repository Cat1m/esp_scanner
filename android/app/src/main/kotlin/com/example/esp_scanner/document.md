# ESP32 Network Binding & Threading Documentation

## 📋 Tổng quan

Document này giải thích **TẠI SAO** cần phải viết native Android code để kết nối với ESP32 Access Point thay vì dùng Flutter HTTP trực tiếp.

**Vị trí file:** `android/app/src/main/kotlin/com/example/esp_scanner/EspNetworkPlugin.kt`

---

## 🔥 Hai vấn đề chính

### 1. **Network Routing Issue** 
- Flutter HTTP không thể chọn network interface
- Android tự động route traffic qua cellular thay vì ESP32 WiFi

### 2. **NetworkOnMainThreadException**
- Socket operations bị cấm trên Main Thread từ Android API 11+
- Cần background threading + Handler pattern

---

## 🚫 Problem 1: Network Routing

### ESP32 Access Point Scenario
```
📱 Android Phone
├── 📶 Cellular (có internet) ← Default route
└── 📡 WiFi ESP32 (không internet) ← Cần force route qua đây
```

### Vấn đề: Flutter HTTP Fails
```dart
// ❌ FAIL: Flutter HTTP luôn đi qua cellular
final dio = Dio();
final response = await dio.get('http://192.168.4.1/api/status');
// Result: Timeout hoặc "No route to host"
```

**Root Cause:** 
- ESP32 hoạt động như isolated Access Point (không internet)
- Android detect ESP32 AP là "captive portal" 
- Android OS tự động route HTTP requests qua cellular network
- ESP32 với IP 192.168.4.1 không accessible từ cellular network

### Giải pháp: Network Binding
```kotlin
// ✅ SUCCESS: Force bind process đến ESP32 network
val network = connectToESP32WiFi() // Get ESP32 Network object
cm.bindProcessToNetwork(network)   // Force ALL traffic qua ESP32

// Tạo OkHttpClient với specific SocketFactory
val client = OkHttpClient.Builder()
    .socketFactory(network.socketFactory) // Chỉ định interface
    .build()
```

---

## 🚫 Problem 2: NetworkOnMainThreadException

### Vấn đề: Socket Operations Blocked
```kotlin
// ❌ CRASH: NetworkOnMainThreadException
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    
    // BAD: Chạy trên Main Thread
    val socket = Socket("192.168.4.1", 80) // Exception!
}
```

### Tại sao Android cấm?

1. **ANR (Application Not Responsive)**
   - Network operations có thể block UI 5-10+ seconds
   - User thấy app "đơ" → Force close

2. **Unpredictable Timing**
   - Socket connect có thể instant hoặc timeout
   - WiFi có thể yếu/mất kết nối

3. **User Experience**
   - Main Thread phải luôn responsive cho UI
   - Network I/O phải async

### Giải pháp: Background Thread + Handler
```kotlin
// ✅ SUCCESS: Background thread pattern
private fun rawSocketTest(host: String, port: Int, result: MethodChannel.Result) {
    val network = this.network ?: run {
        result.error("NO_NETWORK", "ESP network not connected", null)
        return
    }
    
    // Background thread cho network I/O
    Thread {
        try {
            val socket = network.socketFactory.createSocket()
            socket.soTimeout = 2000
            socket.connect(InetSocketAddress(host, port), 1500) // Blocking OK
            socket.close()
            
            // Switch back to Main Thread cho UI updates
            postSuccess(result, true)
        } catch (e: Exception) {
            postSuccess(result, false)
        }
    }.start()
}

// Helper: Switch về Main Thread
private fun postSuccess(result: MethodChannel.Result, value: Any) {
    mainHandler.post { result.success(value) } // Main Thread safe
}
```

---

## 💡 Giải pháp hoàn chỉnh

### Architecture Overview
```
Flutter App
     ↓ (MethodChannel)
Native Android Plugin
     ├── Network Binding (cho routing)
     └── Background Threading (cho socket operations)
```

### Step-by-step Implementation

#### 1. **WiFi Connection + Network Binding**
```kotlin
private fun connect(ssid: String, pass: String?, bindProcess: Boolean, result: MethodChannel.Result) {
    // Tạo WifiNetworkSpecifier cho ESP32
    val spec = WifiNetworkSpecifier.Builder()
        .setSsid(ssid)
        .setWpa2Passphrase(pass)
        .build()

    // Request network với NO internet capability
    val request = NetworkRequest.Builder()
        .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
        .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) // KEY!
        .setNetworkSpecifier(spec)
        .build()

    val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            this@EspNetworkPlugin.network = network
            
            // Force bind process đến ESP32 network
            if (bindProcess) {
                cm.bindProcessToNetwork(network) // Critical step!
            }
            
            result.success(true)
        }
    }
    
    cm.requestNetwork(request, callback, 10_000)
}
```

#### 2. **HTTP Client với Specific SocketFactory**
```kotlin
private fun httpClientForEsp(): OkHttpClient {
    val network = this.network ?: throw IllegalStateException("ESP network not connected")
    
    return OkHttpClient.Builder()
        .socketFactory(network.socketFactory) // Force qua ESP32 interface
        .followRedirects(false)
        .build()
}
```

#### 3. **Background Threading cho All Network Operations**
```kotlin
private fun httpGet(url: String, result: MethodChannel.Result) {
    val client = httpClientForEsp()
    val request = Request.Builder().url(url).build()
    
    // OkHttp tự động chạy background, nhưng callback vẫn cần handle
    client.newCall(request).enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            postError(result, "HTTP_ERROR", e.message ?: "failure")
        }
        
        override fun onResponse(call: Call, response: Response) {
            val body = response.body?.string().orEmpty()
            val responseData = mapOf(
                "code" to response.code,
                "body" to body,
                "headers" to response.headers.toMultimap()
            )
            postSuccess(result, responseData) // Back to main thread
        }
    })
}
```

---

## 🚨 Tại sao KHÔNG dùng alternatives?

### ❌ StrictMode.permitAll()
```kotlin
// BAD: Bypass NetworkOnMainThreadException
StrictMode.ThreadPolicy.Builder().permitAll().build()
```
**Vấn đề:** App sẽ ANR và crash khi network chậm

### ❌ Flutter http/dio directly  
```dart
// BAD: Không control được network routing
final response = await dio.get('http://192.168.4.1');
```
**Vấn đề:** Traffic vẫn đi qua cellular, không reach ESP32

### ❌ Tắt Cellular manually
**Vấn đề:** Yêu cầu user intervention, UX tệ

---

## 📱 Testing Scenarios

### Test Cases cần verify:

1. **Multiple Networks Active**
   ```
   ✓ WiFi: ESP32 (no internet)
   ✓ Cellular: 4G/5G (có internet)  
   → HTTP requests phải đi qua ESP32, không cellular
   ```

2. **Background/Foreground Switching**
   ```
   ✓ App background → ESP32 connection maintain
   ✓ App foreground → Network binding vẫn active
   ```

3. **Network Instability**
   ```
   ✓ ESP32 WiFi disconnect → Graceful error handling
   ✓ Weak signal → Timeout handling
   ```

---

## 🔧 Debugging Tips

### Common Issues & Solutions

#### 1. **"No route to host" errors**
```bash
# Check: Traffic có đang đi qua ESP32 không?
adb shell netstat -i
adb shell ip route show
```

#### 2. **NetworkOnMainThreadException still occurs**
```kotlin
// Verify: All socket operations in background?
Thread.currentThread().name // Should NOT be "main"
```

#### 3. **HTTP requests timeout**
```kotlin
// Check: Network binding successful?
val boundNetwork = cm.boundNetworkForProcess
Log.d("ESP", "Bound network: $boundNetwork")
```

### Debug Logging
```kotlin
// Add extensive logging
android.util.Log.d("ESP_PLUGIN", "Network binding: $network")
android.util.Log.d("ESP_PLUGIN", "Socket factory: ${network.socketFactory}")
android.util.Log.d("ESP_PLUGIN", "Request thread: ${Thread.currentThread().name}")
```

---

## 📚 References & Further Reading

### Android Documentation
- [ConnectivityManager.bindProcessToNetwork()](https://developer.android.com/reference/android/net/ConnectivityManager#bindProcessToNetwork(android.net.Network))
- [NetworkCapabilities](https://developer.android.com/reference/android/net/NetworkCapabilities)
- [NetworkOnMainThreadException](https://developer.android.com/reference/android/os/NetworkOnMainThreadException)

### Key Android Concepts
- **Network Interface Selection**: Controlling which network interface handles traffic
- **StrictMode Policies**: Android's main thread protection mechanisms  
- **Handler Pattern**: Safe communication between background and UI threads

---

## 🎯 Kết luận

Native Android code trong `EspNetworkPlugin.kt` **BẮT BUỘC** vì:

1. **Flutter HTTP không support network interface selection**
2. **Android cấm socket operations trên main thread**  
3. **ESP32 AP scenarios cần specific network binding**

Đây không phải "workaround" mà là **proper solution** theo Android architecture guidelines!

---

**Author:** Development Team  
**Last Updated:** $(date)  
**Version:** 1.0