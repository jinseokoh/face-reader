import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/core/http/http_client.dart';
import 'package:facely/data/datasources/local/metaphor_local_datasource.dart';
import 'package:facely/data/datasources/remote/metaphor_remote_datasource.dart';
import 'package:facely/data/repositories/metaphor_repository.dart';

// Re-export for convenience
export 'package:facely/core/http/http_client.dart' show dioProvider;

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
