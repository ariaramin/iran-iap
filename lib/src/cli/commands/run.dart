import 'package:iran_iap/src/cli/commands/base.dart';

/// Command to run the Flutter app with the selected store.
class RunCommand extends IranIapCommand {
  @override
  String get name => 'run';
  @override
  String get description => 'Run the Flutter app with the selected store';

  @override
  Future<int> run() async {
    final store = requireStore();
    final project = resolveProject();
    if (project == null) {
      return 66;
    }

    final flutterArgs = ['run', ...argResults!.rest];
    return executeFlutter(project, store, flutterArgs);
  }
}
