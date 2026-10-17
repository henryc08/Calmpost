"""USB/network separation with deterministic fake I/O; no hardware or secrets."""
from collections import deque
from threading import Event

import pytest
import requests

from scripts import serial_bridge as bridge


class Response:
    def __init__(self, status=200, body=None):
        self.status_code = status
        self.text = "test response"
        self.body = body

    def json(self):
        return self.body


class Session:
    def __init__(self, post):
        self.post = post
        self.closed = False

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.closed = True


def sample(n):
    return bridge.to_payload({'moisture_raw': n}, 'test-bin')


def test_slow_upload_does_not_block_serial_reads(monkeypatch):
    entered, release, all_sent = Event(), Event(), Event()
    sent = []

    def post(url, *, json, headers, timeout):
        assert timeout == 10
        if not sent:
            entered.set()
            assert release.wait(3)
        sent.append(dict(json))
        if len(sent) == 3:
            all_sent.set()
        return Response()

    class Serial:
        def __init__(self, *args, **kwargs):
            self.n = 0

        def __enter__(self):
            return self

        def __exit__(self, *_):
            pass

        def readline(self):
            self.n += 1
            if self.n == 2:
                assert entered.wait(3)  # First HTTP request is still blocked.
            if self.n == 4:
                assert worker.queue.qsize() == 2
                assert not sent
                raise KeyboardInterrupt
            return ('{"moisture_raw": %d}\n' % self.n).encode()

    monkeypatch.setattr(bridge.serial, 'Serial', Serial)
    session = Session(post)
    with bridge.UploadWorker('test-url', {}, session_factory=lambda: session) as worker:
        try:
            bridge.read_serial('fake-port', 115200, 'test-bin', worker)
        finally:
            release.set()
        assert all_sent.wait(3)
    assert [p['moisture_raw'] for p in sent] == [1, 2, 3]
    assert all(p['time'] for p in sent)
    assert session.closed


def test_retry_preserves_order_and_timestamp_without_new_serial_input():
    done = Event()
    calls = []
    first, second = sample(10), sample(20)

    def post(url, *, json, **kwargs):
        calls.append(dict(json))
        if len(calls) == 1:
            raise requests.Timeout('fake timeout')
        if len(calls) == 3:
            done.set()
        return Response(body={'moisture_pct': 50})

    with bridge.UploadWorker('test-url', {}, retry_delay=0.01,
                             session_factory=lambda: Session(post)) as worker:
        worker.submit(first)
        worker.submit(second)
        assert done.wait(3)
    assert calls == [first, first, second]


def test_queue_is_bounded_and_reports_dropped_samples(caplog):
    worker = bridge.UploadWorker('test-url', {}, capacity=2)
    assert worker.submit(sample(1))
    assert worker.submit(sample(2))
    assert not worker.submit(sample(3))
    assert worker.queue.qsize() == 2
    assert 'queue full' in caplog.text


@pytest.mark.parametrize('status', [401, 403])
def test_auth_failure_reaches_serial_loop(status):
    with bridge.UploadWorker('test-url', {}, session_factory=lambda: Session(
            lambda *a, **k: Response(status))) as worker:
        worker.submit(sample(1))
        worker.thread.join(3)
        with pytest.raises(SystemExit, match='auth rejected'):
            worker.raise_if_failed()
        with pytest.raises(SystemExit, match='auth rejected'):
            worker.submit(sample(2))


def test_shutdown_interrupts_retry_delay_and_warns_about_unsent_data(caplog):
    attempted = Event()

    def post(*args, **kwargs):
        attempted.set()
        return Response(503)

    session = Session(post)
    with bridge.UploadWorker('test-url', {}, retry_delay=60,
                             session_factory=lambda: session) as worker:
        worker.submit(sample(1))
        assert attempted.wait(3)
    assert not worker.thread.is_alive()
    assert session.closed
    assert 'unsent samples' in caplog.text


def test_rejected_sample_does_not_block_next_sample():
    responses = deque([Response(422), Response(body=['unexpected', 'json'])])
    pending = deque([sample(1), sample(2)])
    session = Session(lambda *a, **k: responses.popleft())
    bridge._drain(session, 'test-url', {}, pending)
    assert not pending


def test_unexpected_worker_failure_is_not_silent():
    def post(*args, **kwargs):
        raise RuntimeError('private details should not escape')

    with bridge.UploadWorker('test-url', {}, session_factory=lambda: Session(post)) as worker:
        worker.submit(sample(1))
        worker.thread.join(3)
        with pytest.raises(SystemExit, match='upload worker failed') as error:
            worker.raise_if_failed()
        assert 'private details' not in str(error.value)
