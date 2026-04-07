import 'package:dio/dio.dart';

import 'package:face_reader/config/api_config.dart';

abstract class MetaphorRemoteDataSource {
  Future<String> fetchMetaphor(Map<String, dynamic> requestDto);
}

class MetaphorRemoteDataSourceImpl implements MetaphorRemoteDataSource {
  final Dio dio;

  MetaphorRemoteDataSourceImpl(this.dio);

  @override
  Future<String> fetchMetaphor(Map<String, dynamic> requestDto) async {
    final response = await dio.post(
      ApiConfig.metaphorRead,
      data: requestDto,
    );
    return response.data['text'] as String;
  }
}
