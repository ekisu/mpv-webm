from abc import ABCMeta
from pathlib import Path
import unittest
import subprocess
import json
import uuid
from typing import List
from dataclasses import dataclass
from tests.mpv_ipc import MpvIPC

@dataclass
class MpvEvent:
    event_name: str
    args: list

class BaseTestCase(unittest.TestCase, metaclass=ABCMeta):
    mpv_process: subprocess.Popen
    mpv_ipc: MpvIPC

    def setUp(self) -> None:
        super().setUp()

        # Start a mpv process with the script loaded
        # Use a UUID on the socket to avoid collisions with previous running instances.
        socket_address = f'/tmp/mpvsocket-{str(uuid.uuid4())}'
        script_path = Path('build/webm.lua')
        mpv_process_args = [
            'mpv',
            '-v',
            '--no-config',
            '--vo=null',
            '--ao=null',
            '--load-scripts=no',
            '--idle=yes',
            f'--input-ipc-server={socket_address}',
        ]

        self.mpv_process = subprocess.Popen(
            mpv_process_args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

        self.mpv_ipc = MpvIPC()
        self.mpv_ipc.connect(socket_address)
        self.mpv_ipc.start()
        
        self.mpv_ipc.send_command({
            'command': ['enable_event', 'client-message'],
        })

        self.mpv_ipc.send_command({
            'command': ['load-script', str(script_path.absolute())],
        })

        self.mpv_ipc.wait_for_event('webm-script-loaded')
    
    def tearDown(self) -> None:
        self.mpv_process.terminate()
        self.mpv_ipc.stop()

        super().tearDown()

    def sendCommandToMpv(self, data: dict, timeout: float = 10) -> None:
        return self.mpv_ipc.send_command(data, timeout)
    
    def updateScriptOptions(self, new_options: dict) -> None:
        self.sendCommandToMpv({
            'command': ['script-message', 'mpv-webm-set-options', json.dumps(new_options)],
        })

    def openTestVideoFile(self, path: Path) -> None:
        self.sendCommandToMpv({
            'command': ['loadfile', str(path.absolute()), 'replace'],
        })
        self.waitForEvent('file-loaded')
    
    def sendKeyPress(self, key: str) -> None:
        self.sendCommandToMpv({
            'command': ['keypress', key],
        })
    
    def waitForEvent(self, event_name: str, timeout: float = 5):
        event = self.mpv_ipc.wait_for_event(event_name, timeout)
        if not event:
            self.fail(f'No {event_name} event was fired')
        
        return event
