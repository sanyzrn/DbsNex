#!/usr/bin/env python3
"""Verify actual APK identities, version codes and ABI update coverage."""
import argparse
import re
import subprocess
from pathlib import Path

VARIANTS = ('universal', 'armeabi-v7a', 'arm64-v8a', 'x86_64', 'store')


def metadata(apk, build_tools):
    badging = subprocess.check_output([str(build_tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)'", badging, re.M)
    native = re.search(r'^native-code:\s*(.*)$', badging, re.M)
    certs = subprocess.check_output([str(build_tools / 'apksigner'), 'verify', '--print-certs', str(apk)], text=True)
    signer = re.findall(r'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', certs)
    if not package or not signer or not native:
        raise ValueError(f'{apk}: missing package, versionCode, native ABIs or verified signer')
    return {'id': package[1], 'code': int(package[2]), 'signers': set(x.lower() for x in signer),
            'abis': set(re.findall(r"'([^']+)'", native[1]))}


def verify(previous, current):
    if 'universal' not in previous or set(current) != set(VARIANTS):
        raise ValueError('Previous universal and all five current APK variants are required')
    identity = previous['universal']
    if identity['id'] != 'com.sanyzrn.nex':
        raise ValueError('Previous package identity is unexpected')
    maximum = max(apk['code'] for apk in previous.values())
    for variant, apk in previous.items():
        if apk['id'] != identity['id'] or not apk['signers'] or apk['signers'] != identity['signers']:
            raise ValueError(f'Previous {variant}: inconsistent package or signer')
    for variant, apk in current.items():
        if apk['id'] != identity['id'] or not apk['signers'] or apk['signers'] != identity['signers']:
            raise ValueError(f'{variant}: package or signer changed')
        # Even the new universal/store must outrank every previously shipped
        # split APK; comparing only universal-to-universal missed a real bug.
        if apk['code'] <= maximum:
            raise ValueError(f'{variant}: versionCode {apk["code"]} must exceed previous maximum {maximum}')
        if variant in previous and not previous[variant]['abis'] <= apk['abis']:
            raise ValueError(f'{variant}: removed a previously supported ABI')
        if variant not in ('universal', 'store') and variant not in apk['abis']:
            raise ValueError(f'{variant}: APK does not contain its advertised ABI')
    old_abis = set().union(*(x['abis'] for x in previous.values()))
    for variant in ('universal', 'store'):
        if not old_abis <= current[variant]['abis']:
            raise ValueError(f'{variant}: does not update every previously supported ABI')


def collect(directory, build_tools):
    result = {}
    for apk in directory.glob('*.apk'):
        variant = next((v for v in VARIANTS if apk.name.endswith(f'-{v}.apk')), None)
        if variant is None or variant in result:
            raise ValueError(f'Unknown or duplicate APK variant: {apk.name}')
        result[variant] = metadata(apk, build_tools)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--previous', type=Path, required=True)
    parser.add_argument('--current', type=Path, required=True)
    parser.add_argument('--build-tools', type=Path, required=True)
    args = parser.parse_args()
    verify(collect(args.previous, args.build_tools), collect(args.current, args.build_tools))
    print('All APK variants preserve identity, advance versionCode and cover previous ABIs.')


if __name__ == '__main__':
    main()
