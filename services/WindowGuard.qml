pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../config"

/**
 * Keeps floating windows reachable for Hyprshell's ALT+TAB switcher.
 *
 * Hyprshell reads window positions as 16-bit numbers. A floating window with a
 * position far off screen (seen after a monitor change: x = -41703) makes the
 * whole `hyprctl clients` list unreadable to it, and ALT+TAB then does nothing.
 * scripts/window-guard.sh moves such a window back to the centre of its monitor.
 *
 * The script runs when a window opens or moves, when the floating mode
 * changes and when a monitor is added or removed. The runs are throttled to one
 * each second. A slow timer is the fallback for a window that moves without an
 * event.
 *
 * A lazy singleton: `void WindowGuard.armed` from the shell's
 * Component.onCompleted makes it start.
 */
Singleton {
    id: root

    readonly property bool armed: true

    readonly property var watchedEvents: ({
        openwindow: true, movewindow: true, movewindowv2: true,
        changefloatingmode: true,
        monitoradded: true, monitoraddedv2: true, monitorremoved: true
    })

    function check() {
        if (!guardProc.running)
            guardProc.running = true;
    }

    // Throttle, not debounce: a steady stream of events must not delay the run.
    Timer {
        id: throttle
        interval: 1000
        onTriggered: root.check()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.watchedEvents[event.name] && !throttle.running)
                throttle.start();
        }
    }

    Component.onCompleted: root.check()

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.check()
    }

    Process {
        id: guardProc
        command: ["bash", Config.hyprPath("scripts", "window-guard.sh")]
        stdout: SplitParser {
            // One line for each window that the script handled.
            onRead: (line) => {
                if (line.length > 0)
                    console.warn("WindowGuard:", line.replace(/\t/g, " "));
            }
        }
    }
}
