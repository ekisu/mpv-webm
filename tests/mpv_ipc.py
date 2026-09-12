from __future__ import annotations

from dataclasses import dataclass
from abc import ABCMeta
from typing import List, Any, Optional
import socket
import time
import json
import threading
import select

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

class MpvIPC:
    def __init__(self):
        self.fired_events = []
        self.unanswered_replies = []
        self.unmatched_replies = self.unanswered_replies
        self._ipc_socket = None
        self._running = False
        self._read_thread = None
        self._condition = threading.Condition()
        self._send_lock = threading.Lock()
        self._pending_replies = {}
        self._events = []
        self._event_cursor = 0
        self._last_request_id = 0
        self._buffer = bytearray()

    @property
    def event_cursor(self) -> int:
        with self._condition:
            return self._event_cursor

    def connect(self, ipc_socket_filename: str, connection_timeout: float = 5):
        deadline = time.monotonic() + connection_timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Timed out trying to connect to the IPC')
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                sock.settimeout(remaining)
                sock.connect(ipc_socket_filename)
                sock.setblocking(False)
                self._ipc_socket = sock
                return
            except (FileNotFoundError, ConnectionRefusedError):
                sock.close()
                time.sleep(min(0.01, max(0, deadline - time.monotonic())))
            except BaseException:
                sock.close()
                raise

    def _disconnect(self):
        with self._condition:
            self._running = False
            self._condition.notify_all()

    def _process_data(self, data: bytes):
        # Decode only complete lines: even a UTF-8 code point may span recv calls.
        self._buffer.extend(data)
        while b'\n' in self._buffer:
            line, _, rest = self._buffer.partition(b'\n')
            self._buffer = bytearray(rest)
            if not line.strip():
                continue
            response = json.loads(line.decode('utf-8'))
            with self._condition:
                if 'event' in response:
                    event = MpvEvent.from_dict(response)
                    self._event_cursor += 1
                    self.fired_events.append(event)
                    self._events.append((self._event_cursor, event))
                else:
                    reply = MpvReply(**response)
                    if reply.request_id in self._pending_replies:
                        self._pending_replies[reply.request_id] = reply
                    else:
                        self.unanswered_replies.append(reply)
                self._condition.notify_all()

    def _read_loop(self):
        sock = self._ipc_socket
        try:
            while self._running:
                if not select.select([sock], [], [], 0.1)[0]:
                    continue
                try:
                    data = sock.recv(4096)
                except BlockingIOError:
                    continue
                if not data:
                    break
                self._process_data(data)
        except (OSError, ValueError, TypeError, KeyError):
            # A broken connection or invalid protocol must wake every waiter.
            pass
        finally:
            self._disconnect()

    def start(self):
        with self._condition:
            if self._running:
                return
            if self._ipc_socket is None or self._ipc_socket.fileno() < 0:
                raise ConnectionError('IPC is not connected')
            self._ipc_socket.setblocking(False)
            self._running = True
            self._read_thread = threading.Thread(target=self._read_loop)
            self._read_thread.start()

    def stop(self):
        self._disconnect()
        sock = self._ipc_socket
        if sock is not None:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        thread = self._read_thread
        if thread is not None and thread is not threading.current_thread():
            thread.join()
        if sock is not None:
            sock.close()

    def _send(self, data: bytes, deadline: float):
        if not self._send_lock.acquire(timeout=max(0, deadline - time.monotonic())):
            raise TimeoutError('Timed out sending command')
        try:
            sock = self._ipc_socket
            view = memoryview(data)
            while view:
                with self._condition:
                    if not self._running:
                        raise ConnectionError('IPC is disconnected')
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    # A partially sent frame cannot safely be followed by another.
                    self._disconnect()
                    raise TimeoutError('Timed out sending command')
                if not select.select([], [sock], [], min(remaining, 0.1))[1]:
                    continue
                try:
                    sent = sock.send(view)
                except BlockingIOError:
                    continue
                if sent == 0:
                    raise ConnectionError('IPC is disconnected')
                view = view[sent:]
        except TimeoutError:
            raise
        except (OSError, ValueError) as error:
            self._disconnect()
            raise ConnectionError('IPC is disconnected') from error
        finally:
            self._send_lock.release()

    def send_command(self, command_data: dict, timeout: float = 5) -> MpvReply:
        deadline = time.monotonic() + timeout
        with self._condition:
            if not self._running:
                raise ConnectionError('IPC is not running')
            self._last_request_id += 1
            request_id = self._last_request_id
            self._pending_replies[request_id] = None
        try:
            data = json.dumps({**command_data, 'request_id': request_id}).encode('utf-8') + b'\n'
            self._send(data, deadline)
            with self._condition:
                while self._pending_replies[request_id] is None:
                    if not self._running:
                        raise ConnectionError('IPC is disconnected')
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise TimeoutError('Timed out waiting for reply')
                    self._condition.wait(remaining)
                return self._pending_replies[request_id]
        finally:
            with self._condition:
                self._pending_replies.pop(request_id, None)

    def wait_for_event(self, event_name: str, timeout: float = 5,
                       after: Optional[int] = None) -> Optional[MpvEvent]:
        """Consume the oldest matching event, optionally newer than a cursor."""
        deadline = time.monotonic() + timeout
        with self._condition:
            while True:
                for index, (cursor, event) in enumerate(self._events):
                    if event.event_name == event_name and (after is None or cursor > after):
                        self._events.pop(index)
                        return event
                if not self._running:
                    raise ConnectionError('IPC is disconnected')
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return None
                self._condition.wait(remaining)
