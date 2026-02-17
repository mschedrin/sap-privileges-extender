set dismissed to 0
set found to 0
tell application "System Events"
    tell application process "NotificationCenter"
        try
            set _scrollAreas to scroll areas of group 1 of group 1 of window "Notification Center"
            repeat with _scrollArea in _scrollAreas
                set _groups to groups of _scrollArea
                repeat with _group in _groups
                    set _heading to ""
                    try
                        set _heading to value of static text 1 of _group
                    end try
                    if _heading contains "Privileges" then
                        set found to found + 1
                        try
                            set _actions to actions of _group
                            repeat with _action in _actions
                                if description of _action contains "Close" then
                                    perform _action
                                    set dismissed to dismissed + 1
                                end if
                            end repeat
                        end try
                    end if
                end repeat
            end repeat
        end try
    end tell
end tell
return "found=" & found & " dismissed=" & dismissed
