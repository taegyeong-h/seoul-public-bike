from abc import ABC, abstractmethod


class BaseDBClient(ABC):
    @abstractmethod
    def get_connection_uri(self) -> str:
        """자식 클래스는 반드시 이 시그니처(동일한 매개변수)를 그대로 구현해야 합니다."""
        pass

class PostgresDBClient(BaseDBClient):
    def __init__(self, user: str, password: str, host: str, database_name: str, port: str = "5432", **kwargs):
        self._user = user
        self._password = password
        self._host = host
        self._port = port
        self._database_name = database_name

    def get_connection_uri(self) -> str:
        # ?connect_timeout=3 (서버 노크 대기 시간) 3초가 지나면 네트워크 단절 OR DB 서버 다운으로 판단 후 즉시 연결 포기 
        return f"postgresql://{self._user}:{self._password}@{self._host}:{self._port}/{self._database_name}?connect_timeout=3"