# 분석 파이프라인 안에서 사용하는 event_handler 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from abc import ABC, abstractmethod

from core.event_rule import Event


class EventHandler(ABC):
    # 콘솔 출력, 로그 저장, 알람 전송 등은 이 구조를 따라 확장한다

    @abstractmethod
    def handle(self, event: Event) -> None:
        pass
