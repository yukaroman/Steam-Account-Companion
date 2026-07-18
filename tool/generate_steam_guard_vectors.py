#!/usr/bin/env python3
"""Independent Steam Guard vector generator (not the Dart implementation).

Cross-check reference:
  https://github.com/winauth/SteamAuth/blob/master/index.js
  BeyondDimension/WinAuth SteamAuthenticator.CalculateCode

Usage:
  python3 tool/generate_steam_guard_vectors.py
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import struct
from pathlib import Path

STEAMCHARS = "23456789BCDFGHJKMNPQRTVWXY"
PERIOD_SECONDS = 30


def code_for(secret_b64: str, unix_sec: int, server_diff_ms: int = 0) -> str:
    secret = base64.b64decode(secret_b64)
    ms = unix_sec * 1000 + server_diff_ms
    interval = ms // (PERIOD_SECONDS * 1000)
    msg = struct.pack(">Q", interval)
    mac = hmac.new(secret, msg, hashlib.sha1).digest()
    start = mac[19] & 0x0F
    fullcode = struct.unpack(">I", mac[start : start + 4])[0] & 0x7FFFFFFF
    out: list[str] = []
    for _ in range(5):
        out.append(STEAMCHARS[fullcode % 26])
        fullcode //= 26
    return "".join(out)


def remaining(unix_sec: int, server_diff_ms: int = 0) -> int:
    ms = unix_sec * 1000 + server_diff_ms
    elapsed = (ms // 1000) % PERIOD_SECONDS
    r = PERIOD_SECONDS - elapsed
    return PERIOD_SECONDS if r == 0 else r


CASES = [
    ("zero-epoch", "AAAAAAAAAAAAAAAAAAAAAAAAAAA=", 0, 0),
    ("first-boundary", "AAAAAAAAAAAAAAAAAAAAAAAAAAA=", 30, 0),
    ("same-window-as-epoch", "AAAAAAAAAAAAAAAAAAAAAAAAAAA=", 29, 0),
    ("classic-timestamp", "AAAAAAAAAAAAAAAAAAAAAAAAAAA=", 1234567890, 0),
    ("demo-primary-secret", "dGVzdC1zaGFyZWQtc2VjcmV0ISE=", 1700000000, 0),
    ("demo-trading-secret", "MTIzNDU2Nzg5MGFiY2RlZg==", 1600000000, 0),
    ("demo-alt-secret", "SGVsbG9Xb3JsZFNlY3JldCE=", 1893456000, 0),
    ("server-time-skew-rolls-window", "AAAAAAAAAAAAAAAAAAAAAAAAAAA=", 100, 20000),
]


def main() -> None:
    vectors = []
    for case_id, secret, unix, diff in CASES:
        vectors.append(
            {
                "id": case_id,
                "shared_secret_b64": secret,
                "unix_seconds": unix,
                "server_time_diff_ms": diff,
                "expected_code": code_for(secret, unix, diff),
                "expected_remaining": remaining(unix, diff),
            }
        )
    print(json.dumps({"vectors": vectors}, indent=2))
    root = Path(__file__).resolve().parents[1]
    print(f"# compare with {root / 'test/fixtures/steam_guard_vectors.json'}", flush=True)


if __name__ == "__main__":
    main()
