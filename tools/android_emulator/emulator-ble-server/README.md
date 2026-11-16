# emulator-ble-server

Fake Bluetooth LE peripherals for the Android emulator, to test NucleantBluetooth (or any Bluetooth app) against without hardware. Each one is a [Bumble](https://github.com/google/bumble) device on netsim, the emulator's virtual radio, so the emulator finds and connects to them like real ones. What they do over time (heart rates, readings, beacons, signal strength, leaving range) is [reactivex](https://github.com/ReactiveX/RxPY) streams on timers.

Start the emulator, then:

```sh
uv run emulator-ble-server                    # every device and a crowd of 12
uv run emulator-ble-server heart-rate uart    # only these, still with the crowd
uv run emulator-ble-server --crowd 0          # no crowd
uv run emulator-ble-server --list             # what each device does
uv run emulator-ble-server -v                 # every signal change and event; -vv adds Bumble's HCI traffic
```

## The devices

| Device | Name | What it tests | Signal |
|---|---|---|---|
| `heart-rate` | Pulse HR | Heart Rate (notify: a rate that wanders, energy expended), its control point (write `01` resets the energy, anything else is refused), Body Sensor Location, Battery (read, notify, drains), Device Information; appearance, transmit power and Nordic's manufacturer data in the scan response | orbiting, -78 to -45 dBm |
| `thermometer` | Thermo | Health Thermometer: measurements **indicated**, IEEE-11073 floats; Measurement Interval (read, write, indicate), which retimes the measurements at once and refuses values outside 1–60 (ATT 0xFF) | steady, -58 ± 1 |
| `weather-station` | Weather Station | Environmental Sensing: temperature, humidity, pressure (read, notify); the temperature also as **service data in the advertisement**, changing while you scan | steady, -84 ± 4 |
| `uart` | UART Console | Nordic UART: **128-bit UUIDs** (the service in the scan response), writes with and without response, echoes upper-cased, `tick N` every 5 s | steady, -50 ± 1 |
| `test-bench` | Test Bench | A counter notifying 4 times a second, a 400-byte value (long read), a read refused (0x02), a write that takes one byte only (0x0D), a write always refused (0xFC), write-without-response only, an indicate-only alarm | steady, -42 ± 0.5 |
| `dropout` | Dropout | Counts down 12 s once connected, then **disconnects the central** (remote user terminated) | drifting, -88 to -55 |
| `roaming-tag` | Roaming Tag | Find Me (Alert Level, write without response) and Battery, on a tag that **leaves range** about 15 s of every 45: a connection to it times out | roaming around -62 |
| `blinky` | Blinky Tag | Advertises in bursts, 3 s on and 5 s off: the device comes and goes, its last-seen time falls behind | drifting, -85 to -45 |
| `ibeacon` | (no name) | An iBeacon: **non-connectable**, unnamed, Apple's manufacturer data, a minor that counts up | steady, -70 ± 4 |
| `eddystone` | (no name) | An Eddystone beacon: non-connectable, unnamed, service data switching between a URL frame and a telemetry frame | orbiting, -90 to -60 |
| crowd | Kettle, Desk Lamp, … | Everyday devices that only advertise: real company identifiers (named by PureSwift's metadata), every fourth unnamed, every third not connectable, manufacturer data that changes | steady, drifting, orbiting and roaming in turn |

## Signals

How strong each device's signal is, over time, is a class of its own in `signals.py`, and each device picks one:

- **`Steady`**: still, give or take a little jitter.
- **`Drifting`**: carried around, a random walk between two strengths.
- **`Orbiting`**: on a path round the room, from far to near and back.
- **`Roaming`**: in range for a while, fading towards the edge, then gone, then back.

netsim doesn't move devices, but it does work out the RSSI from the advertiser's transmit power: with every device at the same spot it reports TX + 41 dB, from TX -127 (RSSI -86) up to RSSI +20. So a device sets its advertising set's transmit power to the RSSI its signal asks for, changing it only when it moves by 2 dB or more. While a device is out of range it isn't on netsim at all. A central's scan stops finding it, and a connection to it times out the way it does when a device walks away (supervision timeout, HCI 0x08). Back in range, it joins netsim again with the same address, services and advertisement.

## How it runs

Everything is one process, on one asyncio loop with one reactivex scheduler:

- **`Netsim`** finds netsimd's gRPC port from the `netsim.ini` it writes. On macOS that file can be under another app's TMPDIR, so the folders under `$TMPDIR` are searched as well. `--netsim-port` skips the search.
- **One controller per device.** Each device gets its own controller on its own gRPC connection. netsim turns a device away for a few seconds after the same one left, and now and then leaves a new controller hanging, so bringing a device up is retried with a short wait. A controller that stops answering mid-run leaves netsim and joins again.
- **`Peripheral`** is the base class. A device says what it is (`services`, `advertisement`, `scan_response`) and what it does (`behave`, its streams), and gets its signal handled for it.
- **Load on netsim.** netsim answers a flood of HCI commands with GOAWAY ("Buffers full") and drops connections. So advertising data is updated in place, the transmit power changes only on real moves, and devices advertise once a second.

## Tests

```sh
uv run pytest
```

They cover the byte layouts the devices send (IEEE-11073 floats, Heart Rate Measurement, Eddystone URL and TLM frames, iBeacon data), the transmit power picked for an RSSI, and each kind of signal over three minutes of virtual time.
