pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * After the in-app updater relaunches the shell, raise a one-shot toast naming
 * what landed, so the apply ends in a confirmation instead of a silent restart.
 * The updater drops a marker file (`$XDG_STATE_HOME/fukushima/updated`) just
 * before it restarts; the short delay lets the notification server own the bus
 * before we post, and the marker is removed as it is read so the toast fires
 * only once.
 *
 * A lazy singleton — `void UpdateToast.armed` from the shell's
 * Component.onCompleted starts the timer.
 */
Singleton {
    id: root

    readonly property bool armed: true

    Timer {
        interval: 2500
        running: true
        onTriggered: proc.running = true
    }

    Process {
        id: proc
        command: ["sh", "-c",
            "m=\"${XDG_STATE_HOME:-$HOME/.local/state}/fukushima/updated\"; [ -f \"$m\" ] || exit 0; "
            + "b=$(cat \"$m\"); rm -f \"$m\"; "
            + "gdbus call --session --dest org.freedesktop.Notifications "
            + "--object-path /org/freedesktop/Notifications "
            + "--method org.freedesktop.Notifications.Notify "
            + "Pill 0 '' 'Pill updated' \"$b\" '[]' '{}' 5000 >/dev/null 2>&1"]
    }
}
