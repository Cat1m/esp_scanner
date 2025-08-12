import 'dart:io';
import 'package:flutter/services.dart';

class EspNetworkAndroid {
  static const _ch = MethodChannel('esp.network');

  static Future<bool> connect({
    required String ssid,
    String? password,
    bool bindProcess = false,
  }) async {
    if (!Platform.isAndroid) return false;
    final ok = await _ch.invokeMethod<bool>('connect', {
      'ssid': ssid,
      'password': password,
      'bindProcess': bindProcess,
    });
    return ok == true;
  }

  static Future<void> unbind() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('unbind');
  }

  static Future<Map<String, dynamic>> httpGet(String url) async {
    final res = await _ch.invokeMethod('httpGet', {'url': url});
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> httpGetWithHeaders(
    String url,
    Map<String, String> headers,
  ) async {
    final res = await _ch.invokeMethod('httpGetWithHeaders', {
      'url': url,
      'headers': headers,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> httpPostJson(
    String url,
    String body,
  ) async {
    final res = await _ch.invokeMethod('httpPostJson', {
      'url': url,
      'body': body,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> httpPostJsonWithHeaders(
    String url,
    String body,
    Map<String, String> headers,
  ) async {
    final res = await _ch.invokeMethod('httpPostJsonWithHeaders', {
      'url': url,
      'body': body,
      'headers': headers,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> httpPostFormData(
    String url,
    String formData,
  ) async {
    final res = await _ch.invokeMethod('httpPostFormData', {
      'url': url,
      'formData': formData,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> httpPostMultipartFormData(
    String url,
    String formData,
  ) async {
    final res = await _ch.invokeMethod('httpPostMultipartFormData', {
      'url': url,
      'formData': formData,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<bool> rawSocketTest(String host, int port) async {
    final ok = await _ch.invokeMethod<bool>('rawSocketTest', {
      'host': host,
      'port': port,
    });
    return ok == true;
  }

  static Future<Map<String, dynamic>> linkInfo() async {
    final res = await _ch.invokeMethod('linkInfo');
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> capInfo() async {
    final res = await _ch.invokeMethod('capInfo');
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<Map<String, dynamic>> rawSocketTestVerbose(
    String host,
    int port,
  ) async {
    final res = await _ch.invokeMethod('rawSocketTestVerbose', {
      'host': host,
      'port': port,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<List<int>> scanCommonPorts(String host) async {
    final res = await _ch.invokeMethod('scanCommonPorts', {'host': host});
    final map = Map<String, dynamic>.from(res as Map);
    return (map['open'] as List).map((e) => e as int).toList();
  }
}
