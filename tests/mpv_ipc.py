from __future__ import annotations

from dataclasses import dataclass
from abc import ABCMeta
from typing import Dict, List, Any, Mapping, Optional
import socket
import time
import json
import threading

@dataclass(frozen=True, eq=True)
class MpvEvent(metaclass=ABCMeta):
    @staticmethod
    def from_dict(data: dict) -> MpvEvent:
        if data['event'] == 'client-message':
            return MpvScriptMessageEvent(data['args'])
        else:
            return MpvGenericEvent(data['event'])

@dataclass(frozen=True, eq=True)
class MpvScriptMessageEvent(MpvEvent):
    args: List[str]

    @property
    def event_name(self) -> str:
        return self.args[0]

@dataclass(frozen=True, eq=True)
class MpvGenericEvent(MpvEvent):
    event_name: str

@dataclass(frozen=True, eq=True)
class MpvReply():
    error: str
    request_id: Optional[int]
    data: Optional[Any] = None

# TODO Rework this awful naming scheme?
class MpvIPC:
    fired_events: List[MpvEvent]
    unmatched_replies: List[MpvReply]

    _ipc_socket: Optional[socket.socket]
    _running: bool
    _pending_request_events: Dict[int, threading.Event]
    # ??????????
    _pending_event_events: Dict[str, threading.Event]
    _pending_request_replies: Dict[int, MpvReply]
    _pending_event_replies: Dict[str, MpvEvent]
    _read_thread: Optional[threading.Thread]
    _last_request_id: int

    def __init__(self):
        self.fired_events = []
        self.unanswered_replies = []
        
        self._ipc_socket = None
        self._running = False
        self._pending_request_events = {}
        self._pending_event_events = {}
        self._pending_request_replies = {}
        self._pending_event_replies = {}
        self._read_thread = None
        self._last_request_id = 0

    def connect(self, ipc_socket_filename: str, connection_timeout: float = 5):
        self._ipc_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection_start = time.time()

        while time.time() - connection_start < connection_timeout:
            try:
                self._ipc_socket.connect(ipc_socket_filename)
                self._ipc_socket.settimeout(0.1)

                return
            except FileNotFoundError:
                pass
            except ConnectionRefusedError:
                pass
        
        raise TimeoutError('Timed out trying to connect to the IPC')
    
    def _send_to_ipc_socket(self, data: dict) -> None:
        if not self._running:
            raise ConnectionError('IPC is not running')

        self._ipc_socket.send(json.dumps(data).encode('utf-8') + b'\n')
    
    def _process_data(self, data: bytes):
        lines = data.decode('utf-8').split('\n')
        json_responses = [json.loads(line) for line in lines if line.strip() != '']

        new_events = [MpvEvent.from_dict(response) for response in json_responses if 'event' in response]
        new_replies = [MpvReply(**reply) for reply in json_responses if 'event' not in reply]

        replies_for_pending_requests = {reply.request_id: reply for reply in new_replies if reply.request_id in self._pending_request_events}
        new_unanswered_replies = [reply for reply in new_replies if reply.request_id not in self._pending_request_events]

        replies_for_pending_events = {event.event_name: event for event in new_events if event.event_name in self._pending_event_events}

        self.fired_events.extend(new_events)
        self.unanswered_replies.extend(new_unanswered_replies)

        # Fire events for pending requests
        self._pending_request_replies.update(replies_for_pending_requests)
        for request_id, _ in replies_for_pending_requests.items():
            event = self._pending_request_events.pop(request_id)
            event.set()

        self._pending_event_replies.update(replies_for_pending_events)
        for new_event in new_events:
            if new_event.event_name in self._pending_event_events:
                event = self._pending_event_events.pop(new_event.event_name)
                event.set()

    def _read_loop(self):
        try:
            while self._running:
                try:
                    data = self._ipc_socket.recv(4096)

                    self._process_data(data)
                except socket.timeout:
                    pass
        finally:
            self._running = False
    
    def start(self):
        self._running = True
        self._read_thread = threading.Thread(target=self._read_loop)
        self._read_thread.start()
    
    def stop(self):
        self._running = False
        self._read_thread.join()

        self._ipc_socket.close()
    
    def send_command(self, command_data: dict, timeout: float = 5) -> MpvReply:
        new_request_id = self._last_request_id + 1
        command_with_request_id = {**command_data, 'request_id': new_request_id}

        event = threading.Event()
        self._pending_request_events[new_request_id] = event

        self._send_to_ipc_socket(command_with_request_id)
        self._last_request_id = new_request_id
        got_reply = event.wait(timeout)

        if not got_reply:
            raise TimeoutError('Timed out waiting for reply')

        return self._pending_request_replies[new_request_id]

    def wait_for_event(self, event_name: str, timeout: float = 5) -> Optional[MpvEvent]:
        if any(event.event_name == event_name for event in self.fired_events):
            return True
        
        event = threading.Event()
        self._pending_event_events[event_name] = event
        got_reply = event.wait(timeout)

        if not got_reply:
            return None
        
        return self._pending_event_replies[event_name]
