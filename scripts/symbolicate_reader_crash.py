"""Match a reader crash to its IPA and preserve app-only symbol evidence.

Usage: python -X utf8 scripts/symbolicate_reader_crash.py --crash <IPS> --ipa <IPA> --out <JSON>
Uses the already installed lief package; never exports device IDs or raw crash contents.
"""
import argparse
import bisect
import hashlib
import json
from pathlib import Path
import tempfile
import uuid
import zipfile

import lief


def read_report(path):
    contents = path.read_bytes()
    text = contents.decode('utf-8')
    decoder = json.JSONDecoder()
    first, end = decoder.raw_decode(text)
    report = decoder.raw_decode(text[end:].lstrip())[0] if 'threads' not in first else first
    return report, hashlib.sha256(contents).hexdigest()


def match_symbols(report, executable):
    image_index, image = next((index, item) for index, item in enumerate(report['usedImages'])
                              if item.get('name') == 'SourceReadSwift')
    binary = lief.MachO.parse(str(executable)).at(0)
    binary_uuid = str(uuid.UUID(bytes=bytes(binary.uuid.uuid)))
    if binary_uuid.lower() != image['uuid'].lower():
        raise ValueError('Crash UUID does not match IPA; refusing misleading symbolication')
    symbols = sorted((symbol.value, symbol.name) for symbol in binary.symbols
                     if symbol.name and symbol.value >= binary.imagebase)
    addresses = [address for address, _ in symbols]
    frames = []
    for index, frame in enumerate(report['threads'][report['faultingThread']]['frames']):
        if frame['imageIndex'] != image_index:
            continue
        offset = frame['imageOffset']
        # A saved return address belongs to the preceding instruction.
        address = binary.imagebase + offset - (4 if index else 0)
        position = bisect.bisect_right(addresses, address) - 1
        if position < 0:
            raise ValueError('No app symbol precedes the crashed instruction')
        symbol_address, symbol = symbols[position]
        frames.append({'frame': index, 'image_offset': hex(offset), 'symbol_offset': hex(symbol_address - binary.imagebase),
                       'instruction_offset': address - symbol_address, 'symbol': symbol})
    return binary_uuid, frames


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['crash', 'ipa', 'out']:
        parser.add_argument('--' + name, required=True, type=Path)
    options = parser.parse_args()
    report, crash_hash = read_report(options.crash)
    with tempfile.TemporaryDirectory(prefix='reader-symbols-') as folder:
        executable = Path(folder) / 'SourceReadSwift'
        with zipfile.ZipFile(options.ipa) as archive:
            executable.write_bytes(archive.read('Payload/SourceReadSwift.app/SourceReadSwift'))
        binary_uuid, frames = match_symbols(report, executable)
    receipt = {'crash_sha256': crash_hash, 'ipa_sha256': hashlib.sha256(options.ipa.read_bytes()).hexdigest(),
               'matched_uuid': binary_uuid, 'exception': {key: report['exception'].get(key)
               for key in ['message', 'type', 'signal']}, 'app_frames': frames}
    options.out.parent.mkdir(parents=True, exist_ok=True)
    options.out.write_text(json.dumps(receipt, indent=2, ensure_ascii=False), encoding='utf-8')
    print('MATCHED', binary_uuid, 'app_frames', len(frames), 'receipt', options.out)
    for frame in frames[:5]:
        print(frame['image_offset'], frame['symbol'].split('LL')[0] + '…', '+', frame['instruction_offset'])


if __name__ == '__main__':
    main()
