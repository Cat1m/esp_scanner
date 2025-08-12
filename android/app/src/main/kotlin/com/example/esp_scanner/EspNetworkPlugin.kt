package com.example.esp_scanner

import android.content.Context
import android.net.*
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import okhttp3.*
import java.io.IOException
import javax.net.SocketFactory
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.InetSocketAddress
import java.net.URLDecoder
import okio.Buffer

class EspNetworkPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "esp.network")
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var network: Network? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> {
                val ssid = call.argument<String>("ssid")
                val pass = call.argument<String>("password")
                val bindProcess = call.argument<Boolean>("bindProcess") ?: false
                if (ssid.isNullOrBlank()) {
                    result.error("ARG", "ssid is required", null); return
                }
                connect(ssid, pass, bindProcess, result)
            }
            "linkInfo" -> linkInfo(result)
            "capInfo"  -> capInfo(result)
            "unbind" -> {
                unbind()
                result.success(true)
            }
            "httpGet" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) { result.error("ARG","url is required",null); return }
                httpGet(url, result)
            }
            "httpGetWithHeaders" -> {
                val url = call.argument<String>("url")
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                if (url.isNullOrBlank()) { result.error("ARG","url is required",null); return }
                httpGetWithHeaders(url, headers, result)
            }
            "httpPostJson" -> {
                val url = call.argument<String>("url")
                val body = call.argument<String>("body") ?: ""
                if (url.isNullOrBlank()) { result.error("ARG","url is required",null); return }
                httpPostJson(url, body, result)
            }
            "httpPostJsonWithHeaders" -> {
                val url = call.argument<String>("url")
                val body = call.argument<String>("body") ?: ""
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                if (url.isNullOrBlank()) { result.error("ARG","url is required",null); return }
                httpPostJsonWithHeaders(url, body, headers, result)
            }
            "httpPostFormData" -> {
                val url = call.argument<String>("url")
                val formData = call.argument<String>("formData") ?: ""
                if (url.isNullOrBlank()) { result.error("ARG","url is required",null); return }
                httpPostFormData(url, formData, result)
            }
            "httpPostMultipartFormData" -> {
                val url = call.argument<String>("url")
                val formData = call.argument<String>("formData") ?: ""
                if (url.isNullOrBlank()) { result.error("ARG","url is required",null); return }
                httpPostMultipartFormData(url, formData, result)
            }
            "rawSocketTest" -> {
                val host = call.argument<String>("host")
                val port = call.argument<Int>("port") ?: 80
                if (host.isNullOrBlank()) { result.error("ARG","host is required",null); return }
                rawSocketTest(host, port, result)
            }
            "rawSocketTestVerbose" -> {
                val host = call.argument<String>("host")
                val port = call.argument<Int>("port") ?: 80
                if (host.isNullOrBlank()) { result.error("ARG","host is required",null); return }
                rawSocketTestVerbose(host, port, result)
            }
            "scanCommonPorts" -> {
                val host = call.argument<String>("host")
                if (host.isNullOrBlank()) { result.error("ARG","host is required",null); return }
                scanCommonPorts(host, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun connect(ssid: String, pass: String?, bindProcess: Boolean, result: MethodChannel.Result) {
        callback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        callback = null
        network = null

        val specBuilder = WifiNetworkSpecifier.Builder().setSsid(ssid)
        if (!pass.isNullOrEmpty()) specBuilder.setWpa2Passphrase(pass)
        val spec = specBuilder.build()

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(spec)
            .build()

        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) {
                network = n
                if (bindProcess) cm.bindProcessToNetwork(n)
                mainHandler.postDelayed({ postSuccess(result, true) }, 1000)
            }
            override fun onUnavailable() { postSuccess(result, false) }
            override fun onLost(n: Network) { if (network == n) network = null }
        }
        callback = cb
        cm.requestNetwork(request, cb, 10_000)
    }

    private fun linkInfo(result: MethodChannel.Result) {
        val n = network ?: run { result.error("NO_NETWORK","ESP network not connected",null); return }
        val lp = cm.getLinkProperties(n)
        val data = mapOf(
            "ifName" to (lp?.interfaceName ?: ""),
            "addresses" to (lp?.linkAddresses?.map { it.address.hostAddress } ?: emptyList()),
            "routes" to (lp?.routes?.map { it.toString() } ?: emptyList()),
            "dns" to (lp?.dnsServers?.map { it.hostAddress } ?: emptyList())
        )
        result.success(data)
    }

    private fun capInfo(result: MethodChannel.Result) {
        val n = network ?: run { result.error("NO_NETWORK","ESP network not connected",null); return }
        val nc = cm.getNetworkCapabilities(n)
        val caps = mutableListOf<String>()
        if (nc != null) {
            if (nc.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) caps.add("WIFI")
            if (nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) caps.add("INTERNET")
            if (nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) caps.add("VALIDATED")
            if (nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_TRUSTED)) caps.add("TRUSTED")
            if (nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)) caps.add("NOT_RESTRICTED")
        }
        result.success(mapOf("caps" to caps))
    }

    private fun httpClientForEsp(followRedirects: Boolean = true): OkHttpClient {
        val n = network ?: throw IllegalStateException("ESP network not connected")
        val sf: SocketFactory = n.socketFactory
        return OkHttpClient.Builder()
            .socketFactory(sf)
            .followRedirects(followRedirects)
            .followSslRedirects(followRedirects)
            .build()
    }

    private fun httpGet(url: String, result: MethodChannel.Result) {
        val client = try { httpClientForEsp() } catch (e: Exception) {
            result.error("NO_NETWORK", e.message, null); return
        }
        val req = Request.Builder().url(url).get().build()
        client.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                postError(result, "HTTP_ERROR", e.message ?: "failure")
            }
            override fun onResponse(call: Call, response: Response) {
                val body = response.body?.string().orEmpty()
                val map = hashMapOf(
                    "code" to response.code,
                    "body" to body,
                    "headers" to response.headers.toMultimap()
                )
                postSuccess(result, map)
            }
        })
    }

    private fun httpGetWithHeaders(url: String, headers: Map<String, String>, result: MethodChannel.Result) {
        val client = try { httpClientForEsp() } catch (e: Exception) {
            result.error("NO_NETWORK", e.message, null); return
        }
        val reqBuilder = Request.Builder().url(url).get()
        headers.forEach { (key, value) -> reqBuilder.addHeader(key, value) }
        val req = reqBuilder.build()
        
        client.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                postError(result, "HTTP_ERROR", e.message ?: "failure")
            }
            override fun onResponse(call: Call, response: Response) {
                val body = response.body?.string().orEmpty()
                val map = hashMapOf(
                    "code" to response.code,
                    "body" to body,
                    "headers" to response.headers.toMultimap()
                )
                postSuccess(result, map)
            }
        })
    }

    private fun httpPostJson(url: String, body: String, result: MethodChannel.Result) {
        val client = try { httpClientForEsp() } catch (e: Exception) {
            result.error("NO_NETWORK", e.message, null); return
        }
        val reqBody = body.toRequestBody("application/json; charset=utf-8".toMediaType())
        val req = Request.Builder().url(url).post(reqBody).build()
        client.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                postError(result, "HTTP_ERROR", e.message ?: "failure")
            }
            override fun onResponse(call: Call, response: Response) {
                val text = response.body?.string().orEmpty()
                val map = hashMapOf(
                    "code" to response.code,
                    "body" to text,
                    "headers" to response.headers.toMultimap()
                )
                postSuccess(result, map)
            }
        })
    }

    private fun httpPostJsonWithHeaders(url: String, body: String, headers: Map<String, String>, result: MethodChannel.Result) {
        val client = try { httpClientForEsp() } catch (e: Exception) {
            result.error("NO_NETWORK", e.message, null); return
        }
        val reqBody = body.toRequestBody("application/json; charset=utf-8".toMediaType())
        val reqBuilder = Request.Builder().url(url).post(reqBody)
        headers.forEach { (key, value) -> reqBuilder.addHeader(key, value) }
        val req = reqBuilder.build()
        
        client.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                postError(result, "HTTP_ERROR", e.message ?: "failure")
            }
            override fun onResponse(call: Call, response: Response) {
                val text = response.body?.string().orEmpty()
                val map = hashMapOf(
                    "code" to response.code,
                    "body" to text,
                    "headers" to response.headers.toMultimap()
                )
                postSuccess(result, map)
            }
        })
    }

    private fun httpPostFormData(url: String, formData: String, result: MethodChannel.Result) {
    val client = try { 
        httpClientForEsp(followRedirects = false)
    } catch (e: Exception) {
        result.error("NO_NETWORK", e.message, null); return
    }
    
    android.util.Log.d("ESP_PLUGIN", "Raw formData received: $formData")
    
    val formBuilder = FormBody.Builder()
    formData.split("&").forEach { pair ->
        val parts = pair.split("=", limit = 2)
        if (parts.size == 2) {
            val key = parts[0]
            val value = java.net.URLDecoder.decode(parts[1], "UTF-8")
            android.util.Log.d("ESP_PLUGIN", "Adding form field: $key = $value")
            formBuilder.add(key, value)
        }
    }
    
    val reqBody = formBuilder.build()
    
    val req = Request.Builder()
        .url(url)
        .post(reqBody)
        .addHeader("Content-Type", "application/x-www-form-urlencoded") // ← FIX: Thêm header này
        .build()
    
    // Log để verify header được thêm
    android.util.Log.d("ESP_PLUGIN", "Request headers: ${req.headers}")
    
    client.newCall(req).enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            android.util.Log.e("ESP_PLUGIN", "Request failed: ${e.message}")
            postError(result, "HTTP_ERROR", e.message ?: "failure")
        }
        override fun onResponse(call: Call, response: Response) {
            val text = response.body?.string().orEmpty()
            android.util.Log.d("ESP_PLUGIN", "Response code: ${response.code}")
            android.util.Log.d("ESP_PLUGIN", "Response body: $text")
            
            val map = hashMapOf(
                "code" to response.code,
                "body" to text,
                "headers" to response.headers.toMultimap()
            )
            postSuccess(result, map)
        }
    })
}

    private fun httpPostMultipartFormData(url: String, formData: String, result: MethodChannel.Result) {
        val client = try { httpClientForEsp(followRedirects = false) } catch (e: Exception) {
            result.error("NO_NETWORK", e.message, null); return
        }
        
        // Try multipart form data instead of URL-encoded
        val formBuilder = MultipartBody.Builder().setType(MultipartBody.FORM)
        
        // Parse form data and add as form fields
        formData.split("&").forEach { pair ->
            val parts = pair.split("=", limit = 2)
            if (parts.size == 2) {
                val key = parts[0]
                val value = parts[1]
                formBuilder.addFormDataPart(key, value)
            }
        }
        
        val reqBody = formBuilder.build()
        val req = Request.Builder().url(url).post(reqBody).build()
        
        client.newCall(req).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                postError(result, "HTTP_ERROR", e.message ?: "failure")
            }
            override fun onResponse(call: Call, response: Response) {
                val text = response.body?.string().orEmpty()
                val map = hashMapOf(
                    "code" to response.code,
                    "body" to text,
                    "headers" to response.headers.toMultimap()
                )
                postSuccess(result, map)
            }
        })
    }

    private fun rawSocketTestVerbose(host: String, port: Int, result: MethodChannel.Result) {
        val n = network
        if (n == null) { 
            result.success(mapOf("ok" to false, "error" to "NO_NETWORK")); return 
        }
        
        // Run on background thread to avoid NetworkOnMainThreadException
        Thread {
            try {
                val s = n.socketFactory.createSocket()
                s.soTimeout = 2000
                s.connect(InetSocketAddress(host, port), 1500)
                s.close()
                postSuccess(result, mapOf("ok" to true))
            } catch (e: Exception) {
                postSuccess(result, mapOf("ok" to false, "error" to "${e.javaClass.simpleName}: ${e.message}"))
            }
        }.start()
    }

    private fun scanCommonPorts(host: String, result: MethodChannel.Result) {
        val n = network
        if (n == null) { 
            result.success(mapOf("open" to emptyList<Int>(), "error" to "NO_NETWORK")); return 
        }
        
        // Run on background thread
        Thread {
            val ports = listOf(80, 8080, 5000, 1880, 1883, 8266)
            val open = mutableListOf<Int>()
            for (p in ports) {
                try {
                    val s = n.socketFactory.createSocket()
                    s.soTimeout = 800
                    s.connect(InetSocketAddress(host, p), 600)
                    s.close()
                    open.add(p)
                } catch (_: Exception) { /* closed */ }
            }
            postSuccess(result, mapOf("open" to open))
        }.start()
    }

    private fun rawSocketTest(host: String, port: Int, result: MethodChannel.Result) {
        val n = network
        if (n == null) { result.error("NO_NETWORK","ESP network not connected",null); return }
        
        // Run on background thread
        Thread {
            try {
                val s = n.socketFactory.createSocket()
                s.soTimeout = 2000
                s.connect(InetSocketAddress(host, port), 600)
                s.close()
                postSuccess(result, true)
            } catch (e: Exception) {
                postSuccess(result, false)
            }
        }.start()
    }

    private fun unbind() {
        callback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        callback = null
        cm.bindProcessToNetwork(null) // Unbind process
        network = null
    }

    private fun postSuccess(result: MethodChannel.Result, value: Any) {
        mainHandler.post { result.success(value) }
    }
    
    private fun postError(result: MethodChannel.Result, code: String, msg: String) {
        mainHandler.post { result.error(code, msg, null) }
    }
}