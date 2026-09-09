"""
Throwaway raw-TCP logger for reverse-engineering the EL-440's ATL stream.
Run on a public host, point the device at it with #serverchange, capture a
few minutes of frames while the device sits at a known location, then hand
capture.log back for analysis.

  python3 tcp_capture.py            # listens on 0.0.0.0:5001, writes capture.log
  PORT=5023 python3 tcp_capture.py
"""
import os
import socket
import threading
from datetime import datetime, timezone

PORT = int(os.environ.get("PORT", "5001"))
LOGFILE = os.environ.get("LOGFILE", "capture.log")


def now():
    return datetime.now(timezone.utc).isoformat()


def hexdump(b):
    lines = []
    for i in range(0, len(b), 16):
        chunk = b[i:i + 16]
        hexs = " ".join(f"{x:02x}" for x in chunk)
        text = "".join(chr(x) if 32 <= x < 127 else "." for x in chunk)
        lines.append(f"{i:04x}  {hexs:<47}  {text}")
    return "\n".join(lines)


_lock = threading.Lock()


def log(msg):
    with _lock:
        print(msg, flush=True)
        with open(LOGFILE, "a") as f:
            f.write(msg + "\n")


def handle(conn, addr):
    log(f"\n=== CONNECT {addr} {now()} ===")
    conn.settimeout(300)
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                break
            log(f"\n--- {len(data)} bytes @ {now()} ---")
            log(hexdump(data))
    except Exception as e:
        log(f"closed: {e}")
    finally:
        conn.close()
        log(f"=== DISCONNECT {addr} {now()} ===")


def main():
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", PORT))
    s.listen(5)
    log(f"listening on 0.0.0.0:{PORT}  ({now()})")
    while True:
        c, a = s.accept()
        threading.Thread(target=handle, args=(c, a), daemon=True).start()


if __name__ == "__main__":
    main()
