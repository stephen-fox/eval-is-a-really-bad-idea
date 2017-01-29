#!/bin/bash

# really-bad-idea.sh - Demonstates why using 'eval' in Bash is a bad idea.
#     This script presents a basic "API" that is accessible over a network. The
#     API is supposed to "manage" a text file (G_IMPORTANT_FILE) using rules
#     defined in the function 'execute_api_call'. This script uses the Bash
#     'eval' builtin to check if a valid API request has been made. While the
#     script makes some basic attempts at sanitizing user data, anyone can
#     ultimately exploit this script to run their own code on the host machine.

# Globals.
readonly G_LISTENER_LOG='/tmp/listener.log'
readonly G_API_KEY=/api/$(date | md5sum | cut -f1 -d' ')
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
        echo "[INFO] Make API calls to '<server-address>:${port}${G_API_KEY}'"
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

            # The following logic attempts to check if the line is a HTTP 'GET'
            # request. Unfortunately, the usage of 'eval' here means that code
            # can be injected into the 'line' variable by an external user.
            eval echo "${line}" | grep -w "GET ${G_API_KEY}" \
                && execute_api_call "${line}"
        done < "${G_LISTENER_LOG}"
    done

    [ ${G_USER_REQUESTED_SHUTDOWN} -ne 0 ] \
        && echo '[ERROR] The listener has exited unexpectedly'
}

# execute_api_call <CALL>
# Attempts to execute an API call. The call is validated against a rule set.
execute_api_call() {
    echo "Got data ${1}"
    local call=$(cut -f2 -d' ' <<< "${1}")
    echo "Got call ${call}"
    local command=${call##*${G_API_KEY}/}

    echo "Received API call: '${call}'"

    case "${command}" in
        'update' )
            echo '[INFO] Updating file...'
            echo "Updated on $(date)" >> "${G_IMPORTANT_FILE}"
            ;;
        'delete' )
            echo '[INFO] Removing file...'
            [ -f "${G_IMPORTANT_FILE}" ] && rm "${G_IMPORTANT_FILE}"
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
