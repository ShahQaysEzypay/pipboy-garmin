import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// Pip-Boy 3000 (Qays Industries) Watch Face.
// Uses a subpixel-accurate condensed Monofonto vector glyph renderer so all
// labels, numbers, and giant clock digits scale cleanly to any round screen
// (e.g. Forerunner 165 390x390) without overflowing or colliding.
class PipBoyView extends WatchUi.WatchFace {

    private const BG             = 0x000000;
    private const COLOR_GREEN    = 0x00FE86;
    private const COLOR_SCANLINE = 0x0A3309;
    private const COLOR_DIM      = 0x156615;

    private const ALIGN_LEFT   = 0;
    private const ALIGN_CENTER = 1;
    private const ALIGN_RIGHT  = 2;

    private var mTimer = null;
    private var mBoyFrames as Array<WatchUi.BitmapResource?> = [null, null, null, null, null, null, null, null];
    private var mIsRunning = false;
    private var mAnimStep = 0;
    private var mLastRefreshMin = -1;
    private var mSleeping = false;

    // Metrics
    private var mSteps = 0;
    private var mStepGoal = 10000;
    private var mHr = 0;
    private var mKcal = 0;
    private var mKcalGoal = 2000;
    private var mDistStr = "0.00";
    private var mBattery = 0;
    private var mBody = -1;
    private var mTemp = null;
    private var mPhoneConnected = false;
    private var mAlarmCount = 0;
    private var mDoNotDisturb = false;

    // Bit-packed 8x16 Monofonto glyph stroke table:
    // Each integer encodes one segment: (x0 << 14) | (y0 << 9) | (x1 << 5) | y1
    private var mGlyphs as Dictionary<String, Array<Number>> = {
        "0" => [2081, 16992, 49312, 82145, 115460, 133388, 137455, 122544, 90224, 57391, 24076, 6148],
        "1" => [18080, 82096],
        "2" => [2081, 16992, 49312, 82145, 115460, 133382, 134376, 118800, 8464],
        "3" => [1569, 16992, 49312, 82145, 115459, 132869, 133863, 118440, 86120, 86249, 119563, 136973, 137967, 122544, 90224, 57391, 24077],
        "4" => [98315, 5899, 98512],
        "5" => [131072, 7, 3686, 52390, 85223, 118537, 135949, 137967, 122544, 90224, 57391, 24077],
        "6" => [115904, 98400, 49186, 17413, 2572, 6191, 24176, 57520, 90351, 122636, 137482, 136424, 118951, 85607, 52776, 20490],
        "7" => [1536, 256, 131152],
        "8" => [53287, 19973, 2563, 1569, 16992, 49312, 82145, 115459, 132869, 133863, 118440, 86120, 53289, 21003, 5645, 6703, 24176, 57520, 90351, 122637, 137995, 136937, 119464],
        "9" => [134376, 118953, 86633, 53800, 20486, 3076, 2081, 16992, 49312, 82145, 115460, 133387, 136942, 122032, 90192, 41006],
        "A" => [8320, 65808, 22251],
        "B" => [16, 8368, 90351, 122637, 137994, 136424, 118952, 86024, 160, 82145, 115459, 132870, 134375, 118440],
        "C" => [132833, 115360, 82016, 49185, 16899, 1549, 6703, 24176, 57520, 90351, 122637],
        "D" => [16, 8336, 73966, 122123, 136965, 133858, 115840, 65536],
        "E" => [131072, 16, 8464, 4296],
        "F" => [131072, 16, 4296],
        "G" => [132833, 115360, 82016, 49185, 16899, 1549, 6703, 24176, 57520, 90351, 122637, 137992, 135304],
        "H" => [16, 131344, 4360],
        "I" => [32960, 65680, 41168],
        "J" => [131341, 137967, 122544, 90224, 57391, 24077],
        "K" => [16, 131081, 52496],
        "L" => [16, 8464],
        "M" => [8192, 137, 70400, 131344],
        "N" => [8192, 272, 139520],
        "O" => [2081, 16992, 49312, 82145, 115460, 133388, 137455, 122544, 90224, 57391, 24076, 6148],
        "P" => [8192, 160, 82145, 115459, 132870, 134376, 118953, 86537],
        "Q" => [2081, 16992, 49312, 82145, 115460, 133388, 137455, 122544, 90224, 57391, 24076, 6148, 54578],
        "R" => [8192, 160, 82145, 115459, 132870, 134376, 118953, 86537, 86800],
        "S" => [132833, 115360, 82016, 49185, 16899, 1541, 2599, 20201, 119563, 136973, 137967, 122544, 90224, 57391, 24077],
        "T" => [256, 65680],
        "U" => [13, 6703, 24176, 57520, 90351, 122637, 137984],
        "V" => [144, 73984],
        "W" => [80, 41095, 69328, 106752],
        "X" => [272, 131088],
        "Y" => [136, 69888, 69776],
        "Z" => [256, 131088, 8464],
        "z" => [3334, 134160, 8464],
        "-" => [4360],
        ":" => [51364, 84134, 85094, 52324, 54955, 87725, 88685, 55915],
        "." => [23662, 56432, 57392, 24622],
        "%" => [8448, 576, 32866, 50212, 18433, 88812, 121102, 138448, 106669],
        "°" => [33408, 65729, 99011, 99972, 67651, 34369]
    };

    function initialize() {
        WatchFace.initialize();
    }

    // ------------------------------------------------------------- lifecycle --

    function onLayout(dc as Dc) as Void {
        loadAnimFrames(mIsRunning);
    }

    // Load either the 8 walking frames (HR <= 100) or the 8 running frames (HR > 100).
    // Releases previous frames first to keep heap memory usage low.
    function loadAnimFrames(running as Boolean) as Void {
        for (var i = 0; i < 8; i++) {
            mBoyFrames[i] = null;
        }
        if (running) {
            mBoyFrames[0] = WatchUi.loadResource(Rez.Drawables.VaultBoyRun0) as WatchUi.BitmapResource;
            mBoyFrames[1] = WatchUi.loadResource(Rez.Drawables.VaultBoyRun1) as WatchUi.BitmapResource;
            mBoyFrames[2] = WatchUi.loadResource(Rez.Drawables.VaultBoyRun2) as WatchUi.BitmapResource;
            mBoyFrames[3] = WatchUi.loadResource(Rez.Drawables.VaultBoyRun3) as WatchUi.BitmapResource;
            mBoyFrames[4] = WatchUi.loadResource(Rez.Drawables.VaultBoyRun4) as WatchUi.BitmapResource;
            mBoyFrames[5] = WatchUi.loadResource(Rez.Drawables.VaultBoyRun5) as WatchUi.BitmapResource;
            mBoyFrames[6] = WatchUi.loadResource(Rez.Drawables.VaultBoyRun6) as WatchUi.BitmapResource;
            mBoyFrames[7] = WatchUi.loadResource(Rez.Drawables.VaultBoyRun7) as WatchUi.BitmapResource;
        } else {
            mBoyFrames[0] = WatchUi.loadResource(Rez.Drawables.VaultBoy) as WatchUi.BitmapResource;
            mBoyFrames[1] = WatchUi.loadResource(Rez.Drawables.VaultBoy1) as WatchUi.BitmapResource;
            mBoyFrames[2] = WatchUi.loadResource(Rez.Drawables.VaultBoy2) as WatchUi.BitmapResource;
            mBoyFrames[3] = WatchUi.loadResource(Rez.Drawables.VaultBoy3) as WatchUi.BitmapResource;
            mBoyFrames[4] = WatchUi.loadResource(Rez.Drawables.VaultBoy4) as WatchUi.BitmapResource;
            mBoyFrames[5] = WatchUi.loadResource(Rez.Drawables.VaultBoy5) as WatchUi.BitmapResource;
            mBoyFrames[6] = WatchUi.loadResource(Rez.Drawables.VaultBoy6) as WatchUi.BitmapResource;
            mBoyFrames[7] = WatchUi.loadResource(Rez.Drawables.VaultBoy7) as WatchUi.BitmapResource;
        }
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
        refresh();
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
        var interval = mIsRunning ? 90 : 150;
        mTimer.start(method(:onTick), interval, true);
    }

    function stopTimer() as Void {
        if (mTimer != null) {
            mTimer.stop();
        }
    }

    function onTick() as Void {
        mAnimStep = (mAnimStep + 1) % 8;
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------------- data ---

    // Fast live metrics (steps, calories, distance in KM, live heart rate)
    function refreshFast() as Void {
        var info = ActivityMonitor.getInfo();
        if (info != null) {
            if (info.steps != null) {
                mSteps = info.steps;
            }
            if (info.stepGoal != null && info.stepGoal > 0) {
                mStepGoal = info.stepGoal;
            }
            if (info.calories != null) {
                mKcal = info.calories;
            }
            if (info.distance != null) {
                var distKm = info.distance.toFloat() / 100000.0;
                mDistStr = distKm.format("%.2f");
            }
        }

        // Live Heart Rate first, then recent history fallback
        var actInfo = Activity.getActivityInfo();
        if (actInfo != null && actInfo.currentHeartRate != null && actInfo.currentHeartRate > 25) {
            mHr = actInfo.currentHeartRate;
        } else {
            var hrIter = ActivityMonitor.getHeartRateHistory(5, true);
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
        }

        // Switch between Walking (HR <= 100) and Running (HR > 100)
        var shouldRun = (mHr > 100);
        if (shouldRun != mIsRunning) {
            mIsRunning = shouldRun;
            loadAnimFrames(mIsRunning);
            if (!mSleeping && mTimer != null) {
                mTimer.stop();
                startTimer();
            }
        }
    }

    function refresh() as Void {
        refreshFast();

        // Battery
        var stats = System.getSystemStats();
        if (stats != null && stats.battery != null) {
            mBattery = stats.battery.toNumber();
        }

        // Stamina / Body Battery (0-100)
        if (Toybox has :SensorHistory && Toybox.SensorHistory has :getBodyBatteryHistory) {
            var bbIter = SensorHistory.getBodyBatteryHistory({
                :period => 5,
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

        // Weather Temperature
        mTemp = null;
        if (Toybox has :Weather && Toybox.Weather has :getCurrentConditions) {
            var cond = Toybox.Weather.getCurrentConditions();
            if (cond != null && cond.temperature != null) {
                var t = cond.temperature;
                if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
                    t = (t * 9.0 / 5.0) + 32.0;
                }
                mTemp = t.toNumber();
            }
        }

        // System status flags
        var devSettings = System.getDeviceSettings();
        if (devSettings != null) {
            mPhoneConnected = devSettings.phoneConnected;
            mAlarmCount = devSettings.alarmCount;
            if (devSettings has :doNotDisturb) {
                mDoNotDisturb = devSettings.doNotDisturb;
            }
        }
    }

    // -------------------------------------------------------------- helpers ---

    // Scale a 480-space coordinate to current screen dimension
    function sc(dim as Number, v480 as Number) as Number {
        return (v480 * dim + 240) / 480;
    }

    // Subpixel-accurate Pip-Boy Monofonto vector text renderer.
    // x480, y480 are in 480-space; cw10, ch10, gap10 are in 1/10th of a 480-space unit
    // (e.g. cw10 = 68 means 6.8 units in 480-space).
    function drawPipText(
        dc as Dc,
        w as Number,
        h as Number,
        text as String,
        x480 as Number,
        y480 as Number,
        cw10 as Number,
        ch10 as Number,
        gap10 as Number,
        penW as Number,
        color as Number,
        align as Number,
        rot90 as Boolean
    ) as Void {
        var n = text.length();
        if (n == 0) {
            return;
        }
        if (penW < 1) {
            penW = 1;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(penW);
        var halfPen = penW / 2;

        if (!rot90) {
            var totalW10 = (n - 1) * gap10;
            for (var k = 0; k < n; k++) {
                var chK = text.substring(k, k + 1);
                totalW10 += chK.equals(".") ? (cw10 * 5) / 10 : cw10;
            }
            var x0_10 = x480 * 10;
            if (align == ALIGN_CENTER) {
                x0_10 = x0_10 - totalW10 / 2;
            } else if (align == ALIGN_RIGHT) {
                x0_10 = x0_10 - totalW10;
            }
            var y0_10 = y480 * 10 - ch10 / 2;
            var cx10 = x0_10;

            for (var i = 0; i < n; i++) {
                var chStr = text.substring(i, i + 1);
                var adv10 = chStr.equals(".") ? (cw10 * 5) / 10 : cw10;
                var segs = mGlyphs.get(chStr) as Array<Number>?;
                if (segs != null) {
                    var numSegs = segs.size();
                    for (var j = 0; j < numSegs; j++) {
                        var s = segs[j];
                        var gx0 = (s >> 14) & 0x0F;
                        var gy0 = (s >> 9)  & 0x1F;
                        var gx1 = (s >> 5)  & 0x0F;
                        var gy1 =  s        & 0x1F;

                        var px0 = ((cx10 + (gx0 * cw10) / 8) * w + 2400) / 4800;
                        var py0 = ((y0_10 + (gy0 * ch10) / 16) * h + 2400) / 4800;
                        var px1 = ((cx10 + (gx1 * cw10) / 8) * w + 2400) / 4800;
                        var py1 = ((y0_10 + (gy1 * ch10) / 16) * h + 2400) / 4800;

                        dc.drawLine(px0, py0, px1, py1);
                        if (penW >= 4) {
                            dc.fillCircle(px0, py0, halfPen);
                            dc.fillCircle(px1, py1, halfPen);
                        }
                    }
                }
                cx10 += adv10 + gap10;
            }
        } else {
            var totalH10 = n * cw10 + (n - 1) * gap10;
            var y0_10 = y480 * 10 - totalH10 / 2;
            var x0_10 = x480 * 10 - ch10 / 2;
            var step10 = cw10 + gap10;

            for (var i = 0; i < n; i++) {
                var chStr = text.substring(i, i + 1);
                var segs = mGlyphs.get(chStr) as Array<Number>?;
                if (segs != null) {
                    var cy10 = y0_10 + i * step10;
                    var numSegs = segs.size();
                    for (var j = 0; j < numSegs; j++) {
                        var s = segs[j];
                        var gx0 = (s >> 14) & 0x0F;
                        var gy0 = (s >> 9)  & 0x1F;
                        var gx1 = (s >> 5)  & 0x0F;
                        var gy1 =  s        & 0x1F;

                        var rx0 = ((x0_10 + ch10 - (gy0 * ch10) / 16) * w + 2400) / 4800;
                        var ry0 = ((cy10 + (gx0 * cw10) / 8) * h + 2400) / 4800;
                        var rx1 = ((x0_10 + ch10 - (gy1 * ch10) / 16) * w + 2400) / 4800;
                        var ry1 = ((cy10 + (gx1 * cw10) / 8) * h + 2400) / 4800;

                        dc.drawLine(rx0, ry0, rx1, ry1);
                    }
                }
            }
        }
        dc.setPenWidth(1);
    }

    // ---------------------------------------------------------------- drawing --

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(BG, BG);
        dc.clear();

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var ct = System.getClockTime();

        if (mSleeping) {
            drawLowPower(dc, w, h, ct);
            return;
        }

        if (ct.min != mLastRefreshMin) {
            mLastRefreshMin = ct.min;
            refresh();
        } else if (mAnimStep == 0) {
            refreshFast();
        }

        drawScanlines(dc, w, h);
        drawHeader(dc, w, h);
        drawSubheader(dc, w, h);
        drawLeftStats(dc, w, h);
        drawCenter(dc, w, h);
        drawRightClock(dc, w, h, ct);
        drawBattery(dc, w, h);
        drawFooter(dc, w, h);
    }

    // Subtle CRT raster scanlines across the screen
    function drawScanlines(dc as Dc, w as Number, h as Number) as Void {
        dc.setColor(COLOR_SCANLINE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        var y = 0;
        while (y < h) {
            dc.drawLine(0, y, w, y);
            y += 5;
        }
    }

    // Top Header: Inverted [ MONDAY ] badge with flanking terminal lines
    function drawHeader(dc as Dc, w as Number, h as Number) as Void {
        var dayStr = getDayNameFull();
        var n = dayStr.length();
        // Dynamic box width in 480-space so WEDNESDAY fits with clean padding
        var textW480 = (n * 140 + (n - 1) * 40) / 10;
        var boxW480 = textW480 + 18;
        if (boxW480 < 121) {
            boxW480 = 121;
        }

        var boxW = sc(w, boxW480);
        var boxH = sc(h, 38);
        var boxX = (w - boxW) / 2;
        var boxY = sc(h, 24);

        dc.setColor(COLOR_GREEN, COLOR_GREEN);
        dc.fillRectangle(boxX, boxY, boxW, boxH);

        drawPipText(dc, w, h, dayStr, 240, 43, 140, 250, 40, 3, BG, ALIGN_CENTER, false);

        // Flanking header lines (left line drops down to y=100 at x=205)
        var lineY = sc(h, 72);
        var divX = sc(w, 205);
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(sc(w, 69), lineY, divX, lineY);
        dc.drawLine(divX, lineY, divX, sc(h, 100));
        dc.drawLine(sc(w, 211), lineY, sc(w, 410), lineY);
        dc.setPenWidth(1);
    }

    // Subheader row: Date (DD MM YYYY), solid [ TEMPERATURE ] badge, Weather + Temp
    function drawSubheader(dc as Dc, w as Number, h as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dateStr = Lang.format("$1$ $2$ $3$", [
            info.day.format("%02d"),
            info.month.format("%02d"),
            info.year.format("%04d")
        ]);

        drawPipText(dc, w, h, dateStr, 130, 90, 95, 190, 40, 2, COLOR_GREEN, ALIGN_CENTER, false);

        // Solid green [ TEMPERATURE ] badge with dark text
        var tBoxX = sc(w, 211);
        var tBoxY = sc(h, 80);
        var tBoxW = sc(w, 111);
        var tBoxH = sc(h, 20);
        dc.setColor(COLOR_GREEN, COLOR_GREEN);
        dc.fillRectangle(tBoxX, tBoxY, tBoxW, tBoxH);

        drawPipText(dc, w, h, "TEMPERATURE", 266, 90, 65, 120, 22, 2, BG, ALIGN_CENTER, false);

        // Weather icon (cloud + sun arch)
        drawWeatherIcon(dc, w, h);

        var tempStr = (mTemp != null) ? (mTemp.toString() + "°") : "--°";
        drawPipText(dc, w, h, tempStr, 390, 93, 105, 190, 35, 2, COLOR_GREEN, ALIGN_CENTER, false);
    }

    // Open-bottom RobCo gauge bar with hanging triangle fang and floating fill bar
    function drawRobCoGauge(dc as Dc, w as Number, h as Number, x480 as Number, y480 as Number, bw480 as Number, bh480 as Number, progress as Float, isReversed as Boolean) as Void {
        if (progress < 0.0) { progress = 0.0; }
        if (progress > 1.0) { progress = 1.0; }

        var x = sc(w, x480);
        var y = sc(h, y480);
        var bw = sc(w, bw480);
        var bh = sc(h, bh480);

        dc.setColor(COLOR_GREEN, COLOR_GREEN);
        dc.setPenWidth(2);

        if (!isReversed) {
            // Top horizontal rail + left vertical tick
            dc.drawLine(x, y, x + bw, y);
            dc.drawLine(x, y, x, y + bh);

            // Hanging triangle fang near right end
            var tx = sc(w, x480 + bw480 - 14);
            var tw = sc(w, 8);
            dc.fillPolygon([[tx, y], [tx + tw, y], [tx, y + bh - 2]]);

            // Floating progress bar inside
            var maxW = sc(w, bw480 - 20);
            var fillW = (maxW * progress).toNumber();
            if (fillW > 0) {
                dc.fillRectangle(x + sc(w, 4), y + sc(h, 4), fillW, bh - sc(h, 4));
            }
        } else {
            // Reversed for STEPS: top rail + right vertical tick + left hanging fang
            dc.drawLine(x, y, x + bw, y);
            dc.drawLine(x + bw, y, x + bw, y + bh);

            var tx = sc(w, x480 + 14);
            var tw = sc(w, 8);
            dc.fillPolygon([[tx - tw, y], [tx, y], [tx, y + bh - 2]]);

            var maxW = sc(w, bw480 - 20);
            var fillW = (maxW * progress).toNumber();
            if (fillW > 0) {
                dc.fillRectangle(x + bw - sc(w, 4) - fillW, y + sc(h, 4), fillW, bh - sc(h, 4));
            }
        }
        dc.setPenWidth(1);
    }

    // Left column: KCAL, HEARTRATE, STAMINA, KM (all aligned on the same vertical axis)
    function drawLeftStats(dc as Dc, w as Number, h as Number) as Void {
        // KCAL
        var kcalVal = mKcal.toString();
        var kcalProgress = (mKcalGoal > 0) ? (mKcal.toFloat() / mKcalGoal.toFloat()) : 0.0;
        drawPipText(dc, w, h, kcalVal, 68, 163, 95, 190, 32, 2, COLOR_GREEN, ALIGN_RIGHT, false);
        drawPipText(dc, w, h, "KCAL", 76, 148, 68, 120, 24, 2, COLOR_GREEN, ALIGN_LEFT, false);
        drawRobCoGauge(dc, w, h, 76, 159, 105, 13, kcalProgress, false);

        // HEARTRATE
        var hrVal = (mHr > 0) ? mHr.toString() : "--";
        var hrProgress = (mHr > 40) ? ((mHr - 40).toFloat() / 140.0) : 0.0;
        drawPipText(dc, w, h, hrVal, 68, 207, 95, 190, 32, 2, COLOR_GREEN, ALIGN_RIGHT, false);
        drawPipText(dc, w, h, "HEARTRATE", 76, 192, 68, 120, 24, 2, COLOR_GREEN, ALIGN_LEFT, false);
        drawRobCoGauge(dc, w, h, 76, 203, 105, 13, hrProgress, false);

        // STAMINA (Body Battery 0-100)
        var staminaVal = (mBody >= 0) ? mBody.toString() : "--";
        var staminaProgress = (mBody >= 0) ? (mBody.toFloat() / 100.0) : 0.0;
        drawPipText(dc, w, h, staminaVal, 68, 251, 95, 190, 32, 2, COLOR_GREEN, ALIGN_RIGHT, false);
        drawPipText(dc, w, h, "STAMINA", 76, 236, 68, 120, 24, 2, COLOR_GREEN, ALIGN_LEFT, false);
        drawRobCoGauge(dc, w, h, 76, 247, 105, 13, staminaProgress, false);

        // KM (Distance in kilometers)
        drawPipText(dc, w, h, mDistStr, 68, 295, 95, 190, 26, 2, COLOR_GREEN, ALIGN_RIGHT, false);
        drawPipText(dc, w, h, "KM", 76, 298, 68, 120, 24, 2, COLOR_GREEN, ALIGN_LEFT, false);
    }

    // Center column: 8-frame Animated Walking Vault Boy, STEPS gauge & step count
    function drawCenter(dc as Dc, w as Number, h as Number) as Void {
        var idx = mSleeping ? 4 : (mAnimStep % 8);
        var sprite = mBoyFrames[idx];
        if (sprite == null) {
            sprite = mBoyFrames[0];
        }
        if (sprite != null) {
            var bx = sc(w, 240) - sprite.getWidth() / 2;
            var by = sc(h, 125);
            dc.drawBitmap(bx, by, sprite);
        }

        // STEPS label, reversed RobCo gauge, and step count
        drawPipText(dc, w, h, "STEPS", 240, 337, 72, 130, 25, 2, COLOR_GREEN, ALIGN_CENTER, false);

        var stepsProgress = (mStepGoal > 0) ? (mSteps.toFloat() / mStepGoal.toFloat()) : 0.0;
        drawRobCoGauge(dc, w, h, 188, 350, 102, 13, stepsProgress, true);

        drawPipText(dc, w, h, mSteps.toString(), 240, 381, 105, 200, 32, 2, COLOR_GREEN, ALIGN_CENTER, false);
    }

    // Right column: Time bracket, rotated 90-deg "TIME", giant Hour, --, giant Minute, status icons (no seconds)
    function drawRightClock(dc as Dc, w as Number, h as Number, ct) as Void {
        var boxLeft = sc(w, 309);
        var boxTop = sc(h, 122);
        var boxBottom = sc(h, 360);
        var boxRight = sc(w, 448);

        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        // Top horizontal line
        dc.drawLine(boxLeft, boxTop, boxRight, boxTop);
        // Left vertical line split with middle gap for rotated "TIME"
        dc.drawLine(boxLeft, boxTop, boxLeft, sc(h, 202));
        dc.drawLine(boxLeft, sc(h, 279), boxLeft, boxBottom);
        // Continuous bottom horizontal line (no seconds cutout)
        dc.drawLine(boxLeft, boxBottom, boxRight, boxBottom);
        dc.setPenWidth(1);

        // Rotated 90 deg CW "TIME" centered in the left vertical line gap
        drawPipText(dc, w, h, "TIME", 309, 241, 75, 130, 35, 2, COLOR_GREEN, ALIGN_CENTER, true);

        var hourText;
        if (System.getDeviceSettings().is24Hour) {
            hourText = ct.hour.format("%02d");
        } else {
            var h12 = ct.hour % 12;
            if (h12 == 0) { h12 = 12; }
            hourText = h12.format("%02d");
        }
        var minText = ct.min.format("%02d");

        var bigPenW = sc(w, 11);
        if (bigPenW < 6) { bigPenW = 6; }

        // Giant Hour digits
        drawPipText(dc, w, h, hourText, 388, 183, 440, 820, 160, bigPenW, COLOR_GREEN, ALIGN_CENTER, false);

        // Center dashes --
        var dashY = sc(h, 241);
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(sc(w, 369), dashY, sc(w, 384), dashY);
        dc.drawLine(sc(w, 393), dashY, sc(w, 408), dashY);
        dc.setPenWidth(1);

        // Giant Minute digits
        drawPipText(dc, w, h, minText, 388, 297, 440, 820, 160, bigPenW, COLOR_GREEN, ALIGN_CENTER, false);

        // Status icons underneath the time box
        drawStatusIcons(dc, w, h);
    }

    // Bottom Left: BATTERY badge, percentage, frame lines
    function drawBattery(dc as Dc, w as Number, h as Number) as Void {
        var batLineY = sc(h, 336);
        var batCornerX = sc(w, 159);
        var batBotY = sc(h, 395);

        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(sc(w, 20), batLineY, batCornerX, batLineY);
        dc.drawLine(batCornerX, batLineY, batCornerX, batBotY);
        dc.setPenWidth(1);

        // Solid green [ BATTERY ] badge with dark text
        var batBoxX = sc(w, 45);
        var batBoxY = sc(h, 344);
        var batBoxW = sc(w, 105);
        var batBoxH = sc(h, 26);

        dc.setColor(COLOR_GREEN, COLOR_GREEN);
        dc.fillRectangle(batBoxX, batBoxY, batBoxW, batBoxH);

        drawPipText(dc, w, h, "BATTERY", 98, 357, 85, 150, 30, 2, BG, ALIGN_CENTER, false);

        var batStr = mBattery.toString() + "%";
        drawPipText(dc, w, h, batStr, 101, 390, 105, 200, 35, 2, COLOR_GREEN, ALIGN_CENTER, false);
    }

    // Bottom Center Footer: PIP-BOY 3000 / QAYS INDUSTRIES
    function drawFooter(dc as Dc, w as Number, h as Number) as Void {
        drawPipText(dc, w, h, "PIP-BOY 3000", 240, 429, 85, 150, 45, 2, COLOR_GREEN, ALIGN_CENTER, false);
        drawPipText(dc, w, h, "QAYS INDUSTRIES", 240, 450, 64, 110, 25, 2, COLOR_GREEN, ALIGN_CENTER, false);
    }

    // Weather Icon (Cloud + Sun arch)
    function drawWeatherIcon(dc as Dc, w as Number, h as Number) as Void {
        var wx = sc(w, 343);
        var wy = sc(h, 97);
        dc.setColor(COLOR_GREEN, COLOR_GREEN);
        dc.fillCircle(wx - sc(w, 6), wy + sc(h, 2), sc(w, 5));
        dc.fillCircle(wx, wy - sc(h, 1), sc(w, 6));
        dc.fillCircle(wx + sc(w, 7), wy + sc(h, 2), sc(w, 5));
        dc.fillRectangle(wx - sc(w, 6), wy + sc(h, 1), sc(w, 13), sc(h, 6));

        dc.setPenWidth(2);
        dc.drawLine(wx - sc(w, 4), wy - sc(h, 8), wx + sc(w, 2), wy - sc(h, 10));
        dc.drawLine(wx + sc(w, 2), wy - sc(h, 10), wx + sc(w, 7), wy - sc(h, 6));
        dc.setPenWidth(1);
    }

    // Status Icons (zZ, Bluetooth, Alarm, Padlock)
    function drawStatusIcons(dc as Dc, w as Number, h as Number) as Void {
        var dndColor = mDoNotDisturb ? COLOR_GREEN : COLOR_DIM;
        drawPipText(dc, w, h, "z", 313, 377, 60, 110, 0, 2, dndColor, ALIGN_LEFT, false);
        drawPipText(dc, w, h, "Z", 321, 374, 70, 120, 0, 2, dndColor, ALIGN_LEFT, false);

        // Bluetooth icon
        var btColor = mPhoneConnected ? COLOR_GREEN : COLOR_DIM;
        dc.setColor(btColor, Graphics.COLOR_TRANSPARENT);
        var btx = sc(w, 342);
        var bty = sc(h, 375);
        dc.setPenWidth(2);
        dc.drawLine(btx, bty - sc(h, 7), btx, bty + sc(h, 7));
        dc.drawLine(btx, bty - sc(h, 7), btx + sc(w, 5), bty - sc(h, 4));
        dc.drawLine(btx + sc(w, 5), bty - sc(h, 4), btx - sc(w, 4), bty + sc(h, 4));
        dc.drawLine(btx - sc(w, 4), bty - sc(h, 4), btx + sc(w, 5), bty + sc(h, 4));
        dc.drawLine(btx + sc(w, 5), bty + sc(h, 4), btx, bty + sc(h, 7));

        // Alarm clock icon
        var alColor = (mAlarmCount > 0) ? COLOR_GREEN : COLOR_DIM;
        dc.setColor(alColor, alColor);
        var alx = sc(w, 366);
        var aly = sc(h, 376);
        dc.fillCircle(alx, aly, sc(w, 6));
        dc.drawLine(alx - sc(w, 6), aly - sc(h, 5), alx - sc(w, 3), aly - sc(h, 8));
        dc.drawLine(alx + sc(w, 6), aly - sc(h, 5), alx + sc(w, 3), aly - sc(h, 8));

        // Lock icon
        dc.setColor(COLOR_GREEN, COLOR_GREEN);
        var lkx = sc(w, 392);
        var lky = sc(h, 375);
        dc.fillRectangle(lkx - sc(w, 6), lky - sc(h, 1), sc(w, 13), sc(h, 8));
        dc.drawLine(lkx - sc(w, 4), lky - sc(h, 1), lkx - sc(w, 4), lky - sc(h, 6));
        dc.drawLine(lkx - sc(w, 4), lky - sc(h, 6), lkx + sc(w, 4), lky - sc(h, 6));
        dc.drawLine(lkx + sc(w, 4), lky - sc(h, 6), lkx + sc(w, 4), lky - sc(h, 1));
        dc.setPenWidth(1);
    }

    // Full weekday name (Garmin FORMAT_SHORT day_of_week is 1-based: 1=SUN .. 7=SAT)
    function getDayNameFull() as String {
        var names = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"];
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var n = info.day_of_week;
        if (n instanceof Lang.Number) {
            var idx = ((n as Number) - 1) % 7;
            if (idx >= 0 && idx < 7) {
                return names[idx];
            }
        }
        return "MONDAY";
    }

    // Low-power ambient AOD mode
    function drawLowPower(dc as Dc, w as Number, h as Number, ct) as Void {
        var hourText;
        if (System.getDeviceSettings().is24Hour) {
            hourText = ct.hour.format("%02d");
        } else {
            var h12 = ct.hour % 12;
            if (h12 == 0) { h12 = 12; }
            hourText = h12.format("%02d");
        }
        var minText = ct.min.format("%02d");

        drawPipText(dc, w, h, hourText + ":" + minText, 240, 210, 260, 480, 90, 4, COLOR_DIM, ALIGN_CENTER, false);

        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dateStr = Lang.format("$1$ $2$ $3$", [
            info.day.format("%02d"),
            info.month.format("%02d"),
            info.year.format("%04d")
        ]);
        drawPipText(dc, w, h, dateStr, 240, 275, 95, 180, 40, 2, COLOR_DIM, ALIGN_CENTER, false);
    }
}
