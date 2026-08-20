pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool available: device.ready && device.isLaptopBattery
    readonly property int percentage: available
        ? Math.max(0, Math.min(100, Math.round(Number(device.percentage) * 100))) : 0
    readonly property bool onBattery: available && UPower.onBattery
    readonly property bool pluggedIn: available && !UPower.onBattery
    readonly property int state: available ? device.state : UPowerDeviceState.Unknown
    readonly property real timeToEmptySeconds: available ? validSeconds(device.timeToEmpty) : 0
    readonly property real timeToFullSeconds: available ? validSeconds(device.timeToFull) : 0
    readonly property real energyWh: available ? validNonNegative(device.energy) : 0
    readonly property real energyCapacityWh: available ? validNonNegative(device.energyCapacity) : 0
    readonly property real changeRateWatts: available ? validNumber(device.changeRate) : 0
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
}
