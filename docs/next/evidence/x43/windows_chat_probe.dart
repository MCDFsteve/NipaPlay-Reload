import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/chat/chat_host.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args[0]);
  final home = await Directory('${root.path}/codex-home').create(recursive: true);
  await File('${home.path}/config.toml').writeAsString('');
  final repository = await Directory('${root.path}/harness').create(recursive: true);
  final endpoint = AgentEndpoint(harness: Harness([]), seed: {},
      appVersion: 'x43-probe', credentialFile: File('${root.path}/endpoint.json'),
      seedRepository: Directory('${root.path}/seed'));
  final chat = ChatHost(endpoint: endpoint, repository: repository,
      labRoot: root, codexExecutable: args[1]);
  try {
    await chat.start();
    stdout.writeln(jsonEncode({'available': chat.available,
      'pid': chat.processId, 'codexHome': chat.launchEnvironment['CODEX_HOME'],
      'transport': 'stdio', 'threadCreated': false, 'turnStarted': false}));
  } finally {
    final childPid = chat.processId;
    await chat.close();
    stdout.writeln(jsonEncode({'closedPid': childPid}));
  }
}
