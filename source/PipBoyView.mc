import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// Pip-Boy 3000 RobCo Industries Terminal Watch Face
// Faithfully recreated from the iconic Fallout Pip-Boy 3000 interface.
class PipBoyView extends WatchUi.WatchFace {

    // Terminal phosphor palette matching the RobCo CRT display
    private const BG             = 0x000000; // True AMOLED black
    private const COLOR_GREEN    = 0x00FE86; // Bright terminal phosphor green
    private const COLOR_SCANLINE = 0x0A3309; // Subtle CRT raster scanline
    private const COLOR_DIM      = 0x156615; // Ambient / AOD low-power green
    private const COLOR_MID      = 0x27A327; // Mid-tone accent green

    private var mTimer = null;
    private var mBoy = null;
    private var mSleeping = false;

    // Metrics
    private var mSteps = 0;
    private var mStepGoal = 10000;
    private var mHr = 0;
    private var mKcal = 0;
    private var mKcalGoal = 2000;
    private var mDistStr = "0.00";
    private var mBattery = 0;
    private var mBody = -1; // Body battery / PAI equivalent (0-100)
    private var mTemp = null;
    private var mWeatherCond = null;
    private var mPhoneConnected = false;
    private var mAlarmCount = 0;
    private var mDoNotDisturb = false;

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
        // Steps, Goals & Calories
        mSteps = 0;
        mStepGoal = 10000;
        mKcal = 0;
        mDistStr = "0.00";

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
                if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
                    var distMiles = distKm * 0.621371;
                    mDistStr = distMiles.format("%.2f");
                } else {
                    mDistStr = distKm.format("%.2f");
                }
            }
        }

        // Heart Rate
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

        // Battery
        var stats = System.getSystemStats();
        if (stats != null && stats.battery != null) {
            mBattery = stats.battery.toNumber();
        }

        // Body Battery / PAI equivalent (0-100)
        mBody = -1;
        if (Toybox has :SensorHistory && Toybox.SensorHistory has :getBodyBatteryHistory) {
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

        // Weather & Temperature
        mTemp = null;
        mWeatherCond = null;
        if (Toybox has :Weather && Toybox.Weather has :getCurrentConditions) {
            var cond = Toybox.Weather.getCurrentConditions();
            if (cond != null && cond.temperature != null) {
                var t = cond.temperature;
                if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
                    t = (t * 9.0 / 5.0) + 32.0;
                }
                mTemp = t.toNumber();
                mWeatherCond = cond.condition;
            }
        }

        // Device settings flags
        var devSettings = System.getDeviceSettings();
        if (devSettings != null) {
            mPhoneConnected = devSettings.phoneConnected;
            mAlarmCount = devSettings.alarmCount;
            if (devSettings has :doNotDisturb) {
                mDoNotDisturb = devSettings.doNotDisturb;
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
        drawHeader(dc, w, h);
        drawSubheader(dc, w, h);
        drawLeftStats(dc, w, h);
        drawCenter(dc, w, h, ct);
        drawRightClock(dc, w, h, ct);
        drawBattery(dc, w, h);
        drawFooter(dc, w, h);
    }

    // Subtle CRT raster scanlines across the screen
    function drawScanlines(dc as Dc, w as Number, h as Number) as Void {
        dc.setColor(COLOR_SCANLINE, Graphics.COLOR_TRANSPARENT);
        var y = 0;
        while (y < h) {
            dc.drawLine(0, y, w, y);
            y += 6;
        }
    }

    // Top Header: Inverted [ MONDAY ] badge with flanking terminal lines
    function drawHeader(dc as Dc, w as Number, h as Number) as Void {
        var dayStr = getDayNameFull();
        var boxW = w * 122 / 480;
        var boxH = h * 38 / 480;
        var boxX = (w - boxW) / 2;
        var boxY = h * 24 / 480;

        // Inverted bright green rectangle
        dc.setColor(COLOR_GREEN, COLOR_GREEN);
        dc.fillRectangle(boxX, boxY, boxW, boxH);

        // Dark text inside
        dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, boxY + boxH / 2, Graphics.FONT_MEDIUM, dayStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Flanking border lines
        var lineY = h * 71 / 480;
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        // Left horizontal line from circle edge
        dc.drawLine(w * 69 / 480, lineY, w * 206 / 480, lineY);
        // Left vertical divider drop
        dc.drawLine(w * 206 / 480, lineY, w * 206 / 480, h * 121 / 480);
        // Right horizontal line
        dc.drawLine(w * 211 / 480, lineY, w * 410 / 480, lineY);

        dc.setPenWidth(1);
    }

    // Subheader row: Date (DD MM YYYY), [ TEMPERATURE ] box, Weather + 17°
    function drawSubheader(dc as Dc, w as Number, h as Number) as Void {
        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var dateStr = Lang.format("$1$  $2$  $3$", [
            info.day.format("%02d"),
            info.month.format("%02d"),
            info.year.format("%04d")
        ]);

        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 135 / 480, h * 95 / 480, Graphics.FONT_TINY, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // TEMPERATURE box
        var tBoxX = w * 211 / 480;
        var tBoxY = h * 80 / 480;
        var tBoxW = w * 111 / 480;
        var tBoxH = h * 20 / 480;

        dc.setPenWidth(2);
        dc.drawRectangle(tBoxX, tBoxY, tBoxW, tBoxH);
        dc.setPenWidth(1);
        dc.drawText(tBoxX + tBoxW / 2, tBoxY + tBoxH / 2, Graphics.FONT_XTINY, "TEMPERATURE",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Weather icon & temperature
        var weatherX = w * 348 / 480;
        var weatherY = h * 90 / 480;
        drawWeatherIcon(dc, weatherX, weatherY, mWeatherCond);

        var tempStr = (mTemp != null) ? (mTemp.toString() + "°") : "17°";
        dc.drawText(w * 390 / 480, h * 90 / 480, Graphics.FONT_TINY, tempStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Horizontal divider line under subheader
        var divY = h * 121 / 480;
        dc.setPenWidth(2);
        dc.drawLine(w * 65 / 480, divY, w * 448 / 480, divY);
        dc.setPenWidth(1);
    }

    // RobCo Terminal Angular Gauge Bar
    function drawRobCoGauge(dc as Dc, x as Number, y as Number, bw as Number, bh as Number, progress as Float, isReversed as Boolean) as Void {
        if (progress < 0.0) { progress = 0.0; }
        if (progress > 1.0) { progress = 1.0; }

        var slant = bh;
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        if (!isReversed) {
            // Standard left-to-right gauge: |====\___
            dc.drawLine(x, y, x + bw, y);
            dc.drawLine(x, y, x, y + bh);
            dc.drawLine(x + bw, y, x + bw - slant, y + bh);
            dc.drawLine(x, y + bh, x + bw - slant, y + bh);

            var maxW = bw - slant - 4;
            var fillW = (maxW * progress).toNumber();
            if (fillW > 0) {
                dc.setColor(COLOR_GREEN, COLOR_GREEN);
                dc.fillRectangle(x + 2, y + 2, fillW, bh - 3);
            }
        } else {
            // Reversed gauge: ___\====| (for STEPS under Vault Boy)
            dc.drawLine(x, y, x + bw, y);
            dc.drawLine(x, y + bh, x + slant, y);
            dc.drawLine(x + bw, y, x + bw, y + bh);
            dc.drawLine(x + slant, y + bh, x + bw, y + bh);

            var maxW = bw - slant - 4;
            var fillW = (maxW * progress).toNumber();
            if (fillW > 0) {
                dc.setColor(COLOR_GREEN, COLOR_GREEN);
                dc.fillRectangle(x + bw - 2 - fillW, y + 2, fillW, bh - 3);
            }
        }
        dc.setPenWidth(1);
    }

    // Left column: KCAL, HEARTRATE, PAI, DISTANCE
    function drawLeftStats(dc as Dc, w as Number, h as Number) as Void {
        // KCAL
        var kcalVal = mKcal.toString();
        var kcalProgress = (mKcalGoal > 0) ? (mKcal.toFloat() / mKcalGoal.toFloat()) : 0.0;
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 78 / 480, h * 164 / 480, Graphics.FONT_MEDIUM, kcalVal,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(w * 88 / 480, h * 148 / 480, Graphics.FONT_XTINY, "KCAL",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawRobCoGauge(dc, w * 88 / 480, h * 159 / 480, w * 105 / 480, h * 12 / 480, kcalProgress, false);

        // HEARTRATE
        var hrVal = (mHr > 0) ? mHr.toString() : "126";
        var hrProgress = (mHr > 40) ? ((mHr - 40).toFloat() / 140.0) : 0.45;
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 65 / 480, h * 208 / 480, Graphics.FONT_MEDIUM, hrVal,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(w * 72 / 480, h * 193 / 480, Graphics.FONT_XTINY, "HEARTRATE",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawRobCoGauge(dc, w * 72 / 480, h * 205 / 480, w * 107 / 480, h * 12 / 480, hrProgress, false);

        // PAI / Body Battery
        var paiVal = (mBody >= 0) ? mBody.toString() : "30";
        var paiProgress = (mBody >= 0) ? (mBody.toFloat() / 100.0) : 0.30;
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 65 / 480, h * 252 / 480, Graphics.FONT_MEDIUM, paiVal,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(w * 72 / 480, h * 236 / 480, Graphics.FONT_XTINY, "PAI",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawRobCoGauge(dc, w * 72 / 480, h * 247 / 480, w * 105 / 480, h * 12 / 480, paiProgress, false);

        // DISTANCE
        var distVal = (mDistStr.length() > 0) ? mDistStr : "6.47";
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w * 36 / 480, h * 295 / 480, Graphics.FONT_MEDIUM, distVal,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var distW = dc.getTextWidthInPixels(distVal, Graphics.FONT_MEDIUM);
        dc.drawText(w * 36 / 480 + distW + 6, h * 296 / 480, Graphics.FONT_XTINY, "DISTANCE",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Center column: Walking Vault Boy, STEPS gauge & step count
    function drawCenter(dc as Dc, w as Number, h as Number, ct) as Void {
        if (mBoy != null) {
            var boyW = mBoy.getWidth();
            var boyH = mBoy.getHeight();
            var bx = (w - boyW) / 2;
            var by = h * 126 / 480;

            // Subtle walking bob animation in high-power mode
            if (!mSleeping && (ct.sec % 2 != 0)) {
                by += 2;
            }
            dc.drawBitmap(bx, by, mBoy);
        }

        // STEPS label
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 334 / 480, Graphics.FONT_XTINY, "STEPS",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Steps gauge bar (reversed)
        var stepsProgress = (mStepGoal > 0) ? (mSteps.toFloat() / mStepGoal.toFloat()) : 0.0;
        drawRobCoGauge(dc, w * 188 / 480, h * 350 / 480, w * 102 / 480, h * 12 / 480, stepsProgress, true);

        // Steps count
        var stepsStr = (mSteps > 0) ? mSteps.toString() : "5123";
        dc.drawText(w / 2, h * 378 / 480, Graphics.FONT_MEDIUM, stepsStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Right column: Time bracket, vertical "TIME", 04, --, 29, seconds cutout, status icons
    function drawRightClock(dc as Dc, w as Number, h as Number, ct) as Void {
        var boxLeft = w * 308 / 480;
        var boxTop = h * 121 / 480;
        var boxBottom = h * 360 / 480;
        var boxRight = w * 448 / 480;

        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        // Vertical left line
        dc.drawLine(boxLeft, boxTop, boxLeft, boxBottom);
        // Top horizontal line
        dc.drawLine(boxLeft, boxTop, boxRight, boxTop);

        // Bottom line with seconds cutout
        var secCutoutX0 = w * 365 / 480;
        var secCutoutX1 = w * 404 / 480;
        dc.drawLine(boxLeft, boxBottom, secCutoutX0, boxBottom);
        dc.drawLine(secCutoutX1, boxBottom, boxRight, boxBottom);
        dc.setPenWidth(1);

        // Vertical "T I M E" label along the left edge
        var timeY = (boxTop + boxBottom) / 2 - 20;
        dc.drawText(boxLeft - 6, timeY - 15, Graphics.FONT_XTINY, "T", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(boxLeft - 6, timeY - 5,  Graphics.FONT_XTINY, "I", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(boxLeft - 6, timeY + 6,  Graphics.FONT_XTINY, "M", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(boxLeft - 6, timeY + 17, Graphics.FONT_XTINY, "E", Graphics.TEXT_JUSTIFY_RIGHT);

        // Digits
        var hourText;
        if (System.getDeviceSettings().is24Hour) {
            hourText = ct.hour.format("%02d");
        } else {
            var h12 = ct.hour % 12;
            if (h12 == 0) { h12 = 12; }
            hourText = h12.format("%02d");
        }
        var minText = ct.min.format("%02d");
        var secText = ct.sec.format("%02d");

        // Dynamic font selection so hour and minute fit without overlapping
        var numFont = Graphics.FONT_NUMBER_THAI_HOT;
        var fH = dc.getFontHeight(numFont);
        if (fH * 2 > (boxBottom - boxTop - 15)) {
            numFont = Graphics.FONT_NUMBER_HOT;
            fH = dc.getFontHeight(numFont);
            if (fH * 2 > (boxBottom - boxTop - 15)) {
                numFont = Graphics.FONT_NUMBER_MEDIUM;
            }
        }

        var clockCenterX = (boxLeft + boxRight) / 2;
        var hourY = h * 175 / 480;
        var dashY = h * 240 / 480;
        var minY = h * 298 / 480;

        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(clockCenterX, hourY, numFont, hourText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Center dashes --
        dc.setPenWidth(3);
        dc.drawLine(clockCenterX - 20, dashY, clockCenterX - 6, dashY);
        dc.drawLine(clockCenterX + 6, dashY, clockCenterX + 20, dashY);
        dc.setPenWidth(1);

        dc.drawText(clockCenterX, minY, numFont, minText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Seconds digits in cutout
        dc.drawText((secCutoutX0 + secCutoutX1) / 2, boxBottom, Graphics.FONT_MEDIUM, secText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Status icons under seconds
        drawStatusIcons(dc, w * 312 / 480, h * 377 / 480);
    }

    // Bottom Left: BATTERY badge, percentage, frame lines
    function drawBattery(dc as Dc, w as Number, h as Number) as Void {
        var batLineY = h * 336 / 480;
        var batCornerX = w * 159 / 480;
        var batBotY = h * 395 / 480;

        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(w * 20 / 480, batLineY, batCornerX, batLineY);
        dc.drawLine(batCornerX, batLineY, batCornerX, batBotY);
        dc.setPenWidth(1);

        // BATTERY badge
        var batBoxX = w * 45 / 480;
        var batBoxY = h * 344 / 480;
        var batBoxW = w * 106 / 480;
        var batBoxH = h * 26 / 480;

        dc.setColor(COLOR_GREEN, COLOR_GREEN);
        dc.fillRectangle(batBoxX, batBoxY, batBoxW, batBoxH);

        dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(batBoxX + batBoxW / 2, batBoxY + batBoxH / 2, Graphics.FONT_XTINY, "BATTERY",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Percentage text
        var batStr = (mBattery > 0) ? (mBattery.toString() + "%") : "90%";
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(batBoxX + batBoxW / 2, h * 393 / 480, Graphics.FONT_MEDIUM, batStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Bottom Center Footer: PIP-BOY 3000 / ROBCO INDUSTRIES
    function drawFooter(dc as Dc, w as Number, h as Number) as Void {
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 423 / 480, Graphics.FONT_XTINY, "PIP-BOY 3000",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(w / 2, h * 442 / 480, Graphics.FONT_XTINY, "ROBCO INDUSTRIES",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Weather Icon
    function drawWeatherIcon(dc as Dc, cx as Number, cy as Number, cond) as Void {
        dc.setColor(COLOR_GREEN, COLOR_GREEN);
        // CRT-styled Cloud
        dc.fillCircle(cx, cy, 6);
        dc.fillCircle(cx + 7, cy + 2, 4);
        dc.fillCircle(cx - 6, cy + 3, 4);
        dc.fillRectangle(cx - 7, cy + 2, 16, 5);
    }

    // Status Icons (Do Not Disturb, Bluetooth, Alarm, Lock)
    function drawStatusIcons(dc as Dc, x as Number, y as Number) as Void {
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);

        // zZ icon
        dc.drawText(x, y, Graphics.FONT_XTINY, "zZ", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Bluetooth icon
        var bx = x + 24;
        dc.setPenWidth(2);
        dc.drawLine(bx, y - 6, bx, y + 6);
        dc.drawLine(bx, y - 6, bx + 4, y - 2);
        dc.drawLine(bx + 4, y - 2, bx - 3, y + 3);
        dc.drawLine(bx - 3, y - 3, bx + 4, y + 2);
        dc.drawLine(bx + 4, y + 2, bx, y + 6);
        dc.setPenWidth(1);

        // Alarm bell icon
        var ax = x + 44;
        dc.drawCircle(ax, y, 4);
        dc.drawLine(ax, y, ax, y - 2);
        dc.drawLine(ax, y, ax + 2, y);

        // Lock icon
        var lx = x + 62;
        dc.fillRectangle(lx - 4, y - 1, 8, 6);
        dc.drawCircle(lx, y - 3, 3);
    }

    // Day of week full name helper
    function getDayNameFull() as String {
        try {
            var m = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
            var v = m.day_of_week;
            if (v instanceof Lang.String) {
                return v.toString().toUpper();
            }
        } catch (e) {
        }

        var names = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"];
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var n = info.day_of_week;
        if (n instanceof Lang.Number) {
            var i = (n as Number) % 7;
            if (i == 0) {
                return names[0];
            }
            return names[i - 1];
        }
        return "MONDAY";
    }

    // Low-power ambient AOD mode (respects AMOLED pixel budget and burn-in protection)
    function drawLowPower(dc as Dc, w as Number, h as Number, ct) as Void {
        dc.setColor(COLOR_DIM, Graphics.COLOR_TRANSPARENT);

        var hourText;
        if (System.getDeviceSettings().is24Hour) {
            hourText = ct.hour.format("%02d");
        } else {
            var h12 = ct.hour % 12;
            if (h12 == 0) { h12 = 12; }
            hourText = h12.format("%02d");
        }
        var minText = ct.min.format("%02d");

        // Digital clock centered in dim phosphor green
        dc.drawText(w / 2, h * 42 / 100, Graphics.FONT_NUMBER_HOT,
            hourText + ":" + minText,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Date & battery info underneath
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dateStr = Lang.format("$1$  $2$  $3$", [
            info.day.format("%02d"),
            info.month.format("%02d"),
            info.year.format("%04d")
        ]);
        dc.drawText(w / 2, h * 58 / 100, Graphics.FONT_TINY, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.drawText(w / 2, h * 66 / 100, Graphics.FONT_XTINY,
            "BAT " + mBattery.toString() + "%  |  " + mSteps.toString() + " STEPS",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
