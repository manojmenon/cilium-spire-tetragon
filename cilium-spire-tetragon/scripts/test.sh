#!/bin/bash
# -----------------------------------------------
# Shell Script Documentation
#
# This script helps in managing clusters and running tests 
# for Tetragon and Cilium using specific configurations.
#
# USAGE:
#   ./main_shell.sh --cluster-config-file <CONFIG_FILE_PATH> <OPTIONS>
#
# OPTIONS:
#   --cluster --delete
#       Deletes the specified cluster configuration.
#
#   --tetragon --install
#       Installs Tetragon using the specified configuration file.
#       [Currently commented out in the script.]
#
#   --tetragon --test
#       Runs tests for Tetragon using the configuration file.
#
#   --cluster --install
#       Installs the cluster configuration (Cilium-specific example).
#       [Currently commented out in the script.]
#
#   --cilium --test
#       Runs tests for Cilium using the configuration file.
#
# HELPER COMMANDS:
#   kind get clusters
#       Lists all clusters currently managed by Kind.
#
#   kubectl config get-contexts
#       Displays all Kubernetes contexts.
#
# NOTES:
#   - Ensure proper permissions and configurations for the commands.
#   - Modify `cluster-config.yaml` files as necessary.
#   - Uncomment commands in the script to enable optional features.
# -----------------------------------------------
echo "================================================================================================"
echo ""
echo "If first time, please be PATIENT it can take upto 5 minutes - lots being done"
echo "Meanwhile, please open two other windows for monitoring the progress "
echo "Window 1, run watch kubectl get pods --all-namespaces"
echo "Windoe 2, keep it for running the tetragon observability or hubble observe commands "
echo "You must have installed kind, brew, docker, cilium cli" 
echo "If clilium cli is not present, installation will take place and you need to provide sudo passwrod"
echo "For testing CLI the browsed for hubble will open. Choose default to see the user traffic"
echo ""
echo "================================================================================================="

echo " "
echo -n "Press <CR> to proceed or Ctrl-C to exit"
read x

# Example commands:
#./main_shell.sh --cluster-config-file ../tetragon/config/cluster-config.yaml --cluster --delete
#./main_shell.sh --cluster-config-file ../tetragon/config/cluster-config.yaml --tetragon --install
#./main_shell.sh --cluster-config-file ../tetragon/config/cluster-config.yaml --tetragon --test

./main_shell.sh --cluster-config-file ../cilium/config/cluster-config.yaml --cluster --delete
#./main_shell.sh --cluster-config-file ../cilium/config/cluster-config.yaml --cluster --install
./main_shell.sh --cluster-config-file ../cilium/config/cluster-config.yaml --tetragon --test


### End of Program
