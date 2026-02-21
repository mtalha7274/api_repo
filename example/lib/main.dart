import 'package:api_repo/data/managers/cache_policy.dart';
import 'package:flutter/material.dart';
import 'package:api_repo/api_repo.dart';
import 'package:dio/dio.dart';

Future<void> main() async {
  runApp(const MaterialApp(home: ApiRepoExample()));
}

class ApiRepoExample extends StatefulWidget {
  const ApiRepoExample({super.key});

  @override
  State<ApiRepoExample> createState() => _ApiRepoExampleState();
}

class _ApiRepoExampleState extends State<ApiRepoExample> {
  String _data = 'Loading...';
  final _api = TodoApi();

  @override
  void initState() {
    super.initState();
    _api.fetchTodo(
      onData: (data, origin) {
        setState(
          () => _data =
              'Title: ${data['title']}\nCompleted: ${data['completed']}',
        );
      },
      onError: (e, st) {
        setState(() => _data = 'Error: $e');
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('API Example')),
    body: Center(child: Text(_data)),
  );
}

class TodoApi with ApiRepo {
  TodoApi() {
    defaultShowLogs = true;
  }

  Future<Map<String, dynamic>?> fetchTodo({
    void Function(Map<String, dynamic> data, ResponseOrigin origin)? onData,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    return await onRequest<Map<String, dynamic>>(
      cachePolicy: CachePolicy.cacheThenNetwork,
      ttl: const Duration(hours: 1),
      request: () async {
        final response = await Dio().get(
          'https://jsonplaceholder.typicode.com/todos/1',
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        return Map<String, dynamic>.from(response.data as Map);
      },
      onData: onData,
      onError: onError,
    );
  }
}
