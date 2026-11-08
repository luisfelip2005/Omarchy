#!/usr/bin/env python3
"""Dynamic night light for Hyprland + hyprsunset.

Turns the fixed-time hyprsunset profiles into a smooth ramp driven by the real
solar elevation at the configured location: neutral during the day, gradually
warmer from a few degrees above the horizon until full night, and back to
neutral at sunrise.

The actual color temperature is pushed to the running hyprsunset daemon with
`hyprctl hyprsunset temperature`, so hyprsunset keeps owning the gamma control.
Gamma is never touched here (the brightness keybinds use it).

Usage:
  night_light_dynamic.py            # run the daemon (single instance)
  night_light_dynamic.py --once     # apply the current target and exit
  night_light_dynamic.py --status   # print the current state as JSON
  night_light_dynamic.py --config   # print the effective config as JSON
"""

import fcntl
import json
import math
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
CONFIG_PATH = HOME / ".config" / "hypr" / "night_light.jsonc"
CONFIG_FALLBACK_PATH = HOME / ".config" / "hypr" / "night_light.json"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state")) / "omarchy" / "night-light"
LOG_PATH = STATE_DIR / "daemon.log"

DEFAULTS = {
    "latitude": -23.55,
    "longitude": -46.63,
    "max_temperature": 6500,
    "min_temperature": 1200,
    "night_temperature": 2200,
    "preset_temperature": 2500,
    "start_elevation": 3.0,
    "full_elevation": -8.0,
    "offset_step": 500,
    "max_offset_up": 2000,
    "max_offset_down": 2000,
    "update_seconds": 20,
}


# --------------------------------------------------------------------------- #
# Config and state
# --------------------------------------------------------------------------- #

def strip_jsonc_comments(text):
    """Remove // and /* */ comments without touching string contents."""
    result = []
    index = 0
    length = len(text)
    in_string = False
    escaped = False

    while index < length:
        char = text[index]

        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
        elif char == '"':
            in_string = True
            result.append(char)
            index += 1
        elif text.startswith("//", index):
            newline = text.find("\n", index)
            index = length if newline == -1 else newline
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            index = length if end == -1 else end + 2
        else:
            result.append(char)
            index += 1

    return "".join(result)


def load_config():
    config = dict(DEFAULTS)
    path = CONFIG_PATH if CONFIG_PATH.exists() else CONFIG_FALLBACK_PATH
    try:
        raw = path.read_text()
        if path.suffix == ".jsonc":
            raw = strip_jsonc_comments(raw)
        config.update(json.loads(raw))
    except (OSError, ValueError) as error:
        log(f"config: using defaults ({error})")
    return config


def read_state(name, default):
    try:
        return (STATE_DIR / name).read_text().strip()
    except OSError:
        return default


def write_state(name, value):
    try:
        (STATE_DIR / name).write_text(str(value))
    except OSError as error:
        log(f"state: cannot write {name} ({error})")


def read_offset(config):
    try:
        offset = int(read_state("offset", "0"))
    except ValueError:
        offset = 0
    up = int(config["max_offset_up"])
    down = int(config["max_offset_down"])
    return max(-down, min(up, offset))


def night_light_mode():
    """One of "auto" (follow the sun), "fixed" (preset temperature) or "off"."""
    mode = read_state("mode", "auto")
    return mode if mode in ("auto", "fixed", "off") else "auto"


def log(message):
    try:
        if LOG_PATH.exists() and LOG_PATH.stat().st_size > 200_000:
            LOG_PATH.write_text("")
        with LOG_PATH.open("a") as handle:
            handle.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
    except OSError:
        pass


# --------------------------------------------------------------------------- #
# Solar elevation (NOAA approximation, no external dependencies)
# --------------------------------------------------------------------------- #

def solar_elevation(latitude, longitude, moment):
    """Return the sun's elevation in degrees for an aware UTC datetime."""
    day = moment.timetuple().tm_yday
    hour = moment.hour + moment.minute / 60 + moment.second / 3600
    gamma = 2 * math.pi / 365 * (day - 1 + (hour - 12) / 24)

    eqtime = 229.18 * (
        0.000075
        + 0.001868 * math.cos(gamma)
        - 0.032077 * math.sin(gamma)
        - 0.014615 * math.cos(2 * gamma)
        - 0.040849 * math.sin(2 * gamma)
    )
    declination = (
        0.006918
        - 0.399912 * math.cos(gamma)
        + 0.070257 * math.sin(gamma)
        - 0.006758 * math.cos(2 * gamma)
        + 0.000907 * math.sin(2 * gamma)
        - 0.002697 * math.cos(3 * gamma)
        + 0.00148 * math.sin(3 * gamma)
    )

    solar_time = hour * 60 + eqtime + 4 * longitude
    hour_angle = math.radians(solar_time / 4 - 180)
    lat = math.radians(latitude)
    cos_zenith = (
        math.sin(lat) * math.sin(declination)
        + math.cos(lat) * math.cos(declination) * math.cos(hour_angle)
    )
    zenith = math.degrees(math.acos(max(-1.0, min(1.0, cos_zenith))))
    return 90 - zenith


def clamp(value, low, high):
    return max(low, min(high, value))


def target_temperature(config, elevation, offset):
    """Map solar elevation to a color temperature with a smooth ramp."""
    start = float(config["start_elevation"])
    full = float(config["full_elevation"])
    day = float(config["max_temperature"])
    night = float(config["night_temperature"])

    # 0 at/above start_elevation (day), 1 at/below full_elevation (deep night).
    progress = clamp((start - elevation) / (start - full), 0.0, 1.0)
    progress = progress * progress * (3 - 2 * progress)  # smoothstep

    temperature = day + (night - day) * progress + offset
    return int(round(clamp(temperature, float(config["min_temperature"]), day)))


# --------------------------------------------------------------------------- #
# hyprsunset control
# --------------------------------------------------------------------------- #

def hyprsunset_pid():
    try:
        result = subprocess.run(
            ["pgrep", "-x", "hyprsunset"], capture_output=True, text=True, timeout=5
        )
    except (OSError, subprocess.SubprocessError):
        return None
    pid = result.stdout.strip()
    return pid or None


def apply_temperature(temperature):
    try:
        subprocess.run(
            ["hyprctl", "hyprsunset", "temperature", str(temperature)],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return True
    except (OSError, subprocess.SubprocessError) as error:
        log(f"apply: {error}")
        return False


def current_state(config):
    mode = night_light_mode()
    offset = read_offset(config)
    elevation = solar_elevation(
        float(config["latitude"]), float(config["longitude"]), datetime.now(timezone.utc)
    )

    day = int(config["max_temperature"])
    if mode == "fixed":
        preset = int(config["preset_temperature"])
        temperature = int(round(clamp(preset + offset, int(config["min_temperature"]), day)))
    elif mode == "off":
        temperature = day
    else:
        temperature = target_temperature(config, elevation, offset)

    return {
        "mode": mode,
        "offset": offset,
        "elevation": round(elevation, 2),
        "temperature": temperature,
    }


def run_once():
    config = load_config()
    state = current_state(config)
    if not hyprsunset_pid():
        print("hyprsunset is not running", file=sys.stderr)
        return 1
    if not apply_temperature(state["temperature"]):
        return 1
    write_state("current", json.dumps(state))
    print(json.dumps(state))
    return 0


def run_daemon():
    last_temperature = None
    last_pid = None

    while True:
        # Re-read the config every tick so night_light.json can be tuned live.
        config = load_config()
        interval = max(5, int(config["update_seconds"]))

        pid = hyprsunset_pid()
        if not pid:
            # hyprsunset.lua starts it on hyprland.start; just wait for it.
            time.sleep(interval)
            continue

        state = current_state(config)
        if pid != last_pid:
            last_temperature = None  # fresh daemon instance: reapply immediately
        if state["temperature"] != last_temperature:
            if apply_temperature(state["temperature"]):
                last_temperature = state["temperature"]
                write_state("current", json.dumps(state))
                log(
                    f"applied {state['temperature']}K "
                    f"(mode {state['mode']}, elevation {state['elevation']}°, "
                    f"offset {state['offset']}K)"
                )
        last_pid = pid
        time.sleep(interval)


def main():
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        print(f"cannot create state dir {STATE_DIR}: {error}", file=sys.stderr)
        return 1

    if "--config" in sys.argv:
        print(json.dumps(load_config()))
        return 0

    if "--status" in sys.argv:
        config = load_config()
        print(json.dumps(current_state(config)))
        return 0

    if "--once" in sys.argv:
        return run_once()

    # Single instance: keep the lock open for the whole process lifetime.
    lock_handle = (STATE_DIR / "daemon.lock").open("w")
    try:
        fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return 0
    run_daemon()
    return 0


if __name__ == "__main__":
    sys.exit(main())
