import concurrent.futures
import json
import socket
import time
import unittest

from tests.mpv_ipc import MpvIPC, MpvScriptMessageEvent


class MpvIPCTest(unittest.TestCase):
    def setUp(self):
        self.ipc = MpvIPC()
        self.ipc._ipc_socket, self.peer = socket.socketpair()
        self.peer.settimeout(2)
        self.reader = self.peer.makefile('rb')
        self.ipc.start()
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=8)

    def tearDown(self):
        self.ipc.stop()
        self.reader.close()
        self.peer.close()
        self.pool.shutdown(wait=True)

    def send(self, *messages):
        self.peer.sendall(b''.join(
            json.dumps(message, ensure_ascii=False).encode() + b'\n'
            for message in messages))

    def command(self):
        return json.loads(self.reader.readline())

    def test_fragmented_utf8_and_newline(self):
        wire = json.dumps({'event': 'client-message', 'args': ['ready', 'café']},
                          ensure_ascii=False).encode() + b'\n'
        split = wire.index('é'.encode()) + 1
        self.peer.sendall(wire[:split])
        self.assertIsNone(self.ipc.wait_for_event('ready', timeout=0.03))
        self.peer.sendall(wire[split:-1])
        self.assertIsNone(self.ipc.wait_for_event('ready', timeout=0.03))
        self.peer.sendall(wire[-1:])
        self.assertEqual(self.ipc.wait_for_event('ready'),
                         MpvScriptMessageEvent(['ready', 'café']))

    def test_coalesced_replies_and_repeated_events_with_cursor(self):
        future = self.pool.submit(self.ipc.send_command, {'command': ['test']})
        request = self.command()
        self.send({'event': 'client-message', 'args': ['ready', 'first']},
                  {'event': 'client-message', 'args': ['ready', 'second']},
                  {'error': 'success', 'request_id': request['request_id'], 'data': 42})
        self.assertEqual(future.result(1).data, 42)
        cursor = self.ipc.event_cursor
        self.assertEqual(cursor, 2)
        self.assertIsNone(self.ipc.wait_for_event('ready', timeout=0.02, after=cursor))
        self.send({'event': 'client-message', 'args': ['ready', 'third']})
        self.assertEqual(self.ipc.wait_for_event('ready', after=cursor).args[1], 'third')
        self.assertEqual(self.ipc.wait_for_event('ready').args[1], 'first')
        self.assertEqual(self.ipc.wait_for_event('ready').args[1], 'second')
        self.assertIsNone(self.ipc.wait_for_event('ready', timeout=0.02))
        self.assertEqual(self.ipc.event_cursor, 3)

    def test_concurrent_commands_and_waiters(self):
        futures = [self.pool.submit(self.ipc.send_command, {'command': [i]})
                   for i in range(6)]
        requests = [self.command() for _ in futures]
        self.assertEqual(len({r['request_id'] for r in requests}), 6)
        self.send(*({'error': 'success', 'request_id': r['request_id'],
                     'data': r['command'][0]} for r in reversed(requests)))
        self.assertEqual([f.result(1).data for f in futures], list(range(6)))
        waiters = [self.pool.submit(self.ipc.wait_for_event, 'ready') for _ in range(2)]
        self.send(*({'event': 'client-message', 'args': ['ready', str(i)]}
                    for i in range(2)))
        self.assertEqual({f.result(1).args[1] for f in waiters}, {'0', '1'})

    def test_timeout_and_late_reply(self):
        start = time.monotonic()
        future = self.pool.submit(self.ipc.send_command, {'command': ['slow']}, 0.05)
        first = self.command()
        with self.assertRaises(TimeoutError):
            future.result(1)
        self.assertLess(time.monotonic() - start, 1)
        next_reply = self.pool.submit(self.ipc.send_command, {'command': ['next']})
        second = self.command()
        self.send({'error': 'success', 'request_id': first['request_id'], 'data': 'late'},
                  {'error': 'success', 'request_id': second['request_id'], 'data': 'next'})
        self.assertEqual(next_reply.result(1).data, 'next')
        self.assertEqual(self.ipc.unanswered_replies[0].data, 'late')
        self.assertEqual(self.ipc._pending_replies, {})

    def test_backpressure_has_bounded_timeout(self):
        self.ipc._ipc_socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
        start = time.monotonic()
        with self.assertRaises(TimeoutError):
            self.ipc.send_command({'command': ['x' * 1000000]}, timeout=0.05)
        self.assertLess(time.monotonic() - start, 1)
        self.assertEqual(self.ipc._pending_replies, {})
        with self.assertRaises(ConnectionError):
            self.ipc.send_command({'command': ['next']})

    def test_disconnect_wakes_pending_callers(self):
        reply = self.pool.submit(self.ipc.send_command, {'command': ['wait']}, 30)
        self.command()
        event = self.pool.submit(self.ipc.wait_for_event, 'missing', 30)
        self.peer.shutdown(socket.SHUT_RDWR)
        for future in (reply, event):
            with self.assertRaises(ConnectionError):
                future.result(1)
        with self.assertRaises(ConnectionError):
            self.ipc.send_command({'command': ['gone']})

    def test_stop_is_idempotent_and_wakes_waiters(self):
        event = self.pool.submit(self.ipc.wait_for_event, 'missing', 30)
        self.ipc.stop()
        self.ipc.stop()
        with self.assertRaises(ConnectionError):
            event.result(1)
        self.assertFalse(self.ipc._read_thread.is_alive())
        fresh = MpvIPC()
        fresh.stop()
        fresh.stop()


if __name__ == '__main__':
    unittest.main()
