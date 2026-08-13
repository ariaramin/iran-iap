import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iran_iap/src/cli/commands/verify.dart';

import '../bin/iran_iap.dart' as cli;

void main() {
  test('parses global options after the command', () {
    final results = cli.createRunner().parse(const [
      'doctor',
      '--store',
      'bazaar',
      '--project-dir',
      'example',
      '--json',
    ]);

    expect(results.option('store'), 'bazaar');
    expect(results.option('project-dir'), 'example');
    expect(results.command?.flag('json'), isTrue);
  });

  test('passes Flutter options only after the separator', () {
    final results = cli.createRunner().parse(const [
      'build',
      'apk',
      '--store',
      'myket',
      '--',
      '--release',
    ]);

    expect(results.command?.rest, ['apk', '--release']);
  });

  test('rejects unsupported stores', () {
    expect(
      () => cli.createRunner().parse(const [
        'doctor',
        '--store',
        'unsupported',
      ]),
      throwsA(isA<UsageException>()),
    );
  });

  test('verify rejects extra artifact paths', () async {
    await expectLater(
      cli.createRunner().run(const [
        'verify',
        '--store',
        'bazaar',
        'one.apk',
        'two.apk',
      ]),
      throwsA(isA<UsageException>()),
    );
  });

  test('resolves the installed artifact verifier', () async {
    final packageDirectory = await resolveIranIapPackageDirectory(
      packageConfigLocation: File(
        '.dart_tool/package_config.json',
      ).absolute.uri.toString(),
    );

    expect(packageDirectory, isNotNull);
    expect(
      File(
        '${packageDirectory!.path}${Platform.pathSeparator}tool'
        '${Platform.pathSeparator}verify_android_artifact.py',
      ).existsSync(),
      isTrue,
    );
  });

  test('resolves verifier assets for direct script execution', () async {
    final packageDirectory = await resolveIranIapPackageDirectory(
      packageConfigLocation: File(
        'missing-package-config.json',
      ).absolute.uri.toString(),
      scriptUri: File('bin/iran_iap.dart').absolute.uri,
    );

    expect(packageDirectory?.path, Directory.current.absolute.path);
  });

  test('build rejects a conflicting store define before execution', () async {
    await expectLater(
      cli.createRunner().run(const [
        'build',
        'apk',
        '--store',
        'bazaar',
        '--project-dir',
        'example',
        '--',
        '--dart-define=IRAN_IAP_STORE=myket',
      ]),
      throwsA(isA<UsageException>()),
    );
  });
}
