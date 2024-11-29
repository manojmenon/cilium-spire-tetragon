#!/bin/bash

# ------------------------------------------------------------------------
# Utility Functions for Kubernetes and Logging
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# Wait until all Kubernetes pods are in the "Running" state
# ------------------------------------------------------------------------
fn_wait_till_all_running() {
    
    while true; do
        COUNT=$(kubectl get pods --all-namespaces | grep -v NAMESPACE | grep -v Running | wc -l)
        if [ "$COUNT" -ne 0 ]; then
            sleep 1
        else
            break
        fi
    done
}

# ------------------------------------------------------------------------
# Exit function (reserved for custom exit handling if needed in future)
# ------------------------------------------------------------------------
fn_exit() {
    return 0
}

# ------------------------------------------------------------------------
# Logging utility: Logs a message with a timestamp, program, and log level
# ------------------------------------------------------------------------
fn_log() {
    local prog="$1"
    local level="$2"
    local mesg="$3"

    echo "$prog: $(date '+%Y-%m-%d %H:%M:%S') | $level | $mesg"
}

# ------------------------------------------------------------------------
# Check command status and log error if the last command failed
# ------------------------------------------------------------------------
fn_check_command() {
    local command="$1"
    local error_msg="$2"

    # Check the exit status of the previous command
    if [ $? -ne 0 ]; then
        fn_log "$command" "ERROR" "$error_msg"
        exit 1
    fi
}

# ------------------------------------------------------------------------
# Main script to demonstrate function usage (if needed for testing)
# ------------------------------------------------------------------------
main() {
    # Example usage of fn_log
    fn_log "ExampleScript" "INFO" "Script started."

    # Example command: Check if 'kubectl' is installed
    which kubectl >/dev/null 2>&1
    fn_check_command "kubectl" "kubectl command not found. Please install Kubernetes CLI."

    # Example usage of fn_wait_till_all_running
    fn_log "ExampleScript" "INFO" "Waiting for all pods to be in the 'Running' state..."
    fn_wait_till_all_running
    fn_log "ExampleScript" "INFO" "All pods are running."

    # Finish script
    fn_log "ExampleScript" "INFO" "Script completed successfully."
}

# Run the main function if the script is executed directly
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main
fi