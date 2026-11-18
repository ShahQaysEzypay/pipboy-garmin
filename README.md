# Pip-Boy 3000 — Garmin Watch Face

A faithful recreation of the iconic Fallout Pip-Boy 3000 terminal watch face for Garmin smartwatches, written in Monkey C (Connect IQ 3.2+ / 5.x). Built and designed for circular AMOLED displays (e.g. **Forerunner 165**, 390x390, scalable to 416x416 / 454x454 / 480x480).

```
          ┌─────────┐
    ──────│ MONDAY  │──────
 08 01 2024 [TEMPERATURE] ⛅ 17°
─────────────────────────────┬──────
  198 KCAL [====\__]   🚶   │  04
 126 HEARTRATE [==\__]      │  --
  30 PAI [=\__]             │  29
 6.47 DISTANCE   STEPS      │
               [___\==|]    └───────
┌─────────┐      5123        zZ * 🔔
│ BATTERY │
│   90%   │       PIP-BOY 3000
└─────────┘     QAYS INDUSTRIES
```

## Features & Display Layout

| Section | Elements & Data Source |
| --- | --- |
| **Top Badge** | Inverted solid green badge with full weekday name (`MONDAY` - `SUNDAY`) |
| **Subheader** | Date `DD MM YYYY`, `[ TEMPERATURE ]` box, weather condition icon, and temperature (`17°`) |
| **Left Stats** | • `KCAL`: Calories burned with angular RobCo progress gauge<br>• `HEARTRATE`: Current BPM with progress gauge<br>• `PAI`: Body Battery / PAI equivalent (0–100) with progress gauge<br>• `DISTANCE`: Daily distance in km or statute miles |
| **Center** | Classic walking Vault Boy sprite with multi-frame walking animation |
| **Steps** | Centered under Vault Boy: `STEPS` label, reversed RobCo bracket gauge, and step count |
| **Right Time Frame** | RobCo terminal bracket containing vertical 90° `TIME` label, large digital Hour (`04`), separator dashes (`--`), and Minute (`29`) |
| **Status Bar** | System status icons under the time box: Do Not Disturb (`zZ`), Bluetooth phone connection, Alarm, and Lock |
| **Bottom Left** | `[ BATTERY ]` boxed badge with battery percentage readout (`90%`) |
| **Footer** | `PIP-BOY 3000` / `QAYS INDUSTRIES` branding |
| **CRT Aesthetic** | CRT horizontal scanlines across the AMOLED display in deep phosphor green (`#0A3309`) |
| **AOD Low Power Mode** | Energy-efficient ambient mode with dim clock, date, and vitals respecting AMOLED burn-in protection |

## Building

Requires the Connect IQ SDK and a developer key.

```bash
# JAVA_HOME must point at a JDK 17+
bash build.sh          # → build/fr165.prg
```

`build.sh` compiles for `fr165` and signs with `~/garmin-dev/keys/developer_key.der`.
Change `-d fr165` for another device model.

## Installing

Copy `build/fr165.prg` to the watch:

```
GARMIN/Apps/pipboy.prg
```

Then select the Pip-Boy face from the watch face list.

## Project Structure

```
source/PipBoyApp.mc       AppBase entry point
source/PipBoyView.mc      Watch face rendering: all RobCo gauges, scanlines, data polling
resources/drawables/      Vault Boy sprite + launcher icon
tools/make_vaultboy.py    Sprite extractor and scaler
manifest.xml              App permissions (SensorHistory, Positioning) & target products
monkey.jungle             Build rules
build.sh                  Build script
```

## Licence

Fan project, unaffiliated with Bethesda or Garmin. Fallout, Vault Boy, Pip-Boy, and RobCo are trademarks of Bethesda Softworks.
