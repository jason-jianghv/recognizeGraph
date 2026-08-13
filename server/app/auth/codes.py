"""内存验证码（MVP）；会话与用户改由数据库持久化。"""

from __future__ import annotations

import secrets
import threading
import time
from dataclasses import dataclass


@dataclass
class SmsRecord:
    code: str
    expires_at: float
    resend_at: float


class SmsStore:
    def __init__(
        self,
        *,
        code_ttl_sec: int = 300,
        resend_sec: int = 60,
        code_len: int = 6,
    ) -> None:
        self.code_ttl_sec = code_ttl_sec
        self.resend_sec = resend_sec
        self.code_len = code_len
        self._sms: dict[str, SmsRecord] = {}
        self._lock = threading.Lock()

    def issue_sms_code(self, phone: str) -> tuple[str, int, int]:
        now = time.time()
        with self._lock:
            prev = self._sms.get(phone)
            if prev and now < prev.resend_at:
                wait = int(prev.resend_at - now) + 1
                raise ValueError(f"发送太频繁，请 {wait} 秒后再试")

            code = "".join(secrets.choice("0123456789") for _ in range(self.code_len))
            self._sms[phone] = SmsRecord(
                code=code,
                expires_at=now + self.code_ttl_sec,
                resend_at=now + self.resend_sec,
            )
            return code, self.code_ttl_sec, self.resend_sec

    def verify_and_consume(self, phone: str, code: str) -> None:
        now = time.time()
        submitted = (code or "").strip()
        with self._lock:
            rec = self._sms.get(phone)
            if rec is None:
                raise ValueError("请先获取验证码")
            if now > rec.expires_at:
                self._sms.pop(phone, None)
                raise ValueError("验证码已过期，请重新获取")
            if submitted != rec.code:
                raise ValueError("验证码不正确")
            self._sms.pop(phone, None)


sms_store = SmsStore()

# 兼容旧 import
auth_store = sms_store
