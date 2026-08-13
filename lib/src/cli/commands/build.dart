import 'package:iran_iap/src/cli/commands/base.dart';

/// Command to build the Flutter app with the selected store.
class BuildCommand extends IranIapCommand {
  @override
  String get name => 'build';

  @override
  String get description => 'Build the Flutter app with the selected store';

  @override
  Future<int> run() async {
    final store = requireStore();
    final rest = argResults!.rest;
    if (rest.isEmpty || (rest.first != 'apk' && rest.first != 'appbundle')) {
      usageException('Build target required: apk | appbundle');
    }

    final project = resolveProject();
    if (project == null) {
      return 66;
    }

    final flutterArgs = ['build', ...rest];
    return executeFlutter(project, store, flutterArgs);
  }
}
