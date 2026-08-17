# 카메라 소스별 분석 worker를 시작하고 중지하는 관리자 파일입니다.
# 소스 실행 상태와 서버 presence 동기화 흐름이 포함되어 있습니다.

from __future__ import annotations

import threading
import time
import socket
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from app.analysis_runtime import build_pipeline_for_source, build_source_record, resolve_source
from app.config import (
    CLIENT_CLIP_DIR,
    CLIENT_SETTINGS_PATH,
    CLIENT_SOURCE_CACHE_DIR,
    CLIENT_UPLOAD_SOURCE_DIR,
    DATABASE_PATH,
)
from app.database import (
    delete_source_status,
    delete_source,
    get_source_status,
    get_source,
    list_source_statuses,
    list_sources,
    prune_orphan_source_data,
    reset_source_data,
    set_source_desired_running,
    upsert_source,
    upsert_source_status,
)
from app.log_utils import log_line
from app.reporting_api import remote_server_reporter
from app.source_rule_config import normalize_rule_config


@dataclass
class _ManagedWorker:
    """실행 중인 분석 워커의 상태를 함께 보관하기 위한 내부 데이터 클래스입니다."""
    source_record: dict[str, Any]
    stop_event: threading.Event
    thread: threading.Thread
    stop_reason: str = ""


class AnalysisSourceManager:
    """카메라/스트림/영상 소스의 생명주기를 관리하는 중앙 관리자입니다."""
    _server_presence_interval_seconds = 5.0

    def __init__(self) -> None:
        """워커 저장소와 서버 상태 동기화용 상태를 초기화한다."""
        self._lock = threading.RLock()
        self._workers: dict[str, _ManagedWorker] = {}
        self._server_presence_stop = threading.Event()
        self._server_presence_thread: threading.Thread | None = None

    def bootstrap(self) -> None:
        """저장된 소스 설정은 복원하되 실제 영상 입력은 사용자가 시작하도록 대기시킨다."""
        for source_record in list_sources(DATABASE_PATH):
            source_key = str(source_record.get("source_key", "")).strip()
            if not source_key:
                continue
            source_type = str(source_record.get("source_type", "")).strip().lower()
            source_value = str(source_record.get("source_value", "")).strip()

            # 과거 camera:0 source_key에 owner 정보가 없던 데이터만 새 형식으로 마이그레이션한다.
            if source_type == "camera" and source_value == "0" and "owner=" not in source_key:
                migrated = build_source_record(
                    source_type=source_type,
                    source_value=source_value,
                    original_source_type=str(source_record.get("original_source_type", source_type)).strip() or source_type,
                    original_source_value=str(source_record.get("original_source_value", source_value)).strip() or source_value,
                    client_id=str(source_record.get("client_id", "")).strip() or _build_default_client_id(),
                    session_id=str(source_record.get("session_id", "")).strip(),
                    desired_running=False,
                )
                migrated["rule_config"] = normalize_rule_config(source_record.get("rule_config"))
                migrated["display_name"] = str(source_record.get("display_name", "")).strip()
                upsert_source(DATABASE_PATH, migrated)
                delete_source(DATABASE_PATH, source_key)
                delete_source_status(DATABASE_PATH, source_key)
                remote_server_reporter.delete_source(source_key, clear_data=False)
                source_record = migrated
                source_key = str(source_record.get("source_key", "")).strip()

            # 재부팅 직후 오래된 USB/영상 소스가 자동 실행되는 것을 막는다.
            # 이름, 규칙, 소스 등록 정보는 유지하고 실행 상태만 안전하게 정지로 복원한다.
            set_source_desired_running(
                DATABASE_PATH,
                source_key=source_key,
                desired_running=False,
            )
            latest_source = get_source(DATABASE_PATH, source_key) or source_record
            self._sync_source_to_server(latest_source)
            previous_status = get_source_status(DATABASE_PATH, source_key) or {}
            self._upsert_status_and_sync(
                {
                    "source_key": source_key,
                    "source_type": latest_source["source_type"],
                    "source_value": latest_source["source_value"],
                    "client_id": latest_source["client_id"],
                    "session_id": latest_source["session_id"],
                    "state": "registered",
                    "is_running": False,
                    "source_fps": float(previous_status.get("source_fps", 0.0) or 0.0),
                    "last_frame_id": int(previous_status.get("last_frame_id", -1) or -1),
                    "last_source_time_seconds": float(previous_status.get("last_source_time_seconds", 0.0) or 0.0),
                    "error_message": "",
                }
            )
            log_line("SRC", action="bootstrap-source", source=source_key, desired=False)

        self._start_server_presence_loop()

    def shutdown(self) -> None:
        """서버 presence 루프와 실행 중인 모든 워커를 정리한다."""
        self._server_presence_stop.set()
        if self._server_presence_thread is not None:
            self._server_presence_thread.join(timeout=2.0)
        with self._lock:
            worker_keys = list(self._workers.keys())
        for source_key in worker_keys:
            self.stop_source(
                source_key,
                update_desired_running=False,
                stop_reason="shutdown",
            )

    def register_source(
        self,
        *,
        source_type: str,
        source_value: str,
        client_id: str = "",
        session_id: str = "",
        reset_existing: bool = True,
        start_immediately: bool = True,
    ) -> dict[str, Any]:
        """새 소스를 등록하고 필요하면 즉시 실행 상태로 만든다."""
        source_type = source_type.strip().lower()
        source_value = source_value.strip()
        if source_type not in {"camera", "video", "stream"}:
            raise ValueError(f"unsupported source type: {source_type}")
        if not source_value:
            raise ValueError("source value is required")
        client_id = client_id.strip() or _read_configured_client_id() or _build_default_client_id()
        resolved = resolve_source(source_type=source_type, source_value=source_value)
        source_record = build_source_record(
            source_type=resolved["source_type"],
            source_value=resolved["source_value"],
            original_source_type=resolved["original_source_type"],
            original_source_value=resolved["original_source_value"],
            client_id=client_id,
            session_id=session_id,
            desired_running=start_immediately,
        )
        source_key = str(source_record.get("source_key", "")).strip()
        source_slug = str(source_record.get("source_slug", "")).strip()
        existing_source = get_source(DATABASE_PATH, source_key)
        if existing_source is not None:
            source_record["rule_config"] = normalize_rule_config(
                existing_source.get("rule_config")
            )

        upsert_source(DATABASE_PATH, source_record)
        self._sync_source_to_server(source_record)
        if reset_existing:
            # 기존 데이터가 남아 있으면 클립/이벤트 기록을 초기화해 새 등록 상태로 맞춘다.
            reset_source_data(
                DATABASE_PATH,
                source_key=source_key,
                source_slug=source_slug,
                server_clip_dir=CLIENT_CLIP_DIR,
            )
            self._reset_remote_source_data(source_record)

        if start_immediately:
            # 즉시 시작 요청이면 워커를 생성하고 상태를 시작 중으로 올린다.
            self.start_source(source_key)
        else:
            # 시작하지 않는 경우에도 등록 상태를 서버에 알려 UI와 동기화를 유지한다.
            previous_status = get_source_status(DATABASE_PATH, source_key) or {}
            self._upsert_status_and_sync(
                {
                    "source_key": source_key,
                    "source_type": source_record["source_type"],
                    "source_value": source_record["source_value"],
                    "client_id": source_record["client_id"],
                    "session_id": source_record["session_id"],
                    "state": "registered",
                    "is_running": False,
                    "source_fps": float(previous_status.get("source_fps", 0.0) or 0.0),
                    "last_frame_id": int(previous_status.get("last_frame_id", -1) or -1),
                    "last_source_time_seconds": float(
                        previous_status.get("last_source_time_seconds", 0.0) or 0.0
                    ),
                    "error_message": "",
                }
            )
            latest = get_source(DATABASE_PATH, source_key) or source_record
            self._sync_source_to_server(latest)
        return get_source(DATABASE_PATH, source_key) or source_record

    def update_source_display_name(self, source_key: str, *, display_name: str) -> dict[str, Any]:
        """로컬 표시 이름을 수정하고 중앙 서버 소스 정보에도 동기화한다."""
        source_record = get_source(DATABASE_PATH, source_key)
        if source_record is None:
            raise KeyError(source_key)
        source_record = dict(source_record)
        source_record["display_name"] = display_name.strip()
        source_record["updated_at"] = datetime.now().isoformat()
        saved = upsert_source(DATABASE_PATH, source_record)
        self._sync_source_to_server(saved)
        return saved

    def update_source_rule_config(
        self,
        source_key: str,
        *,
        rule_config: dict,
    ) -> dict[str, Any]:
        """소스의 규칙 설정을 갱신하고 필요 시 재분석을 다시 시작한다."""
        normalized_source_key = source_key.strip()
        source_record = get_source(DATABASE_PATH, normalized_source_key)
        if source_record is None:
            raise KeyError(normalized_source_key)

        source_type = str(source_record.get("source_type", "")).strip().lower()
        source_record["rule_config"] = normalize_rule_config(rule_config)
        source_record["updated_at"] = datetime.now().isoformat()

        should_reanalyze_from_start = source_type == "video"
        if should_reanalyze_from_start:
            # 영상 소스는 규칙 변경 시 처음부터 다시 분석하는 편이 더 안전하다.
            source_record["desired_running"] = True

        upsert_source(DATABASE_PATH, source_record)
        self._sync_source_to_server(source_record)

        if should_reanalyze_from_start:
            self.stop_source(
                normalized_source_key,
                update_desired_running=False,
                stop_reason="config-update",
            )
            reset_source_data(
                DATABASE_PATH,
                source_key=normalized_source_key,
                source_slug=str(source_record.get("source_slug", "")).strip(),
                server_clip_dir=CLIENT_CLIP_DIR,
            )
            self._reset_remote_source_data(source_record)
            self.start_source(normalized_source_key)
            return get_source(DATABASE_PATH, normalized_source_key) or source_record

        with self._lock:
            # 이미 실행 중인 워커가 있으면 새 설정을 반영하기 위해 재시작만 수행한다.
            existing_worker = self._workers.get(normalized_source_key)
            is_running = existing_worker is not None and existing_worker.thread.is_alive()

        if is_running:
            self.restart_source(normalized_source_key)

        return get_source(DATABASE_PATH, normalized_source_key) or source_record

    def list_registered_sources(self) -> list[dict[str, Any]]:
        """현재 등록된 모든 소스 기록을 반환한다."""
        return list_sources(DATABASE_PATH)

    def sync_all_to_server(self) -> None:
        """로컬 소스와 상태를 서버에 한 번에 동기화한다."""
        for source_record in list_sources(DATABASE_PATH):
            self._sync_source_to_server(source_record)
        for status_record in list_source_statuses(DATABASE_PATH):
            remote_server_reporter.post_status(status_record)

    def start_source(self, source_key: str) -> dict[str, Any]:
        """지정한 소스의 분석 워커를 시작한다."""
        normalized_source_key = source_key.strip()
        source_record = get_source(DATABASE_PATH, normalized_source_key)
        if source_record is None:
            raise KeyError(normalized_source_key)

        set_source_desired_running(
            DATABASE_PATH,
            source_key=normalized_source_key,
            desired_running=True,
        )
        latest_source_record = get_source(DATABASE_PATH, normalized_source_key)
        if latest_source_record is not None:
            self._sync_source_to_server(latest_source_record)
        with self._lock:
            # 중복 실행을 막기 위해 이미 살아 있는 워커가 있으면 새 스레드를 만들지 않는다.
            existing_worker = self._workers.get(normalized_source_key)
            if existing_worker is not None and existing_worker.thread.is_alive():
                return source_record

            previous_status = get_source_status(DATABASE_PATH, normalized_source_key) or {}
            stop_event = threading.Event()
            thread = threading.Thread(
                target=self._run_worker,
                args=(normalized_source_key, dict(source_record), stop_event),
                name=f"analysis-worker-{normalized_source_key}",
                daemon=True,
            )
            self._workers[normalized_source_key] = _ManagedWorker(
                source_record=dict(source_record),
                stop_event=stop_event,
                thread=thread,
            )
            log_line(
                "SRC",
                action="start",
                source=normalized_source_key,
                type=source_record["source_type"],
                client=source_record["client_id"] or "-",
            )
            self._upsert_status_and_sync(
                {
                    "source_key": normalized_source_key,
                    "source_type": source_record["source_type"],
                    "source_value": source_record["source_value"],
                    "client_id": source_record["client_id"],
                    "session_id": source_record["session_id"],
                    "state": "starting",
                    "is_running": False,
                    "source_fps": float(previous_status.get("source_fps", 0.0) or 0.0),
                    "last_frame_id": int(previous_status.get("last_frame_id", -1) or -1),
                    "last_source_time_seconds": float(
                        previous_status.get("last_source_time_seconds", 0.0) or 0.0
                    ),
                    "error_message": "",
                }
            )
            thread.start()
        return get_source(DATABASE_PATH, normalized_source_key) or source_record

    def stop_source(
        self,
        source_key: str,
        *,
        update_desired_running: bool = True,
        stop_reason: str = "api-stop",
    ) -> dict[str, Any] | None:
        """실행 중인 워커를 중지하고 상태를 갱신한다."""
        normalized_source_key = source_key.strip()
        if update_desired_running:
            set_source_desired_running(
                DATABASE_PATH,
                source_key=normalized_source_key,
                desired_running=False,
            )
            latest_source_record = get_source(DATABASE_PATH, normalized_source_key)
            if latest_source_record is not None:
                self._sync_source_to_server(latest_source_record)

        worker: _ManagedWorker | None = None
        with self._lock:
            # 현재 등록된 워커를 꺼내고 stop 이벤트를 발생시켜 루프를 종료시킨다.
            worker = self._workers.pop(normalized_source_key, None)
        if worker is not None:
            worker.stop_reason = stop_reason
            log_line(
                "SRC",
                action="stop-request",
                source=normalized_source_key,
                reason=stop_reason,
            )
            worker.stop_event.set()
            worker.thread.join(timeout=10.0)

        source_record = get_source(DATABASE_PATH, normalized_source_key)
        if source_record is not None:
            # 워커 중지 후에는 상태를 stopped로 바꿔 UI와 서버가 최신 상태를 인지하게 한다.
            previous_status = get_source_status(DATABASE_PATH, normalized_source_key) or {}
            self._upsert_status_and_sync(
                {
                    "source_key": normalized_source_key,
                    "source_type": source_record["source_type"],
                    "source_value": source_record["source_value"],
                    "client_id": source_record["client_id"],
                    "session_id": source_record["session_id"],
                    "state": "stopped",
                    "is_running": False,
                    "source_fps": float(previous_status.get("source_fps", 0.0) or 0.0),
                    "last_frame_id": int(previous_status.get("last_frame_id", -1) or -1),
                    "last_source_time_seconds": float(
                        previous_status.get("last_source_time_seconds", 0.0) or 0.0
                    ),
                    "error_message": "",
                }
            )
        return source_record

    def restart_source(self, source_key: str) -> dict[str, Any]:
        """현재 소스를 중지한 뒤 다시 시작한다."""
        self.stop_source(source_key, stop_reason="api-restart")
        return self.start_source(source_key)

    def remove_source(self, source_key: str, *, clear_data: bool = False) -> bool:
        """소스를 등록 해제하고 필요하면 관련 데이터를 함께 정리한다."""
        source_record = get_source(DATABASE_PATH, source_key)
        if source_record is None:
            return False
        self.stop_source(source_key, stop_reason="remove-source")
        if clear_data:
            reset_source_data(
                DATABASE_PATH,
                source_key=source_key,
                source_slug=str(source_record.get("source_slug", "")).strip(),
                server_clip_dir=CLIENT_CLIP_DIR,
            )
            self._delete_managed_source_file(source_record)
        deleted = delete_source(DATABASE_PATH, source_key)
        delete_source_status(DATABASE_PATH, source_key)
        prune_orphan_source_data(DATABASE_PATH)
        remote_server_reporter.delete_source(
            source_key,
            clear_data=clear_data,
            client_id=str(source_record.get("client_id", "")).strip(),
            session_id=str(source_record.get("session_id", "")).strip(),
        )
        return deleted

    def _delete_managed_source_file(self, source_record: dict[str, Any]) -> None:
        """관리 대상 영상 파일이 있으면 로컬에서 제거한다."""
        source_type = str(source_record.get("source_type", "")).strip().lower()
        source_value = str(source_record.get("source_value", "")).strip()
        if source_type != "video" or not source_value:
            return

        try:
            file_path = Path(source_value).resolve()
            managed_roots = (
                CLIENT_UPLOAD_SOURCE_DIR.resolve(),
                CLIENT_SOURCE_CACHE_DIR.resolve(),
            )
        except OSError:
            return

        normalized_file = str(file_path).replace("\\", "/").lower()
        is_managed_file = False
        for managed_root in managed_roots:
            normalized_root = str(managed_root).replace("\\", "/").lower()
            if normalized_file.startswith(f"{normalized_root}/"):
                is_managed_file = True
                break
        if not is_managed_file:
            return
        if file_path.exists() and file_path.is_file():
            file_path.unlink(missing_ok=True)

    def _remove_stale_local_camera_sources(self, *, keep_source_key: str = "") -> None:
        """현재 클라이언트가 아닌 오래된 로컬 카메라 소스를 정리한다."""
        current_client_id = _read_configured_client_id() or _build_default_client_id()
        keep_source_key = keep_source_key.strip()
        for source_record in list_sources(DATABASE_PATH):
            source_key = str(source_record.get("source_key", "")).strip()
            if not source_key or source_key == keep_source_key:
                continue
            source_type = str(source_record.get("source_type", "")).strip().lower()
            source_value = str(source_record.get("source_value", "")).strip()
            client_id = str(source_record.get("client_id", "")).strip()
            if (
                source_type != "camera"
                or source_value != "0"
                or client_id == current_client_id
            ):
                # 기본 카메라 소스만 로컬 정리 대상이며, 같은 클라이언트의 소스는 건드리지 않는다.
                continue

            self.stop_source(
                source_key,
                update_desired_running=False,
                stop_reason="remove-stale-local",
            )
            delete_source(DATABASE_PATH, source_key)
            delete_source_status(DATABASE_PATH, source_key)
            prune_orphan_source_data(DATABASE_PATH)
            # 같은 클라이언트 패밀리라면 서버에 삭제 요청도 함께 보내고, 다른 기기 소스는 로컬만 정리한다.
            is_same_client_family = _canonical_client_id(client_id) == _canonical_client_id(
                current_client_id
            )
            if is_same_client_family:
                remote_server_reporter.delete_source(
                    source_key,
                    clear_data=False,
                    client_id=client_id,
                    session_id=str(source_record.get("session_id", "")).strip(),
                )
            log_line(
                "SRC",
                action=(
                    "remove-stale-camera"
                    if is_same_client_family
                    else "remove-foreign-camera-local"
                ),
                source=source_key,
                client=client_id or "-",
            )

    def _run_worker(
        self,
        source_key: str,
        source_record: dict[str, Any],
        stop_event: threading.Event,
    ) -> None:
        """개별 소스의 분석 루프를 실행하며 재연결과 재시도를 처리한다."""
        source_type = str(source_record.get("source_type", "")).strip().lower()
        try:
            while not stop_event.is_set():
                previous_status = get_source_status(DATABASE_PATH, source_key) or {}
                resume_from_seconds = 0.0
                if source_type == "video":
                    # 영상은 중간부터 이어서 분석할 수 있도록 마지막 재생 위치를 기준으로 복원한다.
                    previous_state = str(previous_status.get("state", "")).strip().lower()
                    previous_time = float(
                        previous_status.get("last_source_time_seconds", 0.0) or 0.0
                    )
                    if previous_state != "completed" and previous_time > 0.0:
                        resume_from_seconds = max(previous_time - 1.0, 0.0)

                stop_reason = "stopped"
                error_message = ""
                try:
                    pipeline = build_pipeline_for_source(
                        source_record,
                        restart_checker=lambda: stop_event.is_set(),
                        resume_from_seconds=resume_from_seconds,
                    )
                    stop_reason = pipeline.run()
                except Exception as error:
                    stop_reason = "error"
                    error_message = str(error)
                    log_line(
                        "ERROR",
                        message="analysis worker failed",
                        source=source_key,
                        error=error,
                    )

                if stop_event.is_set():
                    stop_reason = "stopped"

                if stop_reason == "completed":
                    # 영상 분석이 끝나면 더 이상 자동 실행하지 않도록 desired_running을 꺼준다.
                    set_source_desired_running(
                        DATABASE_PATH,
                        source_key=source_key,
                        desired_running=False,
                    )

                source_state = get_source(DATABASE_PATH, source_key) or source_record
                if stop_reason != "source_changed":
                    previous_status = get_source_status(DATABASE_PATH, source_key) or {}
                    next_error_message = error_message
                    next_state = stop_reason
                    if (
                        source_type in {"stream", "camera"}
                        and not stop_event.is_set()
                        and bool((get_source(DATABASE_PATH, source_key) or {}).get("desired_running", False))
                        and stop_reason in {"disconnected", "error"}
                    ):
                        # 연결이 끊긴 스트림/카메라는 재연결 상태로 표시해 UI에서 바로 인지할 수 있게 한다.
                        next_state = "reconnecting"
                        if not next_error_message:
                            next_error_message = "입력 연결이 끊겨 재시도 중입니다."
                    self._upsert_status_and_sync(
                        {
                            "source_key": source_key,
                            "source_type": source_state["source_type"],
                            "source_value": source_state["source_value"],
                            "client_id": source_state["client_id"],
                            "session_id": source_state["session_id"],
                            "state": next_state,
                            "is_running": False,
                            "source_fps": float(
                                previous_status.get("source_fps", 0.0) or 0.0
                            ),
                            "last_frame_id": int(
                                previous_status.get("last_frame_id", -1) or -1
                            ),
                            "last_source_time_seconds": float(
                                previous_status.get("last_source_time_seconds", 0.0)
                                or 0.0
                            ),
                            "error_message": next_error_message,
                        }
                    )

                if not self._should_retry_source(
                    source_key=source_key,
                    source_type=source_type,
                    stop_reason=stop_reason,
                    stop_event=stop_event,
                ):
                    # 재시도 대상이 아니면 워커 루프를 종료하고 상태를 정리한다.
                    log_line(
                        "SRC",
                        action="stop",
                        source=source_key,
                        reason=stop_reason,
                    )
                    break

                log_line(
                    "SRC",
                    action="retry",
                    source=source_key,
                    type=source_type,
                    reason=stop_reason,
                    wait="2.0s",
                )
                time.sleep(2.0)
        finally:
            with self._lock:
                self._workers.pop(source_key, None)

    def _should_retry_source(
        self,
        *,
        source_key: str,
        source_type: str,
        stop_reason: str,
        stop_event: threading.Event,
    ) -> bool:
        """소스가 재시도 가능한 상태인지 판단한다."""
        if stop_event.is_set():
            return False
        if source_type == "video":
            return False
        if source_type not in {"stream", "camera"}:
            return False
        if stop_reason in {"completed", "disconnected", "error"}:
            source_state = get_source(DATABASE_PATH, source_key)
            return bool(source_state and source_state.get("desired_running", False))
        return False

    def _sync_source_to_server(self, source_record: dict[str, Any]) -> None:
        """소스 정보를 서버에 업서트해 동기화한다."""
        payload = dict(source_record)
        payload["rule_config"] = normalize_rule_config(payload.get("rule_config"))
        payload["source_duration_seconds"] = float(
            payload.get("source_duration_seconds", 0.0) or 0.0
        )
        # Original media stays on the client for every source type.
        payload["server_media_path"] = ""
        payload["media_url"] = ""
        payload["preview_url"] = ""
        remote_server_reporter.upsert_source(payload)

    def _upsert_status_and_sync(self, status_record: dict[str, Any]) -> dict[str, Any]:
        """상태를 로컬 DB에 저장하고 서버에 바로 전파한다."""
        saved_record = upsert_source_status(DATABASE_PATH, status_record)
        remote_server_reporter.post_status(saved_record)
        return saved_record

    def _reset_remote_source_data(self, source_record: dict[str, Any]) -> None:
        """원격 서버의 소스 관련 데이터를 초기화한다."""
        remote_server_reporter.reset_source_data(
            source_key=str(source_record.get("source_key", "")).strip(),
            source_slug=str(source_record.get("source_slug", "")).strip(),
        )

    def _start_server_presence_loop(self) -> None:
        """서버 존재 여부를 주기적으로 확인하는 백그라운드 루프를 시작한다."""
        if self._server_presence_thread is not None and self._server_presence_thread.is_alive():
            return
        self._server_presence_stop.clear()
        self._server_presence_thread = threading.Thread(
            target=self._run_server_presence_loop,
            name="server-presence-loop",
            daemon=True,
        )
        self._server_presence_thread.start()

    def _run_server_presence_loop(self) -> None:
        """정해진 간격마다 서버와의 상태 동기화를 반복한다."""
        while not self._server_presence_stop.wait(self._server_presence_interval_seconds):
            try:
                self._sync_server_presence()
            except Exception as error:
                log_line("WARN", message="server presence sync failed", error=error)

    def _sync_server_presence(self) -> None:
        """등록된 소스와 상태를 주기적으로 서버에 다시 전송한다."""
        for source_record in list_sources(DATABASE_PATH):
            source_key = str(source_record.get("source_key", "")).strip()
            if not source_key:
                continue
            self._sync_source_to_server(source_record)

        for status_record in list_source_statuses(DATABASE_PATH):
            # heartbeat처럼 상태 레코드를 다시 저장해 서버에서 최신 상태를 유지하도록 한다.
            source_key = str(status_record.get("source_key", "")).strip()
            if not source_key:
                continue
            latest_source = get_source(DATABASE_PATH, source_key)
            if latest_source is None:
                continue
            heartbeat_status = dict(status_record)
            heartbeat_status["updated_at"] = datetime.now().isoformat()
            self._upsert_status_and_sync(heartbeat_status)


def _build_default_client_id() -> str:
    """현재 머신 이름을 기반으로 기본 클라이언트 식별자를 만든다."""
    hostname = socket.gethostname().strip().lower()
    normalized = "".join(char if char.isalnum() else "_" for char in hostname)
    normalized = "_".join(part for part in normalized.split("_") if part)
    return f"client_{normalized}" if normalized else "client_local"


def _read_configured_client_id() -> str:
    """설정 파일에 저장된 클라이언트 ID를 읽어온다."""
    try:
        decoded = json.loads(CLIENT_SETTINGS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    if not isinstance(decoded, dict):
        return ""
    return str(decoded.get("client_id", "")).strip()


def _canonical_client_id(client_id: str) -> str:
    """클라이언트 ID의 동일성 비교에 쓰이는 정규화된 형태를 반환한다."""
    normalized = client_id.strip().lower()
    parts = normalized.rsplit("_", 1)
    if (
        len(parts) == 2
        and len(parts[1]) == 6
        and all(char in "0123456789abcdef" for char in parts[1])
    ):
        return parts[0]
    return normalized
