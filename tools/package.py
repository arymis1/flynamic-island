#!/usr/bin/env python3
"""Build a DMG from a clean temporary directory containing only the app."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import subprocess
import tempfile


def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def manifest(app):
    return {str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in app.rglob('*') if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    assert app.name in {'FLYnamic Island.app', 'FLYnamic YT Music.app'} and app.is_dir(), 'Expected a FLYnamic application'
    default_name = 'FLYnamic-YT-Music.dmg' if app.name == 'FLYnamic YT Music.app' else 'FLYnamic-Island.dmg'
    output = (args.output or Path.cwd() / 'release' / default_name).resolve()
    run('codesign', '--verify', '--deep', '--strict', str(app))
    original = manifest(app)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='flynamic-package-') as folder:
        workspace = Path(folder)
        stage = workspace / 'contents'
        stage.mkdir()
        run('ditto', str(app), str(stage / app.name))
        assert [p.name for p in stage.iterdir()] == [app.name]
        image = workspace / 'FLYnamic-Island.dmg'
        run('hdiutil', 'create', '-volname', app.stem, '-srcfolder', str(stage),
            '-format', 'UDZO', '-ov', str(image))
        mount = workspace / 'verify'
        mount.mkdir()
        run('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(image))
        try:
            visible = sorted(p.name for p in mount.iterdir() if not p.name.startswith('.'))
            assert visible == [app.name], f'Unexpected installer files: {visible}'
            packaged = mount / app.name
            run('codesign', '--verify', '--deep', '--strict', str(packaged))
            assert manifest(packaged) == original, 'Packaged application differs from the source'
            version = plistlib.loads((packaged / 'Contents/Info.plist').read_bytes())['CFBundleVersion']
        finally:
            run('hdiutil', 'detach', str(mount))
        # Publish only after inspecting the mounted image and its signature.
        run('ditto', str(image), str(output))
    print(f'Verified: only {app.name}; original app bytes and signature preserved; build {version}.')
    print(output)


if __name__ == '__main__':
    main()
