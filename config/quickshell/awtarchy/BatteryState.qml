pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: root

    property var telemetryData: emptyTelemetry()

    readonly property var device: UPower.displayDevice
    readonly property bool available: device.ready && device.isLaptopBattery
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string batteryTelemetryScript: configHome
        + "/hypr/scripts/quickshell_battery_telemetry.sh"
    readonly property bool telemetryOverrideActive: available && telemetryData.override === true
    readonly property int telemetryPercentage: telemetryOverrideActive
        ? Math.round(Number(telemetryData.percentage)) : 0
    readonly property real telemetryTimeToEmptySeconds: telemetryOverrideActive
        ? validSeconds(telemetryData.time_to_empty_seconds) : 0
    readonly property real telemetryTimeToFullSeconds: telemetryOverrideActive
        ? validSeconds(telemetryData.time_to_full_seconds) : 0
    readonly property real telemetryEnergyWh: telemetryOverrideActive
        ? validNonNegative(telemetryData.energy_wh) : 0
    readonly property real telemetryEnergyCapacityWh: telemetryOverrideActive
        ? validNonNegative(telemetryData.energy_capacity_wh) : 0
    readonly property real telemetryChangeRateWatts: telemetryOverrideActive
        ? validNonNegative(telemetryData.change_rate_watts) : 0
    readonly property int percentage: available
        ? (telemetryOverrideActive ? telemetryPercentage
            : Math.max(0, Math.min(100, Math.round(Number(device.percentage) * 100)))) : 0
    readonly property bool onBattery: available && UPower.onBattery
    readonly property bool pluggedIn: available && !UPower.onBattery
    readonly property int state: available ? device.state : UPowerDeviceState.Unknown
    readonly property real timeToEmptySeconds: available
        ? (telemetryOverrideActive ? telemetryTimeToEmptySeconds : validSeconds(device.timeToEmpty)) : 0
    readonly property real timeToFullSeconds: available
        ? (telemetryOverrideActive ? telemetryTimeToFullSeconds : validSeconds(device.timeToFull)) : 0
    readonly property real energyWh: available
        ? (telemetryOverrideActive ? telemetryEnergyWh : validNonNegative(device.energy)) : 0
    readonly property real energyCapacityWh: available
        ? (telemetryOverrideActive ? telemetryEnergyCapacityWh
            : validNonNegative(device.energyCapacity)) : 0
    readonly property real changeRateWatts: available
        ? (telemetryOverrideActive ? telemetryChangeRateWatts : validNumber(device.changeRate)) : 0
    readonly property bool healthSupported: available && Boolean(device.healthSupported)
    readonly property int healthPercentage: healthSupported
        ? Math.max(0, Math.min(100, Math.round(validNonNegative(device.healthPercentage)))) : 0
    readonly property bool charging: available && (state === UPowerDeviceState.Charging
        || (pluggedIn && timeToFullSeconds > 0 && percentage < 100))
    readonly property bool pendingCharge: available && state === UPowerDeviceState.PendingCharge
    readonly property bool discharging: available && (UPower.onBattery
        || state === UPowerDeviceState.Discharging
        || state === UPowerDeviceState.PendingDischarge)
    readonly property bool fullyCharged: available && (state === UPowerDeviceState.FullyCharged
        || (pluggedIn && percentage >= 100))
    readonly property int defaultHealthTargetPercent: 80
    readonly property real defaultHealthTargetEtaSeconds: estimateChargeSeconds(defaultHealthTargetPercent)
    readonly property string barTooltip: buildBarTooltip()

    function validNumber(value) {
        const number = Number(value);
        return Number.isFinite(number) ? number : 0;
    }

    function validNonNegative(value) {
        return Math.max(0, validNumber(value));
    }

    function validSeconds(value) {
        return Math.max(0, validNumber(value));
    }

    function emptyTelemetry() {
        return ({ override: false });
    }

    function sanitizedTelemetry(data) {
        if (!data || data.override !== true)
            return emptyTelemetry();

        const percentageValue = Number(data.percentage);
        const energyValue = Number(data.energy_wh);
        const capacityValue = Number(data.energy_capacity_wh);
        const rateValue = Number(data.change_rate_watts);
        const emptySecondsValue = Number(data.time_to_empty_seconds);
        const fullSecondsValue = Number(data.time_to_full_seconds);
        const excluded = Array.isArray(data.excluded) ? data.excluded : [];
        const included = Array.isArray(data.included) ? data.included : [];

        if (!Number.isFinite(percentageValue) || percentageValue < 0 || percentageValue > 100
            || !Number.isFinite(energyValue) || energyValue < 0
            || !Number.isFinite(capacityValue) || capacityValue <= 0 || energyValue > capacityValue
            || !Number.isFinite(rateValue) || rateValue < 0
            || !Number.isFinite(emptySecondsValue) || emptySecondsValue < 0
            || !Number.isFinite(fullSecondsValue) || fullSecondsValue < 0
            || excluded.length === 0 || included.length === 0)
            return emptyTelemetry();

        return ({
            override: true,
            percentage: Math.round(percentageValue),
            energy_wh: energyValue,
            energy_capacity_wh: capacityValue,
            change_rate_watts: rateValue,
            time_to_empty_seconds: emptySecondsValue,
            time_to_full_seconds: fullSecondsValue
        });
    }

    function refreshTelemetry() {
        if (!available || batteryTelemetryReader.running)
            return;
        batteryTelemetryReader.exec([
            "/usr/bin/bash", batteryTelemetryScript, "--status-json"
        ]);
    }

    function formatDuration(seconds) {
        const totalMinutes = Math.max(1, Math.round(validSeconds(seconds) / 60));
        const days = Math.floor(totalMinutes / 1440);
        const hours = Math.floor((totalMinutes % 1440) / 60);
        const minutes = totalMinutes % 60;

        if (days > 0)
            return days + "d " + hours + "h";
        if (hours > 0)
            return hours + "h" + (minutes > 0 ? " " + minutes + "m" : "");
        return totalMinutes + "m";
    }

    function estimateChargeSeconds(targetPercent) {
        if (!available || !charging)
            return 0;

        const target = Math.max(0, Math.min(100, Number(targetPercent)));
        if (!Number.isFinite(target) || target <= percentage)
            return 0;
        if (energyCapacityWh <= 0 || changeRateWatts <= 0)
            return 0;

        const targetEnergyWh = energyCapacityWh * target / 100;
        const remainingWh = targetEnergyWh - energyWh;
        if (remainingWh <= 0)
            return 0;

        const seconds = remainingWh / changeRateWatts * 3600;
        return Number.isFinite(seconds) && seconds > 0 ? seconds : 0;
    }

    function buildBarTooltip() {
        if (!available)
            return "Battery unavailable";

        const lines = ["Battery: " + percentage + "%"];

        if (discharging) {
            if (timeToEmptySeconds > 0)
                lines.push(formatDuration(timeToEmptySeconds) + " remaining");
            else
                lines.push("Estimating remaining time…");
            return lines.join("\n");
        }

        if (charging) {
            lines.push("Charging");

            if (percentage < defaultHealthTargetPercent) {
                if (defaultHealthTargetEtaSeconds > 0)
                    lines.push("~" + formatDuration(defaultHealthTargetEtaSeconds)
                        + " to " + defaultHealthTargetPercent + "%");
                else
                    lines.push("Calculating time to " + defaultHealthTargetPercent + "%…");
            }

            if (percentage < 100) {
                if (timeToFullSeconds > 0)
                    lines.push(formatDuration(timeToFullSeconds) + " to 100%");
                else
                    lines.push("Calculating time to 100%…");
            }

            return lines.join("\n");
        }

        if (fullyCharged)
            lines.push("Fully charged");
        else if (pendingCharge)
            lines.push("Plugged in · waiting to charge");
        else if (pluggedIn)
            lines.push("Plugged in");

        return lines.join("\n");
    }

    onAvailableChanged: {
        telemetryData = emptyTelemetry();
        if (available)
            refreshTelemetry();
    }

    Component.onCompleted: refreshTelemetry()

    Process {
        id: batteryTelemetryReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "{}");
                    root.telemetryData = root.sanitizedTelemetry(parsed);
                } catch (error) {
                    root.telemetryData = root.emptyTelemetry();
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.telemetryData = root.emptyTelemetry();
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.available
        onTriggered: root.refreshTelemetry()
    }
}
