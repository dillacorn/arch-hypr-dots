#!/usr/bin/env python3

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import os
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any

FLYOUT_TITLES = {
    "Awtarchy Application Search": "launcher",
    "Awtarchy Clipboard History": "clipboard",
    "Awtarchy Notification Center": "notifications",
    "Awtarchy Quick Settings": "quick-settings",
    "Awtarchy Network": "network",
    "Awtarchy Bluetooth": "bluetooth",
}

INTERESTING_EVENTS = {
    "activewindow",
    "activewindowv2",
    "focusedmon",
    "focusedmonv2",
    "openwindow",
    "openwindowv2",
    "closewindow",
    "closewindowv2",
    "movewindow",
    "movewindowv2",
    "windowtitle",
    "windowtitlev2",
}


def compact(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def now_record() -> dict[str, Any]:
    return {
        "wall_ns": time.time_ns(),
        "mono_ns": time.monotonic_ns(),
    }


def run_text(*args: str) -> str:
    try:
        cp = subprocess.run(
            args,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=2,
        )
        return cp.stdout.rstrip()
    except Exception as exc:
        return f"ERROR: {exc}"


class HyprIPC:
    def __init__(self) -> None:
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        if not runtime or not signature:
            raise RuntimeError(
                "XDG_RUNTIME_DIR or HYPRLAND_INSTANCE_SIGNATURE is missing; "
                "run this inside the Hyprland session"
            )

        base = Path(runtime) / "hypr" / signature
        self.command_socket = base / ".socket.sock"
        self.event_socket = base / ".socket2.sock"

        if not self.command_socket.is_socket():
            raise RuntimeError(f"Hyprland command socket not found: {self.command_socket}")
        if not self.event_socket.is_socket():
            raise RuntimeError(f"Hyprland event socket not found: {self.event_socket}")

    def request(self, request: str, timeout: float = 0.35) -> str:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.settimeout(timeout)
            sock.connect(str(self.command_socket))
            sock.sendall(request.encode("utf-8"))
            try:
                sock.shutdown(socket.SHUT_WR)
            except OSError:
                pass

            chunks: list[bytes] = []
            while True:
                try:
                    data = sock.recv(65536)
                except socket.timeout:
                    break
                if not data:
                    break
                chunks.append(data)
            return b"".join(chunks).decode("utf-8", errors="replace")
        finally:
            sock.close()

    def json_request(self, command: str, default: Any) -> Any:
        raw = self.request(f"j/{command}")
        try:
            return json.loads(raw)
        except Exception:
            return default

    def cursor(self) -> tuple[float, float] | None:
        value = self.json_request("cursorpos", {})
        try:
            return float(value["x"]), float(value["y"])
        except Exception:
            return None

    def active_window(self) -> dict[str, Any]:
        value = self.json_request("activewindow", {})
        return value if isinstance(value, dict) else {}

    def monitors(self) -> list[dict[str, Any]]:
        value = self.json_request("monitors", [])
        return value if isinstance(value, list) else []

    def clients(self) -> list[dict[str, Any]]:
        value = self.json_request("clients", [])
        return value if isinstance(value, list) else []


def select_active(window: dict[str, Any]) -> dict[str, Any]:
    workspace = window.get("workspace")
    workspace_id = workspace.get("id") if isinstance(workspace, dict) else None
    return {
        "address": window.get("address"),
        "class": window.get("class"),
        "title": window.get("title"),
        "monitor": window.get("monitor"),
        "workspace": workspace_id,
        "at": window.get("at"),
        "size": window.get("size"),
        "focusHistoryID": window.get("focusHistoryID"),
    }


def select_monitors(monitors: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for mon in monitors:
        workspace = mon.get("activeWorkspace")
        out.append(
            {
                "id": mon.get("id"),
                "name": mon.get("name"),
                "x": mon.get("x"),
                "y": mon.get("y"),
                "width": mon.get("width"),
                "height": mon.get("height"),
                "scale": mon.get("scale"),
                "transform": mon.get("transform"),
                "focused": mon.get("focused"),
                "activeWorkspace": workspace.get("id") if isinstance(workspace, dict) else None,
            }
        )
    return out


def select_flyouts(clients: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for client in clients:
        title = str(client.get("title") or "")
        surface = FLYOUT_TITLES.get(title)
        if surface is None:
            continue
        workspace = client.get("workspace")
        out.append(
            {
                "surface": surface,
                "address": client.get("address"),
                "title": title,
                "monitor": client.get("monitor"),
                "workspace": workspace.get("id") if isinstance(workspace, dict) else None,
                "at": client.get("at"),
                "size": client.get("size"),
                "focusHistoryID": client.get("focusHistoryID"),
                "mapped": client.get("mapped"),
                "hidden": client.get("hidden"),
            }
        )
    out.sort(key=lambda item: (str(item.get("surface")), str(item.get("address"))))
    return out


def focused_monitor(monitors: list[dict[str, Any]]) -> dict[str, Any] | None:
    for mon in monitors:
        if mon.get("focused") is True:
            return mon
    return None


def logical_monitor_box(mon: dict[str, Any]) -> tuple[float, float, float, float] | None:
    try:
        x = float(mon.get("x", 0))
        y = float(mon.get("y", 0))
        width = float(mon.get("width", 0))
        height = float(mon.get("height", 0))
        scale = float(mon.get("scale", 1) or 1)
        transform = int(mon.get("transform", 0) or 0)
    except Exception:
        return None

    if scale <= 0:
        scale = 1
    if transform % 2 == 1:
        width, height = height, width
    width /= scale
    height /= scale
    return x, y, width, height


def monitor_for_point(monitors: list[dict[str, Any]], x: float, y: float) -> dict[str, Any] | None:
    for mon in monitors:
        box = logical_monitor_box(mon)
        if box is None:
            continue
        mx, my, mw, mh = box
        if mx <= x < mx + mw and my <= y < my + mh:
            return mon
    return None


def point_distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(b[0] - a[0], b[1] - a[1])


def center_of_box(at: Any, size: Any) -> tuple[float, float] | None:
    try:
        return float(at[0]) + float(size[0]) / 2.0, float(at[1]) + float(size[1]) / 2.0
    except Exception:
        return None


class TraceWriter:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.lock = threading.Lock()
        self.file = path.open("w", encoding="utf-8", buffering=1)

    def write(self, kind: str, **payload: Any) -> None:
        record = now_record()
        record["type"] = kind
        record.update(payload)
        line = compact(record)
        with self.lock:
            self.file.write(line + "\n")

    def close(self) -> None:
        with self.lock:
            self.file.flush()
            self.file.close()


class FlyoutWarpTracer:
    def __init__(self, output: Path, interval_ms: float, stop_after: int) -> None:
        self.ipc = HyprIPC()
        self.writer = TraceWriter(output)
        self.interval = max(0.004, interval_ms / 1000.0)
        self.stop_after = max(0, stop_after)
        self.stop = threading.Event()
        self.events = collections.deque(maxlen=80)
        self.cursor_samples = collections.deque(maxlen=120)
        self.suspected_warps: list[dict[str, Any]] = []
        self.last_flyout_state: list[dict[str, Any]] = []
        self.latest_surface_event: tuple[int, str] | None = None

    def snapshot(self) -> dict[str, Any]:
        monitors_raw = self.ipc.monitors()
        clients_raw = self.ipc.clients()
        active_raw = self.ipc.active_window()
        focused = focused_monitor(monitors_raw)
        return {
            "cursor": self.ipc.cursor(),
            "focused_monitor": focused.get("name") if focused else None,
            "active": select_active(active_raw),
            "flyouts": select_flyouts(clients_raw),
            "monitors": select_monitors(monitors_raw),
        }

    def runtime_guard_metadata(self) -> dict[str, Any]:
        runtime = Path.home() / ".config/hypr/scripts/quickshell_runtime_rules.sh"
        result: dict[str, Any] = {"path": str(runtime), "exists": runtime.exists()}
        if not runtime.exists():
            return result
        try:
            content = runtime.read_bytes()
            result["sha256"] = hashlib.sha256(content).hexdigest()
            text = content.decode("utf-8", errors="replace")
            result["cursor_guard_present"] = "awtarchy_flyout_cursor_restore" in text
            result["outside_click_bind_present"] = "awtarchy_flyout_outside_click_bind_v1" in text
        except Exception as exc:
            result["error"] = str(exc)
        return result

    def write_header(self) -> None:
        self.writer.write(
            "meta",
            hyprland_version=run_text("hyprctl", "version"),
            cursor_no_warps=run_text("hyprctl", "getoption", "cursor:no_warps"),
            cursor_persistent_warps=run_text("hyprctl", "getoption", "cursor:persistent_warps"),
            cursor_warp_on_change_workspace=run_text("hyprctl", "getoption", "cursor:warp_on_change_workspace"),
            command_socket=str(self.ipc.command_socket),
            event_socket=str(self.ipc.event_socket),
            interval_ms=self.interval * 1000.0,
            runtime_guard=self.runtime_guard_metadata(),
            initial=self.snapshot(),
        )

    def event_loop(self) -> None:
        while not self.stop.is_set():
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                sock.settimeout(0.5)
                sock.connect(str(self.ipc.event_socket))
                buffer = b""
                while not self.stop.is_set():
                    try:
                        data = sock.recv(65536)
                    except socket.timeout:
                        continue
                    if not data:
                        break
                    buffer += data
                    while b"\n" in buffer:
                        raw, buffer = buffer.split(b"\n", 1)
                        line = raw.decode("utf-8", errors="replace").strip()
                        if not line:
                            continue
                        stamp = time.monotonic_ns()
                        self.events.append((stamp, line))
                        name = line.split(">>", 1)[0]
                        if name in INTERESTING_EVENTS:
                            self.handle_interesting_event(stamp, name, line)
            except OSError as exc:
                if not self.stop.is_set():
                    self.writer.write("event_socket_error", error=str(exc))
                    time.sleep(0.1)
            finally:
                sock.close()

    def handle_interesting_event(self, stamp: int, name: str, line: str) -> None:
        cursor = self.ipc.cursor()
        snapshot: dict[str, Any] | None = None

        if name in {"openwindow", "openwindowv2", "closewindow", "closewindowv2", "movewindow", "movewindowv2", "activewindow", "activewindowv2", "focusedmon", "focusedmonv2"}:
            try:
                snapshot = self.snapshot()
            except Exception as exc:
                snapshot = {"error": str(exc)}

        if snapshot and isinstance(snapshot.get("flyouts"), list):
            flyouts = snapshot["flyouts"]
            surfaces = {str(item.get("surface")) for item in flyouts}
            previous = {str(item.get("surface")) for item in self.last_flyout_state}
            changed = surfaces.symmetric_difference(previous)
            if len(changed) == 1:
                self.latest_surface_event = (stamp, next(iter(changed)))
            elif flyouts:
                active_title = str((snapshot.get("active") or {}).get("title") or "")
                active_surface = FLYOUT_TITLES.get(active_title)
                if active_surface:
                    self.latest_surface_event = (stamp, active_surface)
            self.last_flyout_state = flyouts

        self.writer.write(
            "hypr_event",
            event=name,
            raw=line,
            cursor=cursor,
            state=snapshot,
        )

    def classify_jump(
        self,
        before: tuple[float, float],
        after: tuple[float, float],
        dt_ms: float,
        snapshot: dict[str, Any],
    ) -> dict[str, Any]:
        distance = point_distance(before, after)
        monitors_raw = self.ipc.monitors()
        destination_monitor = monitor_for_point(monitors_raw, after[0], after[1])
        destination_name = destination_monitor.get("name") if destination_monitor else None

        monitor_center_distance: float | None = None
        if destination_monitor:
            box = logical_monitor_box(destination_monitor)
            if box:
                mx, my, mw, mh = box
                monitor_center_distance = point_distance(after, (mx + mw / 2.0, my + mh / 2.0))

        active = snapshot.get("active") or {}
        active_center = center_of_box(active.get("at"), active.get("size"))
        active_center_distance = point_distance(after, active_center) if active_center else None
        active_surface = FLYOUT_TITLES.get(str(active.get("title") or ""))

        flyout_center_matches: list[dict[str, Any]] = []
        for flyout in snapshot.get("flyouts") or []:
            center = center_of_box(flyout.get("at"), flyout.get("size"))
            if center is None:
                continue
            center_distance = point_distance(after, center)
            if center_distance <= 48:
                flyout_center_matches.append(
                    {
                        "surface": flyout.get("surface"),
                        "address": flyout.get("address"),
                        "distance": round(center_distance, 2),
                    }
                )

        likely_surface = active_surface
        if likely_surface is None and flyout_center_matches:
            likely_surface = str(flyout_center_matches[0].get("surface"))
        if likely_surface is None and self.latest_surface_event is not None:
            event_ns, surface = self.latest_surface_event
            if time.monotonic_ns() - event_ns <= 500_000_000:
                likely_surface = surface

        recent_events = [
            line
            for event_ns, line in self.events
            if time.monotonic_ns() - event_ns <= 500_000_000
        ][-20:]

        center_signature = (
            (monitor_center_distance is not None and monitor_center_distance <= 32)
            or (active_center_distance is not None and active_center_distance <= 32)
            or bool(flyout_center_matches)
        )
        instantaneous = dt_ms <= 120.0 and distance >= 240.0
        suspected = distance >= 240.0 and (center_signature or instantaneous)

        return {
            "before": [round(before[0], 3), round(before[1], 3)],
            "after": [round(after[0], 3), round(after[1], 3)],
            "distance": round(distance, 2),
            "dt_ms": round(dt_ms, 3),
            "destination_monitor": destination_name,
            "monitor_center_distance": None if monitor_center_distance is None else round(monitor_center_distance, 2),
            "active_center_distance": None if active_center_distance is None else round(active_center_distance, 2),
            "flyout_center_matches": flyout_center_matches,
            "likely_surface": likely_surface,
            "center_signature": center_signature,
            "instantaneous": instantaneous,
            "suspected_warp": suspected,
            "recent_events": recent_events,
            "state": snapshot,
            "recent_cursor_samples": list(self.cursor_samples)[-20:],
        }

    def cursor_loop(self) -> None:
        previous: tuple[int, tuple[float, float]] | None = None

        while not self.stop.is_set():
            started = time.monotonic()
            cursor = self.ipc.cursor()
            stamp = time.monotonic_ns()

            if cursor is not None:
                sample = {
                    "mono_ns": stamp,
                    "x": round(cursor[0], 3),
                    "y": round(cursor[1], 3),
                }
                self.cursor_samples.append(sample)

                if previous is not None:
                    prev_ns, prev_cursor = previous
                    dt_ms = (stamp - prev_ns) / 1_000_000.0
                    distance = point_distance(prev_cursor, cursor)

                    if distance >= 80.0:
                        try:
                            snapshot = self.snapshot()
                        except Exception as exc:
                            snapshot = {"error": str(exc), "active": {}, "flyouts": [], "monitors": []}

                        jump = self.classify_jump(prev_cursor, cursor, dt_ms, snapshot)
                        self.writer.write("cursor_jump", **jump)

                        if jump["suspected_warp"]:
                            self.suspected_warps.append(jump)
                            number = len(self.suspected_warps)
                            surface = jump.get("likely_surface") or "unknown"
                            destination = jump.get("destination_monitor") or "unknown"
                            print(
                                f"WARP #{number}: surface={surface} "
                                f"{jump['before']} -> {jump['after']} "
                                f"distance={jump['distance']}px destination={destination}",
                                flush=True,
                            )
                            if self.stop_after and number >= self.stop_after:
                                print(f"Captured {number} suspected warps; stopping automatically.", flush=True)
                                self.stop.set()
                                break

                previous = (stamp, cursor)

            elapsed = time.monotonic() - started
            delay = self.interval - elapsed
            if delay > 0:
                self.stop.wait(delay)

    def summarize(self) -> None:
        counts: dict[str, int] = collections.Counter(
            str(item.get("likely_surface") or "unknown") for item in self.suspected_warps
        )
        summary = {
            "suspected_warp_count": len(self.suspected_warps),
            "counts_by_surface": dict(sorted(counts.items())),
        }
        self.writer.write("summary", **summary)

        print("\nTrace summary:")
        print(f"  suspected warps: {len(self.suspected_warps)}")
        if counts:
            for surface, count in sorted(counts.items()):
                print(f"  {surface}: {count}")
        else:
            print("  no suspected warps detected")
        print(f"  log: {self.writer.path}")

    def run(self) -> int:
        self.write_header()
        event_thread = threading.Thread(target=self.event_loop, name="hypr-events", daemon=True)
        cursor_thread = threading.Thread(target=self.cursor_loop, name="cursor-poll", daemon=True)
        event_thread.start()
        cursor_thread.start()

        print("Awtarchy flyout warp tracer is running.")
        print("Use Launcher, Quick Settings, Network, Bluetooth, Clipboard, and Notifications normally.")
        print("When you have reproduced the bad cursor teleport a few times, press Ctrl+C.")
        if self.stop_after:
            print(f"The tracer will also stop automatically after {self.stop_after} suspected warps.")
        print(f"Log: {self.writer.path}")

        try:
            while not self.stop.wait(0.2):
                pass
        except KeyboardInterrupt:
            self.stop.set()

        event_thread.join(timeout=1.0)
        cursor_thread.join(timeout=1.0)
        self.summarize()
        self.writer.close()
        return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Trace Awtarchy Quickshell cross-monitor cursor warps without modifying compositor state."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output JSONL path (default: ~/awtarchy-flyout-warp-YYYYmmdd-HHMMSS.jsonl)",
    )
    parser.add_argument(
        "--interval-ms",
        type=float,
        default=10.0,
        help="Cursor sampling interval in milliseconds (default: 10)",
    )
    parser.add_argument(
        "--stop-after",
        type=int,
        default=0,
        help="Automatically stop after this many suspected warps (0 = Ctrl+C only)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = args.output
    if output is None:
        output = Path.home() / time.strftime("awtarchy-flyout-warp-%Y%m%d-%H%M%S.jsonl")
    output = output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    tracer = FlyoutWarpTracer(output, args.interval_ms, args.stop_after)

    def stop_handler(_signum: int, _frame: Any) -> None:
        tracer.stop.set()

    signal.signal(signal.SIGTERM, stop_handler)
    return tracer.run()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
