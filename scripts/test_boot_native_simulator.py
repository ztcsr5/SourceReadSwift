"""Test the bounded CI simulator retry policy. Usage: python -m unittest discover -s scripts -p test_boot_native_simulator.py"""
import subprocess
import unittest
from unittest.mock import patch

import boot_native_simulator as boot


class NativeSimulatorBootTests(unittest.TestCase):
    def test_cold_migration_can_finish_after_the_previous_180_second_cutoff(self):
        identifier = '00000000-0000-0000-0000-000000000001'

        def wait_for_migration(command, *, check, timeout):
            # The captured CI boot completed at 187 seconds; this is system
            # setup time, before xcodebuild starts any product assertion.
            if timeout < 187:
                raise subprocess.TimeoutExpired(command, timeout)
            return subprocess.CompletedProcess(command, 0)

        with patch.object(boot, 'run', return_value=identifier), patch.object(boot.subprocess, 'run',
            side_effect=wait_for_migration) as status:
            self.assertEqual(boot.boot_fresh('runtime'), identifier)
        self.assertEqual(status.call_count, 1, 'Do not discard a progressing migration and start it again')
        self.assertEqual(status.call_args.kwargs['timeout'], 600, 'Cold setup remains bounded independently of tests')

    def test_headless_boot_does_not_wait_for_the_Simulator_graphical_app(self):
        identifier = '00000000-0000-0000-0000-000000000001'
        commands = []

        def run(command, timeout=30):
            commands.append(command)
            if command[0] == 'open':
                raise subprocess.TimeoutExpired(command, timeout)
            return identifier if command[2] == 'create' else ''

        with patch.object(boot, 'run', side_effect=run), patch.object(boot.subprocess, 'run',
            return_value=subprocess.CompletedProcess([], 0)) as status:
            self.assertEqual(boot.boot_fresh('runtime'), identifier)
        self.assertEqual(status.call_count, 1)
        self.assertFalse(any(command[0] == 'open' for command in commands))

    def test_one_stalled_boot_gets_one_fresh_device_without_shutting_down_others(self):
        identifiers = ['00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002']
        commands = []

        def run(command, timeout=30):
            commands.append(command)
            return identifiers.pop(0) if command[2] == 'create' else ''

        with patch.object(boot, 'run', side_effect=run), patch.object(boot.subprocess, 'run', side_effect=[
            subprocess.TimeoutExpired('bootstatus', 600), subprocess.CompletedProcess([], 0)
        ]) as status:
            self.assertEqual(boot.boot_fresh('runtime'), '00000000-0000-0000-0000-000000000002')
        self.assertEqual(status.call_count, 2)
        self.assertTrue(all(call.kwargs['timeout'] == 600 for call in status.call_args_list))
        shutdowns = [command for command in commands if command[2] == 'shutdown']
        self.assertEqual(shutdowns, [['xcrun', 'simctl', 'shutdown', '00000000-0000-0000-0000-000000000001']])

    def test_two_failures_stop_instead_of_skipping_tests_or_retrying_forever(self):
        identifier = '00000000-0000-0000-0000-000000000001'
        with patch.object(boot, 'run', return_value=identifier), patch.object(boot.subprocess, 'run',
            side_effect=subprocess.TimeoutExpired('bootstatus', 600)) as status:
            with self.assertRaisesRegex(RuntimeError, 'Both fresh simulator boot attempts failed'):
                boot.boot_fresh('runtime')
        self.assertEqual(status.call_count, 2)


if __name__ == '__main__':
    unittest.main()
