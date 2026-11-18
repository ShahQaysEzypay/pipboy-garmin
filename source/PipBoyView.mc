import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// Pip-Boy 3000 watch face.
//
// Layout follows the RobCo terminal: a "Pip-Boy" tab header, a live VITALS row
// (steps / heart rate), a day+date block on the left, the clock split across two
// lines in the middle, a standing Vault Boy on the right, and a PWR/BB readout
// riding a bottom plate.
//
// Vertical rhythm is computed from measured font heights rather than hardcoded
// offsets. The number fonts differ a lot in ascent/descent, so fixed percentages
// make the hour and minute collide at some sizes.
class PipBoyView extends WatchUi.WatchFace {

    // Phosphor palette. AMOLED black behind it so the green does the work.
    private const BG         = 0x030603;
    private const GREEN      = 0x3CFF3C;
    private const GREEN_MID  = 0x27A327;
    private const GREEN_DIM  = 0x156615;
    private const GREEN_DEEP = 0x0A2C0A;

    private var mTimer = null;
    private var mBoy = null;
    private var mSleeping = false;

    private var mSteps = 0;
    private var mHr = 0;
    private var mBattery = 0;
    private var mBody = -1;

    function initialize() {
        WatchFace.initialize();
    }

    // ------------------------------------------------------------- lifecycle --

    function onLayout(dc as Dc) as Void {
        mBoy = WatchUi.loadResource(Rez.Drawables.VaultBoy);
    }

    function onShow() as Void {
        mSleeping = false;
        refresh();
        startTimer();
    }

    function onHide() as Void {
        stopTimer();
    }

    function onEnterSleep() as Void {
        mSleeping = true;
        stopTimer();
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        mSleeping = false;
        startTimer();
        WatchUi.requestUpdate();
    }

    function startTimer() as Void {
        if (mSleeping) {
            return;
        }
        if (mTimer == null) {
            mTimer = new Timer.Timer();
        }
        mTimer.start(method(:onTick), 1000, true);
    }

    function stopTimer() as Void {
        if (mTimer != null) {
            mTimer.stop();
        }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------------- data ---

    function refresh() as Void {
        mSteps = 0;
        var info = ActivityMonitor.getInfo();
        if (info != null && info.steps != null) {
            mSteps = info.steps;
        }

        // Ask for a wide window: a 2 second window is often empty because the
        // optical sensor only samples every few minutes at rest.
        mHr = 0;
        var hrIter = ActivityMonitor.getHeartRateHistory(900, true);
        if (hrIter != null) {
            var sample = hrIter.next();
            while (sample != null) {
                var hr = sample.heartRate;
                if (hr != null && hr > 25 && hr < 230) {
                    mHr = hr;
                    break;
                }
                sample = hrIter.next();
            }
        }

        var stats = System.getSystemStats();
        mBattery = stats.battery.toNumber();

        mBody = -1;
        var bbIter = SensorHistory.getBodyBatteryHistory({
            :period => 3600,
            :order  => SensorHistory.ORDER_NEWEST_FIRST
        });
        if (bbIter != null) {
            var s = bbIter.next();
            while (s != null) {
                var v = s.data;
                if (v != null) {
                    var n = (v instanceof Lang.Float) ? (v as Lang.Float).toNumber() : (v as Number);
                    if (n >= 0 && n <= 100) {
                        mBody = n;
                        break;
                    }
                }
                s = bbIter.next();
            }
        }
    }

    // ---------------------------------------------------------------- drawing --

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(BG, BG);
        dc.clear();

        var ct = System.getClockTime();

        if (mSleeping) {
            drawLowPower(dc, w, h, ct);
            return;
        }

        if (ct.sec == 0) {
            refresh();
        }

        drawScanlines(dc, w, h);
        drawChrome(dc, w, h);
        drawVitals(dc, w, h);
        drawDayDate(dc, w, h, ct);
        drawClock(dc, w, h, ct);
        drawVaultBoy(dc, w, h);
        drawPowerPlate(dc, w, h);
    }

    // Fine horizontal banding, the CRT tell. Kept very dark so it reads as
    // texture rather than as lines.
    function drawScanlines(dc as Dc, w as Number, h as Number) as Void {
        dc.setColor(GREEN_DEEP, Graphics.COLOR_TRANSPARENT);
        var y = 0;
        while (y < h) {
            dc.drawLine(0, y, w, y);
            y += 6;
        }
    }

    function drawChrome(dc as Dc, w as Number, h as Number) as Void {
        // header + footer plates
        drawPlate(dc, w / 2, h * 11 / 100, w * 42 / 100, h * 9 / 100, "Pip-Boy");
        drawPlate(dc, w / 2, h * 88 / 100, w * 38 / 100, h * 9 / 100, "FALLOUT");

        // separator under the vitals row
        dc.setColor(GREEN_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(w * 20 / 100, h * 27 / 100, w * 80 / 100, h * 27 / 100);

        drawBracket(dc, w * 16 / 100, h * 31 / 100, h * 55 / 100, 1);
        drawBracket(dc, w * 95 / 100, h * 31 / 100, h * 70 / 100, -1);
    }

    function drawPlate(dc as Dc, cx as Number, cy as Number, tw as Number, th as Number, label as String) as Void {
        var x = cx - tw / 2;
        var y = cy - th / 2;
        var r = th / 3;
        dc.setColor(GREEN_DEEP, GREEN_DEEP);
        dc.fillRoundedRectangle(x, y, tw, th, r);
        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, tw, th, r);
        dc.drawText(cx, cy, Graphics.FONT_TINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawBracket(dc as Dc, x as Number, y0 as Number, y1 as Number, dir as Number) as Void {
        dc.setColor(GREEN_MID, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x, y0, x, y1);
        dc.drawLine(x, y0, x + dir * 11, y0);
        dc.drawLine(x, y1, x + dir * 11, y1);
        dc.setPenWidth(1);

        // scroll pips
        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - 3, y0 + (y1 - y0) / 3, 6, 9);
        dc.fillRectangle(x - 3, y0 + (y1 - y0) * 2 / 3, 6, 6);
    }

    function drawVitals(dc as Dc, w as Number, h as Number) as Void {
        var y = h * 21 / 100;

        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);

        // footprint glyph - fillEllipse() is centre-based, not corner-based
        var fx = w * 17 / 100;
        dc.fillEllipse(fx, y + 3, 13, 16);
        dc.fillEllipse(fx - 1, y - 8, 10, 9);
        dc.drawText(fx + 22, y, Graphics.FONT_SMALL, mSteps.toString(),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // pulse glyph
        var hx = w * 80 / 100;
        dc.fillEllipse(hx - 5, y - 3, 13, 12);
        dc.fillEllipse(hx + 5, y - 3, 13, 12);
        dc.fillPolygon([[hx - 11, y - 1], [hx + 11, y - 1], [hx, y + 11]]);

        var hrText = (mHr > 0) ? (mHr.toString() + " BPM") : ("-- BPM");
        dc.drawText(hx - 16, y, Graphics.FONT_SMALL, hrText,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawDayDate(dc as Dc, w as Number, h as Number, ct) as Void {
        var cx = w * 28 / 100;
        var by = h * 36 / 100;

        var bw = 52;
        var bh = 27;
        dc.setColor(GREEN_DEEP, GREEN_DEEP);
        dc.fillRectangle(cx - bw / 2, by - bh / 2, bw, bh);

        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, by, Graphics.FONT_TINY, dayName(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        dc.drawText(cx, h * 47 / 100, Graphics.FONT_MEDIUM, info.day.toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Prefer the spelled day name from FORMAT_MEDIUM: the numeric day_of_week
    // field is 1-based on some firmware and 0-based on others.
    function dayName() as String {
        try {
            var m = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
            var v = m.day_of_week;
            if (v instanceof Lang.String) {
                var s = v.toString().toUpper();
                if (s.length() > 3) {
                    s = s.substring(0, 3);
                }
                if (s.length() == 3) {
                    return s;
                }
            }
        } catch (e) {
        }

        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        var n = info.day_of_week;
        if (n instanceof Lang.Number) {
            var i = (n as Number) % 7;
            if (i == 0) {
                return names[0];
            }
            return names[i - 1];
        }
        return "--";
    }

    function drawClock(dc as Dc, w as Number, h as Number, ct) as Void {
        var cx = w * 45 / 100;

        var hourText;
        if (System.getDeviceSettings().is24Hour) {
            hourText = ct.hour.format("%d");
        } else {
            var h12 = ct.hour % 12;
            if (h12 == 0) {
                h12 = 12;
            }
            hourText = h12.format("%d");
        }
        var minText = ct.min.format("%02d");

        var hourFont = Graphics.FONT_NUMBER_MEDIUM;
        var minFont = Graphics.FONT_NUMBER_THAI_HOT;

        // Stack the two lines from their real heights so they never intersect.
        var hourH = dc.getFontHeight(hourFont);
        var minH = dc.getFontHeight(minFont);
        var gap = 6;
        var top = h * 30 / 100;
        var bottom = h * 71 / 100;
        var block = hourH + gap + minH;
        if (block > (bottom - top)) {
            minFont = Graphics.FONT_NUMBER_HOT;
            minH = dc.getFontHeight(minFont);
            gap = 0;
            block = hourH + minH;
        }
        var y0 = top + (bottom - top - block) / 2;
        var hourCy = y0 + hourH / 2;
        var minCy = y0 + hourH + gap + minH / 2;

        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, hourCy, hourFont, hourText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, minCy, minFont, minText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // seconds tucked against the right edge of the minute digits
        var mw = dc.getTextWidthInPixels(minText, minFont);
        dc.setColor(GREEN_MID, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + mw / 2 + 10, minCy - minH / 5, Graphics.FONT_TINY,
            ct.sec.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawVaultBoy(dc as Dc, w as Number, h as Number) as Void {
        if (mBoy == null) {
            return;
        }
        var bx = w * 775 / 1000 - mBoy.getWidth() / 2;
        var by = h * 50 / 100 - mBoy.getHeight() / 2;
        dc.drawBitmap(bx, by, mBoy);
    }

    function drawPowerPlate(dc as Dc, w as Number, h as Number) as Void {
        var bw = w * 58 / 100;
        var bh = h * 8 / 100;
        var x = w / 2 - bw / 2;
        var y = h * 78 / 100 - bh / 2;
        var r = bh / 3;

        dc.setColor(GREEN_DEEP, GREEN_DEEP);
        dc.fillRoundedRectangle(x, y, bw, bh, r);
        dc.setColor(GREEN_MID, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, bw, bh, r);

        var midX = x + bw / 2;
        dc.setColor(GREEN_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(midX, y + 5, midX, y + bh - 5);

        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 14, y + bh / 2, Graphics.FONT_TINY,
            "PWR " + mBattery.toString() + "%",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var bodyText = (mBody >= 0) ? (mBody.toString() + " BB") : ("-- BB");
        dc.drawText(midX + 14, y + bh / 2, Graphics.FONT_TINY, bodyText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Low-power: dim digits only, nothing else, to stay inside the pixel budget.
    function drawLowPower(dc as Dc, w as Number, h as Number, ct) as Void {
        dc.setColor(GREEN_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, Graphics.FONT_NUMBER_MEDIUM,
            ct.hour.format("%02d") + ":" + ct.min.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
