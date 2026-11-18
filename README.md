# Pip-Boy 3000 — Garmin watch face

A Fallout-style Pip-Boy 3000 terminal for Garmin watches, written in Monkey C
(Connect IQ 5.2). Built and tested on a **Forerunner 165** (390x390 AMOLED).

```
┌─────────────────────────┐
│       ╭ Pip-Boy ╮       │   header tab
│  👣 709       78 ♥ BPM  │   VITALS row
│ ─────────────────────── │
│                     ╷   │
│  ┌WED┐   11        │    │   day badge
│  │ 18 │   40       │    │   date + clock
│                     ╵   │   Vault Boy
│  ╭ PWR 75% │ 62 BB ╮    │   power plate
│      ╭ FALLOUT ╮        │   footer
└─────────────────────────┘
```

## What it shows

| Field | Source |
| --- | --- |
| Steps | `ActivityMonitor.getInfo().steps` |
| Heart rate | `ActivityMonitor.getHeartRateHistory()` |
| Day + date | `Time.Gregorian.info()` |
| Clock | `System.getClockTime()`, honours the 12/24 h setting |
| Seconds | small digits beside the minute |
| Battery | `System.getSystemStats().battery` |
| Body Battery | `SensorHistory.getBodyBatteryHistory()` |

Low power mode (wrist gesture off) collapses to dim digits only, to stay inside
the ambient pixel budget.

## Building

Requires the Connect IQ SDK and a developer key.

```bash
# JAVA_HOME must point at a JDK 17+
bash build.sh          # → build/fr165.prg
```

`build.sh` compiles for `fr165` and signs with `~/garmin-dev/keys/developer_key.der`.
Change `-d fr165` for another device, and adjust the layout constants in
`source/PipBoyView.mc` since everything is positioned proportionally to
`dc.getWidth()` / `dc.getHeight()`.

## Installing

Copy `build/fr165.prg` to the watch:

```
GARMIN/Apps/pipboy.prg
```

then unplug and pick the face from the watch face list.

## Layout notes

The clock lines are stacked from `dc.getFontHeight()` rather than fixed
percentages — `FONT_NUMBER_THAI_HOT` and `FONT_NUMBER_MEDIUM` have very
different heights, and hardcoded offsets make them collide. There is an
automatic fallback to the shorter number font if the stacked block would not
fit inside the clock band.

## The sprite

`resources/drawables/vaultboy.png` is generated, not hand-drawn:

```bash
python3 tools/make_vaultboy.py
```

The script has no third-party dependencies (no PIL on the build box): it paints
rounded rectangles, discs, arcs and thick lines into a supersampled buffer,
box-filters it down, and writes the PNG with `zlib`. Everything is authored in a
92x122 design space and scaled by `KSCALE`, so the sprite can be resized without
re-tuning coordinates.

Dark linework is deliberately sparse — at ~100 px tall on a watch, dense detail
collapses into a green blob.

## Files

```
source/PipBoyApp.mc      AppBase entry point
source/PipBoyView.mc     the face: data polling + all drawing
resources/drawables/     Vault Boy + launcher icon
tools/make_vaultboy.py   sprite generator
manifest.xml             app id / type / permissions
monkey.jungle            build paths
build.sh                 one-line build
```

## Licence

Fan project, unaffiliated with Bethesda or Garmin. Fallout and Vault Boy are
trademarks of Bethesda Softworks. Code is MIT.
