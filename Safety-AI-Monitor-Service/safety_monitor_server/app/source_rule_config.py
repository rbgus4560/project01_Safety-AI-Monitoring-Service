# 안전모 룰과 위험구역 ROI 같은 설정값을 정리하는 파일입니다.
# 뷰어에서 저장한 룰 설정이 서버 판정에 들어가기 전 이 형태로 맞춰집니다.

from __future__ import annotations

from copy import deepcopy


def build_default_rule_config() -> dict:
    return {
        "use_no_helmet_rule": True,
        "use_danger_zone_rule": False,
        "danger_zone_roi": None,
        "confidence_threshold": 0.30,
        "event_cooldown_seconds": 3.0,
    }


def normalize_rule_config(value: object) -> dict:
    base = build_default_rule_config()
    if not isinstance(value, dict):
        return base

    next_config = deepcopy(base)
    next_config["use_no_helmet_rule"] = bool(value.get("use_no_helmet_rule", base["use_no_helmet_rule"]))
    next_config["use_danger_zone_rule"] = bool(
        value.get("use_danger_zone_rule", base["use_danger_zone_rule"])
    )
    next_config["danger_zone_roi"] = normalize_roi(value.get("danger_zone_roi"))
    try:
        confidence = float(value.get("confidence_threshold", base["confidence_threshold"]))
    except (TypeError, ValueError):
        confidence = float(base["confidence_threshold"])
    next_config["confidence_threshold"] = min(0.99, max(0.0, confidence))
    try:
        cooldown = float(value.get("event_cooldown_seconds", base["event_cooldown_seconds"]))
    except (TypeError, ValueError):
        cooldown = float(base["event_cooldown_seconds"])
    next_config["event_cooldown_seconds"] = min(300.0, max(0.0, cooldown))
    return next_config


def normalize_roi(value: object) -> dict | None:
    if not isinstance(value, dict):
        return None

    try:
        x1 = int(value.get("x1"))
        y1 = int(value.get("y1"))
        x2 = int(value.get("x2"))
        y2 = int(value.get("y2"))
    except (TypeError, ValueError):
        return None

    left = min(x1, x2)
    right = max(x1, x2)
    top = min(y1, y2)
    bottom = max(y1, y2)
    if left == right or top == bottom:
        return None

    return {
        "x1": left,
        "y1": top,
        "x2": right,
        "y2": bottom,
    }


def to_roi_tuple(value: object) -> tuple[int, int, int, int] | None:
    roi = normalize_roi(value)
    if roi is None:
        return None
    return (
        int(roi["x1"]),
        int(roi["y1"]),
        int(roi["x2"]),
        int(roi["y2"]),
    )
