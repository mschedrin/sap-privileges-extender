#!/bin/bash
# privileges-extend.sh — Re-elevates admin privileges and dismisses Privileges notifications

PRIVILEGES_CLI="/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI"
LOG_FILE="$HOME/Library/Logs/privileges-extender.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Re-elevate privileges
if [ -x "$PRIVILEGES_CLI" ]; then
    STATUS=$("$PRIVILEGES_CLI" --status 2>&1)
    log "Current status: $STATUS"

    "$PRIVILEGES_CLI" --add --reason "auto-extend" >> "$LOG_FILE" 2>&1
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
        log "Privileges re-elevated successfully"
    else
        log "Failed to re-elevate privileges (exit code: $EXIT_CODE)"
    fi
else
    log "ERROR: PrivilegesCLI not found at $PRIVILEGES_CLI"
    exit 1
fi

# Wait for any notification banner to appear
sleep 3

# Dismiss only Privileges notification banners via AppleScript
osascript -e '
tell application "System Events"
    tell application process "NotificationCenter"
        try
            set _groups to groups of scroll area 1 of group 1 of group 1 of window "Notification Center"
            repeat with _group in _groups
                set _heading to ""
                try
                    set _heading to value of static text 1 of _group
                end try
                if _heading contains "Privileges" then
                    try
                        set _actions to actions of _group
                        repeat with _action in _actions
                            if description of _action contains "Close" then
                                perform _action
                            end if
                        end repeat
                    end try
                end if
            end repeat
        end try
    end tell
end tell
' >> "$LOG_FILE" 2>&1

log "Notification dismissal pass complete"
