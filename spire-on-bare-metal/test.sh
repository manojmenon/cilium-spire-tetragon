#!/bin/bash

# -----------------------------------------------
# Shell Script Documentation
#
# This script automates the installation and configuration of 
# SPIRE (the SPIFFE Runtime Environment) for generating and 
# managing SPIFFE IDs.
#
# FEATURES:
# - Installs SPIRE from source code if not already installed.
# - Manages SPIRE server and agent processes.
# - Generates certificates and registration entries.
#
# FUNCTIONS:
#   fn_kill_running_server_agent:
#       Stops any running SPIRE server or agent processes.
#
#   fn_set_log_dir:
#       Sets up directories for logs and certificates.
#
#   fn_install_spire:
#       Installs SPIRE from source code.
#
# VARIABLES:
#   SPIFFE_ID   : SPIFFE identifier for the workload (default: spiffe://example.org/myservice).
#   PARENT_ID   : SPIFFE identifier for the agent (default: spiffe://example.org/myagent).
#   APP_NAME    : Name of the application (default: MyApplication).
#   CERT_DIR    : Directory to store certificates (auto-created).
#   LOG_DIR     : Directory to store logs (auto-created).
#
# USAGE:
#   - Run the script directly to install SPIRE and manage SPIFFE ID setup.
#   - Customize variables (SPIFFE_ID, PARENT_ID, APP_NAME) as needed.
#
# NOTES:
#   - Requires Golang installed and configured.
#   - Ensure proper permissions for process management.
#   - Adjust the `spire` directory path if cloned elsewhere.
#
# OUTPUT:
#   - Log files in the designated LOG_DIR.
#   - Certificates in the CERT_DIR.
#   - Registered SPIFFE IDs on the SPIRE server.
#
# -----------------------------------------------

fn_kill_running_server_agent() {
    SPIRE_PID=$(ps -aef | grep spire-server | grep server.conf | awk '{ print $2 }')

    if [ ! -z "$SPIRE_PID" ] && [ "$SPIRE_PID" -gt 0 ]; then
        kill -9 "${SPIRE_PID}"
    fi

    SPIRE_AGENT_PID=$(ps -aef | grep spire-agent | grep agent.conf | awk '{ print $2 }')

    if [ ! -z "$SPIRE_AGENT_PID" ] && [ "$SPIRE_AGENT_PID" -gt 0 ]; then
        kill -9 "${SPIRE_AGENT_PID}"
    fi
}

fn_set_log_dir() {
    OUT_DIR=$(pwd)/tmp/run.${PID}
    LOG_DIR=${OUT_DIR}/logs
    CERT_DIR=${OUT_DIR}/svid
    mkdir -p "${OUT_DIR}" "${CERT_DIR}" "${LOG_DIR}"
}

fn_install_spire() {
    if [ -f spire/bin/spire-server ] && [ -f spire/bin/spire-agent ]; then
        return 0
    fi

    if ! go version > /dev/null; then
        echo "Please install Golang and then try again. Command 'go' failed."
        exit 1
    fi

    if [ ! -d spire ]; then
        git clone --single-branch --branch v1.10.4 https://github.com/spiffe/spire.git
        cd spire || exit
    fi

    go build ./cmd/spire-server
    go build ./cmd/spire-agent

    # Create a bin directory and move executables
    mkdir bin
    mv spire-server spire-agent bin
}

# Variables
PID=$$
SPIFFE_ID=spiffe://example.org/myservice
PARENT_ID=spiffe://example.org/myagent
APP_NAME=MyApplication
CERT_DIR=""
LOG_DIR=""

echo " "
echo "It can take a few seconds to check spire-server and spire-agent - some issues on agent to be sorted out !!"
echo " "
# Setup directories and environment
fn_set_log_dir

# Install SPIRE
fn_install_spire

# File paths
SERVER_LOG_FILE=${LOG_DIR}/spire-server.log
AGENT_LOG_FILE=${LOG_DIR}/spire-agent.log

# Kill running SPIRE processes
fn_kill_running_server_agent

# Navigate to SPIRE directory
cd spire || exit

# Start SPIRE Server
bin/spire-server run -config conf/server/server.conf > "${SERVER_LOG_FILE}" 2>&1 &
sleep 5

# Check server health
bin/spire-server healthcheck

# Generate a join token for the agent
TOKEN_STRING=$(bin/spire-server token generate -spiffeID "${SPIFFE_ID}" | awk '{ print $2 }')

# Start SPIRE Agent
fn_set_log_dir
bin/spire-agent run -config conf/agent/agent.conf -joinToken "${TOKEN_STRING}" > "${AGENT_LOG_FILE}" 2>&1 &
sleep 3

# Check agent health
bin/spire-agent healthcheck

# Register workload
bin/spire-server entry create -parentID "${PARENT_ID}" \
    -spiffeID "${SPIFFE_ID}" \
    -selector unix:uid:$(id -u) \
    -selector app:name:"${APP_NAME}" \
    -selector app:pid:"${PID}"

# Fetch x509-SVID
bin/spire-agent api fetch x509 -write "${CERT_DIR}"

# View certificate with OpenSSL
openssl x509 -in "${CERT_DIR}/svid.0.pem" -text -noout

# Stop SPIRE processes
fn_kill_running_server_agent