#!/bin/bash
# privileges-extend.sh — Re-elevates admin privileges and dismisses Privileges notifications

PRIVILEGES_CLI="/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI"
DISMISS_APP="$HOME/Applications/DismissPrivilegesNotifications.app"
LOG_FILE="$HOME/Library/Logs/privileges-extender.log"
DISMISS_LOG="$HOME/Library/Logs/privileges-extender-dismiss.log"

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

# Dismiss Privileges notifications using the helper .app
# The .app runs as its own process with Accessibility permission,
# unlike raw osascript which is blocked when run from launchd.
if [ -d "$DISMISS_APP" ]; then
    open -W "$DISMISS_APP"
    if [ -f "$DISMISS_LOG" ]; then
        DISMISS_RESULT=$(cat "$DISMISS_LOG")
        log "Notification dismissal result: $DISMISS_RESULT"
    else
        log "WARNING: Dismiss log not created"
    fi
else
    log "ERROR: Helper app not found at $DISMISS_APP"
    log "Run install.sh to set it up"
fi
