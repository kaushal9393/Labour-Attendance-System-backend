from datetime import datetime, timedelta
from typing import Any


class SimpleCache:
    def __init__(self):
        self._store: dict = {}

    def get(self, key: str) -> Any | None:
        entry = self._store.get(key)
        if entry is None:
            return None
        value, expires = entry
        if datetime.now() > expires:
            del self._store[key]
            return None
        return value

    def set(self, key: str, value: Any, ttl_seconds: int = 30) -> None:
        self._store[key] = (value, datetime.now() + timedelta(seconds=ttl_seconds))

    def invalidate(self, key: str) -> None:
        self._store.pop(key, None)

    def invalidate_prefix(self, prefix: str) -> None:
        keys = [k for k in self._store if k.startswith(prefix)]
        for k in keys:
            del self._store[k]


cache = SimpleCache()
