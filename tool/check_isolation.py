#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / 'android'

checks = [
    (
        ANDROID / 'src' / 'bazaar',
        ['ir.myket', 'ir.mservices.market', 'myket-billing-client'],
        'Bazaar source set contains Myket markers',
    ),
    (
        ANDROID / 'src' / 'myket',
        ['ir.cafebazaar', 'poolakey'],
        'Myket source set contains Bazaar markers',
    ),
]

errors = []

plugin_entry = ANDROID / 'src' / 'main' / 'kotlin' / 'dev' / 'iraniap' / 'IranIapPlugin.kt'
if not plugin_entry.is_file():
    errors.append(
        'Flutter plugin entry point missing from conventional path: '
        'android/src/main/kotlin/dev/iraniap/IranIapPlugin.kt'
    )
else:
    entry_text = plugin_entry.read_text(errors='ignore')
    if 'package dev.iraniap' not in entry_text:
        errors.append('IranIapPlugin.kt package does not match pubspec package dev.iraniap')
    if 'class IranIapPlugin' not in entry_text:
        errors.append('IranIapPlugin.kt does not define class IranIapPlugin')

for directory, forbidden, label in checks:
    text = '\n'.join(
        path.read_text(errors='ignore')
        for path in directory.rglob('*')
        if path.is_file()
    ).lower()
    for token in forbidden:
        if token.lower() in text:
            errors.append(f'{label}: {token}')

build = (ANDROID / 'build.gradle').read_text().lower()
required = [
    "selectedstore == 'bazaar'",
    "selectedstore == 'myket'",
    'poolakey:poolakey:2.2.0',
    'myket-billing-client:1.19',
    'src/${selectedstore}/kotlin',
]
for token in required:
    if token.lower() not in build:
        errors.append(f'Missing build isolation marker: {token}')

pubspec = (ROOT / 'pubspec.yaml').read_text().lower()
for forbidden_dep in ['iran_iap_bazaar:', 'iran_iap_myket:', 'myket_iap:', 'flutter_poolakey:']:
    if forbidden_dep in pubspec:
        errors.append(f'Forbidden Dart dependency in public package: {forbidden_dep}')

example_pubspec = (ROOT / 'example' / 'pubspec.yaml').read_text().lower()
for forbidden_dep in ['iran_iap_bazaar:', 'iran_iap_myket:', 'myket_iap:', 'flutter_poolakey:']:
    if forbidden_dep in example_pubspec:
        errors.append(f'Forbidden provider dependency in example: {forbidden_dep}')

if 'rootproject.subprojects' in build:
    errors.append('Plugin build.gradle must not mutate consuming application subprojects')

if errors:
    print('\n'.join(f'ERROR: {error}' for error in errors), file=sys.stderr)
    raise SystemExit(1)

print('Source/dependency isolation checks passed.')
