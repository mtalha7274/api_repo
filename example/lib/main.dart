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
  String _data = "Loading...";
  final TodoApi _api = TodoApi();

  @override
  void initState() {
    super.initState();
    _api.fetchTodo(
      onData: (data, origin) {
        setState(
          () => _data =
              "Title: ${data['title']}\n Completed: ${data['completed']}",
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("API Example")),
    body: Center(child: Text(_data)),
  );
}

class TodoApi with ApiRepo {
  TodoApi() {
    defaultShowLogs = true; // Global: enable logs
  }

  void fetchTodo({
    required void Function(Map<String, dynamic> data, ResponseOrigin origin)
    onData,
  }) {
    onRequest<Map<String, dynamic>>(
      cachePolicy: CachePolicy.cacheThenNetwork,
      ttl: const Duration(hours: 1), // Local: set TTL to 1 hour
      request: () async {
        final response = await Dio().get(
          'https://jsonplaceholder.typicode.com/todos/1',
        );
        return Map<String, dynamic>.from(response.data as Map);
      },
      onData: onData,
    );
  }
}
