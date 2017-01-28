#!/bin/bash

# really-bad-idea.sh - Demonstates why using 'eval' in Bash is a bad idea.
#     This script presents a basic "API" that is accessible over a network. The
#     API is supposed to "manage" a text file (G_IMPORTANT_FILE) using rules
#     defined in the function 'execute_api_call'. This script uses the Bash
#     'eval' builtin to save a few lines of code. While the script makes some
#     basic attempts at sanitizing user data, anyone can ultimately exploit
#     this script to run their own code on the host machine.

# Globals.
readonly G_LISTENER_LOG='/tmp/listener.log'
readonly G_API_KEY='/api'
readonly G_IMPORTANT_FILE='/tmp/file.txt'
G_LISTENER_PID=''
G_USER_REQUESTED_SHUTDOWN=1

# main
# Runs the script.
main() {
    launch_listener
    parse_incoming_data
}

# launch_listener <PORT>
# Launches netcat in the background. If a PORT is not specified, then 8080
# is used.
launch_listener() {
    local port=${1:-8080}

    if echo '' > "${G_LISTENER_LOG}"
    then
        nc -k -l ${port} >> "${G_LISTENER_LOG}" &
        G_LISTENER_PID=$!
        echo "[INFO] netcat now listening on port ${port} as" \
            "PID ${G_LISTENER_PID}"
    else
        echo '[ERROR] Failed to create listener log file'
        shutdown
    fi
}

# parse_incoming_data
# Parses incoming data sent to the listener. If G_API_KEY is found in the data,
# then it attempts to parse the data using the execute_api_call function.
parse_incoming_data() {
    local parsedCount=0
    local lastParsedLine=0
    local in=''

    # While the listner is running, try to parse input.
    while [ -d /proc/${G_LISTENER_PID} ]; do
        sleep 1
        parsedLineCount=0

        # Parse the data from the listener log file.
        while read -r line; do
            parsedLineCount=$((parsedLineCount + 1))
            [ ${lastParsedLine} -ne 0 ] \
                && [ ${parsedLineCount} -le ${lastParsedLine} ] && continue
            lastParsedLine=${parsedLineCount}

            # The following logic attempts to remove unsantized input by using
            # 'grep' and 'cut'. Unfortunately, the usage of 'eval' here means
            # that code can be injected into the 'line' variable by an external
            # user. The code is then re-interpreted by Bash. While using double
            # quotes around the value of the 'in' variable would catch most
            # cases - I think it is just safer to split this code out into a few
            # lines and not use 'eval' at all.
            # My point is, while this is a neat hack to save a few lines, it is
            # not worth the trade off.
            if eval in=$(echo "${line}" | grep ${G_API_KEY} | cut -f2 -d' ') \
                && [ -n "${in}" ]
            then
                execute_api_call "${in}"
            fi
        done < "${G_LISTENER_LOG}"

    done

    [ ${G_USER_REQUESTED_SHUTDOWN} -ne 0 ] \
        && echo '[ERROR] The listener has exited unexpectedly'
}

# execute_api_call <CALL>
# Attempts to execute an API call. The call is validated against a rule set.
execute_api_call() {
    local call=${1}
    local command=${call##*${G_API_KEY}/}

    echo "Received API call: '${call}'"

    case "${command}" in
        'update' )
            echo '[INFO] Updating file...'
            echo "Updated on $(date)" >> ${G_IMPORTANT_FILE}
            ;;
        'delete' )
            echo '[INFO] Removing file...'
            [ -f "${G_IMPORTANT_FILE}" ] && rm /tmp/file.txt
            ;;
        * )
            echo "[WARN] Unknown command '${command}' for API call: '${call}'"
            ;;
    esac
}

# shutdown
# Stops the listener and exits the script.
shutdown() {
    local exitValue=1

    if [ ${G_USER_REQUESTED_SHUTDOWN} -eq 0 ]
    then
        echo '[INFO] Shutting down...'
        if kill ${G_LISTENER_PID}
        then
            exitValue=0
        else
            echo '[WARN] Failed to shutdown listener'
        fi
    else
        echo '[ERROR] Unexpected shutdown'
    fi

    return ${exitValue}
}

# control_c
# Executes logic to handle a Control + C press by the user.
control_c() {
    G_USER_REQUESTED_SHUTDOWN=0
    echo ''
    shutdown
}

# Bind control_c logic to exit events.
trap control_c SIGINT
trap control_c SIGTERM

# Run the script.
main

exit
