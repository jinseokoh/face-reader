import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/core/http/http_client.dart';
import 'package:face_reader/data/datasources/local/metaphor_local_datasource.dart';
import 'package:face_reader/data/datasources/remote/metaphor_remote_datasource.dart';
import 'package:face_reader/data/repositories/metaphor_repository.dart';

// Re-export for convenience
export 'package:face_reader/core/http/http_client.dart' show dioProvider;

// DataSources
final metaphorRemoteDataSourceProvider = Provider<MetaphorRemoteDataSource>(
  (ref) => MetaphorRemoteDataSourceImpl(ref.read(dioProvider)),
);

final metaphorLocalDataSourceProvider = Provider<MetaphorLocalDataSource>(
  (ref) => MetaphorLocalDataSourceImpl(),
);

// Repositories
final metaphorRepositoryProvider = Provider<MetaphorRepository>(
  (ref) => MetaphorRepository(
    remoteDataSource: ref.read(metaphorRemoteDataSourceProvider),
    localDataSource: ref.read(metaphorLocalDataSourceProvider),
  ),
);
