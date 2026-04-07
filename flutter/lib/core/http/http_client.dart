import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/config/api_config.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      dev.log(
        '[HTTP REQUEST] ${options.method} ${options.uri}\n'
        'Headers: ${options.headers}\n'
        'Data: ${options.data}',
        name: 'Dio',
      );
      handler.next(options);
    },
    onResponse: (response, handler) {
      dev.log(
        '[HTTP RESPONSE] ${response.statusCode} ${response.requestOptions.uri}\n'
        'Data: ${response.data}',
        name: 'Dio',
      );
      handler.next(response);
    },
    onError: (error, handler) {
      dev.log(
        '[HTTP ERROR] ${error.type} ${error.message}\n'
        'URI: ${error.requestOptions.uri}\n'
        'Status: ${error.response?.statusCode}\n'
        'Response: ${error.response?.data}\n'
        'Stack: ${error.stackTrace}',
        name: 'Dio',
        error: error,
      );
      handler.next(error);
    },
  ));

  return dio;
});
