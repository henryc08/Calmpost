"""Sample moisture_raw straight off the board, for calibration.

Reads the serial port directly: no server, no database, no device token. The
probe does not need to be installed in the bin -- calibration is done in air
and in water.

    python scripts/read_probe.py                 # 10s sample, auto-detect port
    python scripts/read_probe.py --seconds 20    # longer, for a noisy probe
    python scripts/read_probe.py --port COM3

Prints the mean (the number to calibrate with) plus the spread, so you can
tell a settled reading from a drifting one.
"""

import argparse
import json
import statistics
import sys
import time

import serial
from serial.tools import list_ports


def find_port() -> str | None:
    candidates = list(list_ports.comports())
    for p in candidates:
        blurb = f"{p.description} {p.manufacturer or ''}".lower()
        if any(k in blurb for k in
               ("arduino", "ch340", "cp210", "ftdi", "usb serial", "silicon labs", "esp32")):
            return p.device
    return candidates[0].device if candidates else None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", help="e.g. COM3; auto-detected when omitted")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=10.0)
    args = parser.parse_args()

    port = args.port or find_port()
    if not port:
        print("no serial port found -- is the board plugged in?")
        return 1

    print(f"reading {port} @ {args.baud} for {args.seconds:.0f}s")
    print("(the sketch waits ~20s for the CO2 sensor on connect -- that silence is normal)\n")

    raws: list[int] = []
    temps: list[float] = []
    deadline = None

    try:
        with serial.Serial(port, args.baud, timeout=2) as ser:
            # Don't start the clock until the first real sample arrives, so
            # the sketch's 20s CO2 settle doesn't eat the sampling window.
            while deadline is None or time.monotonic() < deadline:
                line = ser.readline().decode("utf-8", errors="replace").strip()
                if not line or not line.startswith("{"):
                    if deadline is None:
                        print("  waiting for the board...", end="\r", flush=True)
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                raw = d.get("moisture_raw")
                if raw is None:
                    continue
                if deadline is None:
                    deadline = time.monotonic() + args.seconds
                    print(" " * 40, end="\r")
                raws.append(int(raw))
                if d.get("probe_temp_c") is not None:
                    temps.append(float(d["probe_temp_c"]))
                print(f"  raw={raw:>5}   n={len(raws):>4}", end="\r", flush=True)
    except serial.SerialException as exc:
        print(f"\ncould not open {port}: {exc}")
        print("is the Arduino IDE's Serial Monitor open, or the bridge running?")
        return 1
    except KeyboardInterrupt:
        pass

    print(" " * 40)
    if not raws:
        print("no moisture_raw values seen. is the probe wired to A0?")
        return 1

    mean = statistics.fmean(raws)
    spread = max(raws) - min(raws)
    print(f"samples : {len(raws)}")
    print(f"mean    : {mean:.0f}   <-- use this number")
    print(f"range   : {min(raws)} to {max(raws)}  (spread {spread})")
    if len(raws) > 1:
        print(f"stdev   : {statistics.stdev(raws):.1f}")
    if temps:
        print(f"probe   : {statistics.fmean(temps):.1f}C")

    # A 10-bit ADC reads 0-1023. A wide spread means it has not settled.
    if spread > 25:
        print("\n  the reading is still moving -- wait a few seconds and run it again")
    else:
        print("\n  settled.")
    print("\nnext: run this with the probe in air (dry) and in water (wet),")
    print("then POST both numbers to /bins/{bin_id}/calibration.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
