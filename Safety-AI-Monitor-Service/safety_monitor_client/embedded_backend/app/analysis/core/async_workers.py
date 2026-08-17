# 분석 파이프라인 안에서 사용하는 async_workers 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from __future__ import annotations

import queue
import threading
from typing import Callable, Generic, TypeVar

from app.log_utils import log_line

T = TypeVar("T")


class AsyncTaskWorker(Generic[T]):
    def __init__(
        self,
        *,
        name: str,
        consumer: Callable[[T], None],
        max_queue_size: int = 0,
    ) -> None:
        self.name = name
        self.consumer = consumer
        self.queue: queue.Queue[T] = queue.Queue(maxsize=max_queue_size)
        self.stop_event = threading.Event()
        self.thread = threading.Thread(
            target=self._run,
            name=name,
            daemon=True,
        )
        self.thread.start()

    def submit(self, item: T, *, timeout_seconds: float = 0.05) -> bool:
        if self.stop_event.is_set():
            return False

        try:
            if self.queue.maxsize > 0:
                self.queue.put(item, timeout=timeout_seconds)
            else:
                self.queue.put_nowait(item)
            return True
        except queue.Full:
            return False

    def close(self, *, drain: bool = True, timeout_seconds: float = 30.0) -> bool:
        if drain:
            self.queue.join()
        self.stop_event.set()
        self.thread.join(timeout=timeout_seconds)
        return not self.thread.is_alive()

    def drain(self) -> None:
        self.queue.join()

    def _run(self) -> None:
        while not self.stop_event.is_set() or not self.queue.empty():
            try:
                item = self.queue.get(timeout=0.1)
            except queue.Empty:
                continue

            try:
                self.consumer(item)
            except Exception as error:
                # 소비자 예외로 worker thread가 죽지 않도록 로그만 남기고 다음 작업을 계속 처리합니다.
                log_line("ERROR", source=self.name, error=error)
            finally:
                self.queue.task_done()


class AsyncLatestWorker(Generic[T]):
    def __init__(
        self,
        *,
        name: str,
        consumer: Callable[[T], None],
    ) -> None:
        self.name = name
        self.consumer = consumer
        self.stop_event = threading.Event()
        self.wakeup_event = threading.Event()
        self.lock = threading.Lock()
        self.latest_item: T | None = None
        self.thread = threading.Thread(
            target=self._run,
            name=name,
            daemon=True,
        )
        self.thread.start()

    def submit(self, item: T) -> None:
        with self.lock:
            self.latest_item = item
        self.wakeup_event.set()

    def close(self, *, drain: bool = True, timeout_seconds: float = 30.0) -> bool:
        if not drain:
            with self.lock:
                self.latest_item = None
        self.stop_event.set()
        self.wakeup_event.set()
        self.thread.join(timeout=timeout_seconds)
        return not self.thread.is_alive()

    def _take_latest(self) -> T | None:
        with self.lock:
            item = self.latest_item
            self.latest_item = None
            return item

    def _run(self) -> None:
        while True:
            self.wakeup_event.wait(timeout=0.1)
            self.wakeup_event.clear()

            item = self._take_latest()
            if item is not None:
                try:
                    self.consumer(item)
                except Exception as error:
                    # latest worker도 저장/전송 예외로 중단되지 않게 보호합니다.
                    log_line("ERROR", source=self.name, error=error)

            if self.stop_event.is_set() and self._take_latest() is None:
                break
