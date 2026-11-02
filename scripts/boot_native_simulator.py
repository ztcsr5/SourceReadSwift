"""Boot a fresh CI-only iOS simulator; retry one fresh device after migration stalls.

Usage (macOS CI): python3 -u scripts/boot_native_simulator.py <RUNTIME_ID> --output native-device-id.txt
Allows bounded cold-runtime migration before tests; never changes product test timeouts.
"""
import argparse
from pathlib import Path
import subprocess
import uuid

BOOT_READINESS_TIMEOUT = 600


def run(command, timeout=30):
    return subprocess.run(command, check=True, text=True, capture_output=True, timeout=timeout).stdout.strip()


def boot_fresh(runtime):
    last_failure = None
    for attempt in range(2):
        device = run(['xcrun', 'simctl', 'create', f'PaperReaderCI-{attempt + 1}',
                      'com.apple.CoreSimulator.SimDeviceType.iPhone-16', runtime])
        uuid.UUID(device)
        print('BOOT_ATTEMPT', attempt + 1, 'fresh', device, flush=True)
        try:
            run(['xcrun', 'simctl', 'boot', device])
            # simctl owns headless readiness; launching the GUI is neither a
            # readiness check nor reliable on unattended CI login sessions.
            # CI has completed cold migration at 187s. Killing it at 180s and
            # recreating the device restarts that work; allow at most ten minutes.
            subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True,
                           timeout=BOOT_READINESS_TIMEOUT)
            print('BOOT_VERIFIED', device, flush=True)
            return device
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as failure:
            last_failure = failure
            print('BOOT_FAILED', attempt + 1, type(failure).__name__, flush=True)
            # This identifier was created above; never shut down arbitrary runner devices.
            try:
                run(['xcrun', 'simctl', 'shutdown', device])
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as shutdown_failure:
                print('BOOT_CLEANUP_FAILED', type(shutdown_failure).__name__, flush=True)
    raise RuntimeError('Both fresh simulator boot attempts failed; native acceptance is unavailable') from last_failure


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runtime')
    parser.add_argument('--output', type=Path, default=Path('native-device-id.txt'))
    arguments = parser.parse_args()
    if not arguments.output.resolve().is_relative_to(Path.cwd().resolve()):
        raise ValueError('Device ID output must stay inside the CI workspace')
    device = boot_fresh(arguments.runtime)
    arguments.output.write_text(device + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
