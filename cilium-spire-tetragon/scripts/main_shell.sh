#!/bin/bash

# helm install cilium cilium/cilium --version 1.16.4 --namespace  kube-system \
# cl--set authentication.mutual.spire.install.enabled=true
source ./lib-common.sh


fn_get_cluster_config()
{

    #DEFAULT_CONFIG_FILE="cluster-config.yaml"

    # Check if a parameter is provided, else use the default
    #CLUSTER_CONFIG_FILE="${1:-$DEFAULT_CONFIG_FILE}"

    # Check if the config file exists
    if [ ! -f "$CLUSTER_CONFIG_FILE" ]; then
        fn_log "$PROGRAM" "ERROR" "Configuration file ${CLUSTER_CONFIG_FILE} not found. Exiting script."
        exit 1
    fi
  
    CLUSTER_NAME=`grep "^name" ${CLUSTER_CONFIG_FILE} | awk  '{ print $2}'` 

    # Check if CLUSTER_NAME is empty
    if [ -z "$CLUSTER_NAME" ]; then
        echo "Error: The name in ${CLUSTER_CONFIG_FILE} is empty. Exiting the program."
        exit 1
    fi


}

fn_check_cluster_exists()
{
 
    fn_get_cluster_config
 
    kubectl config use-context kind-${CLUSTER_NAME}

    if [ $? -ne 0 ]
    then
        return 2
    fi
    
    kubectl cluster-info > /dev/null 2>&1

    #exit 0 
    return $?
}

fn_delete_cluster()
{

    fn_check_cluster_exists

    if [ $? -ne 0 ]
    then    
        echo "${CLUSTER_NAME} does not exists"
        return 0
    fi
   
    kubectl -n ${NAME_SPACE}   get nodes -o wide

    # Ask for confirmation before deleting the existing cluster
    echo " "
    echo "Are you sure you want to DELETE the Kubernetes cluster ${CLUSTER_NAME}? (y/n)."
    echo -n "Enter y to continue or any other value to exit: "
    read -r CONFIRMATION

    if [[ "$CONFIRMATION" != "y" && "$CONFIRMATION" != "Y" ]]; then
        fn_log "$PROGRAM" "INFO" "Cluster deletion was not accepted"
        return 1
    fi
      #1. Delete the existing kind cluster
    kind delete cluster --name ${CLUSTER_NAME}
    fn_check_command "kind delete cluster" "Failed to delete the Kubernetes cluster ${CLUSTER_NAME}."

    return 0
}

fn_delete_dashboard()
{
    rm -f ./dashboard.log
   kubectl get namespace kubernetes-dashboard && kubectl delete -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml > /dev/null 2>&1
}

fn_install_dashboard()
{

 
    fn_delete_dashboard
    
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
    kubectl rollout status deployment -n kubernetes-dashboard
    kubectl rollout status deployment -n dashboard-metrics-scraper

    kubectl apply -n kubernetes-dashboard -f ../cluster/yamls/dashboard.yaml 
    
    fn_wait_till_all_running
    kubectl get pods -n kubernetes-dashboard
    ADMIN_TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)

    DASHBOARD_PORT=1223
    kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard --address 0.0.0.0 ${DASHBOARD_PORT}:443 > ../cluster/logs/dashboard.log 2>&1 &

    echo "USE Tokey Key below for Dashboard https://localhost:${DASHBOARD_PORT}"

    echo ""
    echo "  ${ADMIN_TOKEN} "
    echo " "
    




}


fn_delete_grafana_prometheus()
{
    rm -f ./grafana.log
    kubectl delete -f ../grafana/yamls/monitoring-example.yaml > /dev/null 2>&1
}

fn_install_grafana_prometheus()
{



    fn_delete_grafana_prometheus
    
    kubectl apply -f ../grafana/yamls/monitoring-example.yaml 
    fn_wait_till_all_running
    
    sleep 5
    
    kubectl -n cilium-monitoring port-forward service/grafana --address 0.0.0.0 --address :: ${GRAFANA_PORT}:3000 > ../grafana/logs/grafana.log 2>&1 &
    kubectl -n cilium-monitoring port-forward service/prometheus --address 0.0.0.0 --address :: ${PROMETHEUS_PORT}:9090 > ../grafana/logs/prometheus.log 2>&1 &
   

}

fn_install_cluster()
{
 
     fn_check_cluster_exists

    if [ $? -eq 0 ]
    then    
        echo "${CLUSTER_NAME} exists"
        return 0
    fi

    RETURN_VALUE=$?

    if [ ${RETURN_VALUE} -eq 1 ]
    then
        return 1
    fi


    kind create cluster --config ${CLUSTER_CONFIG_FILE}
    fn_check_command "kind create cluster" "Failed to create the Kubernetes cluster ${CLUSTER_NAME} using 'kind' with config  ${CLUSTER_CONFIG_FILE}."



    # 3. Retrieve and display node information
    kubectl -n ${NAME_SPACE}   get nodes -o wide
    fn_check_command "kubectl -n ${NAME_SPACE}   get nodes" "Failed to retrieve nodes information."

    # 4. Describe the nodes and check for InternalIP
    kubectl -n ${NAME_SPACE}   describe nodes | grep -E "InternalIP"
    fn_check_command "kubectl -n ${NAME_SPACE}   describe nodes | grep -E 'InternalIP'" "Failed to retrieve 'InternalIP' from node descriptions."

    # 5. Describe the nodes and check for PodCIDRs
    kubectl -n ${NAME_SPACE}   describe nodes | grep "PodCIDRs"
    fn_check_command "kubectl -n ${NAME_SPACE}   describe nodes | grep 'PodCIDRs'" "Failed to retrieve 'PodCIDRs' from node descriptions."

    # Log the successful completion of the process
    fn_log "$PROGRAM" "$INFO" "Cluster setup process completed successfully."
    kubectl config use-context kind-${CLUSTER_NAME}

    
return 0
            
    
}


fn_check_cilium()
{
    fn_get_cluster_config

    CILIUM_RUNNING=`helm list -n kube-system | grep cilium | grep -v grep | awk '{ print $1}'`

    if [ -z "${CILIUM_RUNNING}" ]
    then    
        echo "Cilium is not installed."
        return 0
    fi
    return 1

}

fn_delete_cilium()
{

    fn_get_cluster_config

    fn_check_cilium

    if [ $? -eq 0 ]
    then
        #echo "Cilium is not installed."
        return 0
    fi

   echo "Cilium  installed on cluster ${CLUSTER_NAME}. "

    # Ask for confirmation before deleting the existing cluster
    echo " "
    echo "Do you want to DELETE Cilium on this cluster ${CLUSTER_NAME}? (y/n)."
    echo -n "Enter y to continue or any other value to exit: "
    read -r CONFIRMATION

    if [[ "$CONFIRMATION" != "y" && "$CONFIRMATION" != "Y" ]]; then
        fn_log "$PROGRAM" "INFO" "Cilium deletion was not accepted"
        return 1
    fi
    
    #Uninstall cilium
    cilium uninstall cilium
    fn_check_command "cilium uninstall cilium" "Failed to delete Cilium the Kubernetes cluster ${CLUSTER_NAME}."

    (cd ../cilium/yamls ; kubectl -n ${NAME_SPACE}    delete -f .)
    
     
    #fn_wait_till_all_running

    return 0
}


fn_install_cilium_cli()
{

    cilium version
    if [ $? -eq 0 ]
    then
        return 0
    fi
    
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    CLI_ARCH=amd64
    if [ "$(uname -m)" = "arm64" ]; then CLI_ARCH=arm64; fi
    curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-darwin-${CLI_ARCH}.tar.gz{,.sha256sum}
    shasum -a 256 -c cilium-darwin-${CLI_ARCH}.tar.gz.sha256sum
    echo " "
    echo "Cilium CLI is being installed, sudo permissions needed to move to /u"
    echo " "
    sudo tar xzvfC cilium-darwin-${CLI_ARCH}.tar.gz /usr/local/bin
    rm cilium-darwin-${CLI_ARCH}.tar.gz{,.sha256sum}
}

fn_install_cilium()
{


            fn_check_cluster_exists

            if [ $? -ne 0 ]
            then
                fn_install_cluster
            fi

            fn_check_cilium

            if [ $? -eq 1 ]
            then
                echo "Cilium is already installed."
                return 0
            fi

          fn_install_cilium_cli

            cilium status > /dev/null 2>&1

            if [ $? -eq 0 ]
            then
                echo "Cilium already installed - cannot install again"
                return 0
            fi


echo "Installing cilium.."

helm install cilium cilium/cilium \
    --namespace kube-system \
    --set authentication.mutual.spire.enabled=true \
    --set authentication.mutual.spire.install.enabled=true \
    --set authentication.mutual.spire.install.server.dataStorage.enabled=false \
    --set prometheus.enabled=true \
    --set operator.prometheus.enabled=true \
    --set hubble.enabled=true \
    --set hubble.metrics.enableOpenMetrics=true \
    --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}" \
   
echo "Waiting for all pods to be in Running state.."
#fn_wait_till_all_running

echo "Installing hubble.."

cilium hubble enable --ui
echo "Waiting for all pods to be in Running state.."
#fn_wait_till_all_running

kubectl -n kube-system rollout restart deployment/cilium-operator
kubectl -n kube-system rollout restart ds/cilium

echo "Waiting for all pods to be in Running state.."
fn_install_dashboard

fn_install_grafana_prometheus

fn_wait_till_all_running
cilium hubble port-forward&
fn_apply_cilium_yamls

return 0

# kubectl -n ${NAME_SPACE}   apply -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/kubernetes/servicemesh/mutual-auth-example.yaml
# kubectl -n ${NAME_SPACE}   apply -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/kubernetes/servicemesh/cnp-without-mutual-auth.yaml
}

fn_apply_cilium_yamls()
{

echo "Deleting namespace ${NAME_SPACE}.."
envsubst < ../cilium/yamls/00-namespace.yaml | kubectl delete -f -
envsubst < ../cilium/yamls/00-namespace.yaml | kubectl create -f -
echo "Deleted and recreated namespace ${NAME_SPACE}."
#kubectl delete -f ../cilium/yamls/00-namespace.yaml
#kubectl apply -f ../cilium/yamls/00-namespace.yaml
    
# kubectl -n ${NAME_SPACE}   apply -f ../cilium/yamls

# echo "Installing echoserver.."
# kubectl -n ${NAME_SPACE}   rollout status deployment echoserver

#echo "Waiting for all pods to be in Running state.."
#fn_wait_till_all_running

return 0
}

fn_test_cilium()
{
    

    # IPV6=`kubectl -n ${NAME_SPACE}   get pod pod-worker -o jsonpath={'.status.podIPs[1].ip'}`
    # echo "pod-worker IP=${IPV6}"
    # IPV6_2=`kubectl -n ${NAME_SPACE}   get pod pod-worker2 -o jsonpath={'.status.podIPs[1].ip'}`
    # echo "pod-worker2 IP=${IPV6_2}"
    # kubectl -n ${NAME_SPACE}   exec -it pod-worker -- ping -c 1 ${IPV6} 
    # kubectl -n ${NAME_SPACE}   exec -it pod-worker -- nslookup -q=AAAA echoserver.${NAME_SPACE} 
    # IPV6_SERVICE=`kubectl -n ${NAME_SPACE}   exec -it pod-worker -- nslookup -q=AAAA echoserver.${NAME_SPACE}  | grep -i Address | tail -1 | awk '{ print $2}' | sed 's/\r//g' `
    # echo "Service = ${IPV6_SERVICE}"

    echo "Testing cilium echoserver.."
    for i in 1 2 3 4 5
    do
        #echo "Testing the echo server..for the $i time"
        kubectl -n ${NAME_SPACE}   exec -it pod-worker -- curl 'http://echoserver.${NAME_SPACE} .svc.cluster.local' > /dev/null
        # echo ""
        # echo "*****"
        #kubectl -n ${NAME_SPACE}   exec -it pod-worker -- curl --interface eth0 -g -6 "http://[${IPV6_SERVICE}]"
        #kubectl -n ${NAME_SPACE}   exec -it pod-worker -- curl --interface eth0 -g -6 "http://[${IPV6_SERVICE}]"
        #break
        # sleep 1
    done 
    

}


fn_check_tetragon()
{
    TETRAGON_RUNNING=`helm list -n kube-system | grep tetragon | grep -v grep | awk '{ print $1}'`

   if [ -z "${TETRAGON_RUNNING}" ]; then
        echo "Tetragon is not installed."
        return 0
    fi
    return 1

}

fn_delete_tetragon()
{

    fn_get_cluster_config

    fn_check_tetragon

    if [ $? -ne 1 ]
    then
        return 0
    fi

    #echo "Tetragon installed on cluster ${CLUSTER_NAME}. "

    # Ask for confirmation before deleting the existing cluster
    echo " "
    echo "Do you want to DELETE Tetragon on this cluster '${CLUSTER_NAME}'? (y/n)."
    echo -n "Enter y to continue or any other value to exit: "
    read -r CONFIRMATION

    if [[ "$CONFIRMATION" != "y" && "$CONFIRMATION" != "Y" ]]; then
        fn_log "$PROGRAM" "INFO" "Tetragon deletion was not accepted"
        return 1
    fi
      #1. Delete the existing kind cluster
    helm uninstall tetragon -n kube-system
    fn_check_command "helm uninstall tetragon cilium/tetragon -n kube-system" "Failed to delete Tetragon the Kubernetes cluster '${CLUSTER_NAME}'."
    fn_delete_tetragon_demo
    fn_wait_till_all_running

    return 0
}


fn_install_tetragon_demo()
{
    
    echo "Installing tetragon demo.."
    
    kubectl -n ${NAME_SPACE}   create -f ../tetragon/yamls/http-sw-app.yaml
    fn_check_command "kubectl -n ${NAME_SPACE}   delete -f ../tetragon/yamls/http-sw-app.yaml" "Failed to upgrade cilum"

    #kubectl -n ${NAME_SPACE}   create -f ../tetragon/yamls/sw_l3_l4_policy.yaml
    #fn_check_command "../tetragon/yamls/sw_l3_l4_policy.yaml" "Failed to l3_l4  policy"

    kubectl -n ${NAME_SPACE}   create -f ../tetragon/yamls/sw_l3_l4_l7_policy.yaml -n ${NAME_SPACE}
    fn_check_command "../tetragon/yamls/sw_l3_l4_l7_policy.yaml" "Failed to create delete l3_l4_and l7 policy"

    kubectl -n ${NAME_SPACE}   create -f ../tetragon/yamls/file_monitoring.yaml
    fn_check_command "../tetragon/yamls/file_monitoring.yaml" "Failed to create delete file_monitoring.yaml"


    export PODCIDR=`kubectl -n ${NAME_SPACE}   get nodes -o jsonpath='{.items[*].spec.podCIDR}'`
    export SERVICECIDR=$(kubectl describe pod -n kube-system kube-apiserver-cilium-cluster-01-control-plane | awk -F= '/--service-cluster-ip-range/ {print $2; }')
    envsubst < ../tetragon/yamls/network/network_egress_cluster.yaml | kubectl -n ${NAME_SPACE}   apply -f -
    envsubst < ../tetragon/yamls/network/network_egress_cluster_enforce.yaml | kubectl -n ${NAME_SPACE}   apply -n ${NAME_SPACE}  -f -

    sleep 5

    echo "Waiting for all pods to be in Running state.."
    fn_wait_till_all_running

    #fn_test_tetragon_events

 
}



fn_test_tetragon_events()
{
    echo "Executing fn_test_tetragon_events.."
    
    kubectl -n ${NAME_SPACE}   exec -ti xwing -- bash -c 'curl https://ebpf.io/applications/#tetragon' > /dev/null
    kubectl -n ${NAME_SPACE}   exec -ti xwing -- bash -c 'cat /etc/shadow' > /dev/null
    kubectl -n ${NAME_SPACE}   exec -ti xwing -- bash -c 'echo foo >> /etc/bar' > /dev/null
    kubectl -n ${NAME_SPACE}   exec -ti tiefighter -- bash -c 'curl https://ebpf.io/applications/#tetragon' > /dev/null

    #kubectl -n ${NAME_SPACE}   exec -ti xwing -- bash -c 'curl -s -XPOST deathstar.${NAME_SPACE} .svc.cluster.local/v1/request-landing'  
    #kubectl -n ${NAME_SPACE}   exec -ti tiefighter -- bash -c "curl -s -XPOST deathstar.`echo ${NAME_SPACE}`.svc.cluster.local/v1/request-landing" 
    kubectl -n ${NAME_SPACE}   exec -ti tiefighter -- bash -c 'curl https://ebpf.io/applications/#tetragon' > /dev/null
    

}
fn_install_tetragon() {

     
    fn_check_cluster_exists

    if [ $? -ne 0 ]
    then
        fn_install_cluster
    fi

    fn_check_tetragon

    

     if [ $? -eq 1 ]
            then
                echo "Tetragon is already installed."
                return 0
            fi

fn_install_cilium
    # Ensure the necessary environment variables are set
    echo "Installing tetragon.."

    EXTRA_HELM_FLAGS=(--set tetragon.hostProcPath= /var/localpath-provisioner) # flags for helm install
    export EXTRA_HELM_FLAGS

    # Define the repository name and URL
    REPO_NAME="cilium"
    REPO_URL="https://helm.cilium.io"

    # Check if the repository already exists
    if ! helm repo list | grep -q "$REPO_NAME"; then
        # If the repository doesn't exist, add it
        helm repo add $REPO_NAME $REPO_URL
        fn_check_command "helm repo add $REPO_NAME $REPO_URL" "Failed whilse running helm repo add $REPO_NAME $REPO_URL"
        echo "Added Helm repo: $REPO_NAME"
    else
        echo "Helm repo $REPO_NAME already exists."
    fi

    helm repo update
    fn_check_command "helm repo update" "Failed whilse running helm repo update"
    
    # Install Tetragon via Helm
    helm install tetragon cilium/tetragon -n kube-system
    fn_check_command "helm install tetragon cilium/tetragon -n kube-system" "Failed to install tetragon"

    # Wait for Tetragon deployment to roll out
    kubectl -n ${NAME_SPACE}   rollout status -n kube-system ds/tetragon -w
   
    # Upgrade Tetragon with additional settings
    helm upgrade tetragon cilium/tetragon -n kube-system --set tetragon.grpc.address=localhost:1337
    fn_check_command "helm upgrade tetragon cilium/tetragon -n kube-system --set tetragon.grpc.address=localhost:1337" "Failed to install tetragon"
    # Create Kubernetes resources
    fn_install_tetragon_demo
    brew reinstall tetra

    # Wait until all pods are running
    echo "Waiting for all pods to be in Running state.."
    #fn_wait_till_all_running

    # Verify pod statuses
    kubectl -n ${NAME_SPACE}   get pods --all-namespaces
}

#fn_install_cilium
#fn_install_tetragon
#fn_test_cilium
#fn_test_tetragon_events

fn_test_tetragon()
{
    fn_install_tetragon

    export PODCIDR=`kubectl -n ${NAME_SPACE}   get nodes -o jsonpath='{.items[*].spec.podCIDR}'`
    export SERVICECIDR=$(kubectl -n ${NAME_SPACE}   describe pod -n kube-system kube-apiserver-${CLUSTER_NAME}-control-plane | awk -F= '/--service-cluster-ip-range/ {print $2; }')
    #wget https://raw.githubusercontent.com/cilium/tetragon/main/examples/quickstart/network_egress_cluster.yaml 
    envsubst < ../tetragon/yamls/network/network_egress_cluster.yaml | kubectl -n ${NAME_SPACE}   apply -f -
    envsubst < ../tetragon/yamls/network/network_egress_cluster_enforce.yaml | kubectl -n ${NAME_SPACE}   apply -n ${NAME_SPACE}  -f -

    #echo "In a separate window please run the following command"
    #echo " "
    #echo "kubectl -n ${NAME_SPACE}   exec -ti -n kube-system ds/tetragon -c tetragon -- tetra getevents -o compact --pods xwing "
    #echo " "
    #echo -n "Please do the above before proceeding to the next step. Once done Press <CR>"
    #read x

    fn_test_tetragon_events

}

# Function to display usage information
usage() {
    echo "Usage: $0 (--cluster | --cilium | --tetragon) (--install | --delete) --cluster-base-name <value>  --number-of-clusters <value from 1 to 3> --config-file-name <config-file-name>"
    echo "  --cluster               Specify the cluster operation."
    echo "  --cilium                Specify the cilium operation."
    echo "  --tetragon              Specify the tetragon operation."
    echo "  --install               Install the selected operation."
    echo "  --delete                Delete the selected operation."
    echo "  --test                  Test the selected operation."
    #echo "  --cluster-config-file   Delete the selected operation."
    #echo "  --number-of-clusters    Delete the selected operation."
    #echo "  --cluster-base-name     Specify the configuration name (required)."
    exit 1
}
fn_check_kind_installed()
{
    kind version > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        echo "Kubernetes software kind does not seems to be installed. Please install kind prior to proceeding"
        PRE_REQUISITES_MET=0
    fi
}

fn_check_docker_installed()
{
    docker ps > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        echo "Docker does not seems to be installed. Please install docker prior to proceeding"
        PRE_REQUISITES_MET=0
    fi
}

fn_check_brew_installed()
{
    brew --version> /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        echo "Brew does not seems to be installed. Please install brew prior to proceeding"
        PRE_REQUISITES_MET=0
     fi
}
fn_check_pre_requisites()
{
    fn_check_docker_installed
    fn_check_kind_installed
    fn_check_brew_installed

    if [ ${PRE_REQUISITES_MET} -eq 0 ]
        then
        echo "Pre-requisites NOT MET - FATAL Error. Stop"
        exit 1
    fi


}

fn_close_program()
{

echo " "

echo " "
echo "******************************************************************************************************************"
echo " "
echo "All components attempted to be installed"
echo "Check out pod health by running "
echo " " 
echo "    kubectl -n ${NAME_SPACE} get pods -A "
echo " "
echo "If all pods are not in Running status, some tests will fail !! "
echo " "
echo "******************************************************************************************************************"
echo " "
echo "  A.To watch network related events "
echo " "
echo "    cilium hubble ui (opens browser)"
echo " "
echo "    hubble observe -n ${NAME_SPACE} -f (to view network events on terminal)"
echo " "
echo "    kubectl -n ${NAME_SPACE}   exec -ti tiefighter -- bash -c 'curl -s -XPOST deathstar.`echo ${NAME_SPACE}`.svc.cluster.local/v1/request-landing' "
echo "    kubectl -n ${NAME_SPACE}   exec -ti tiefighter -- bash -c 'curl https://ebpf.io/applications/#tetragon' > /dev/null"
echo "    kubectl -n ${NAME_SPACE}   exec -ti xwing -- bash -c 'curl https://ebpf.io/applications/#tetragon' > /dev/null"
echo "    kubectl -n ${NAME_SPACE}   exec -ti xwing -- bash -c 'curl -s -XPOST deathstar.`echo ${NAME_SPACE}`.svc.cluster.local/v1/request-landing' "
echo " "
echo "    If no response for the last xwing command - Press Ctrl-C to exit"
echo " "

echo "  B.To watch file related events "
echo " "
POD=$(kubectl -n kube-system get pods -l 'app.kubernetes.io/name=tetragon' -o name --field-selector spec.nodeName=$(kubectl -n ${NAME_SPACE} get pod xwing -o jsonpath='{.spec.nodeName}'))
echo "    kubectl exec -ti -n kube-system $POD -c tetragon -- tetra getevents -o compact --pods xwing"
echo " "
echo "    kubectl -n ${NAME_SPACE}   exec -ti xwing -- bash -c 'cat /etc/shadow' "
echo "    kubectl -n ${NAME_SPACE}   exec -ti xwing -- /bin/bash "
echo " "

echo "  C.To Access Dashboards on the browser "
echo " "
echo "     1. Grafana     : https://localhost:${GRAFANA_PORT} (https)"
echo "     2. Prometheus  : http://localhost:${PROMETHEUS_PORT} (http)"
echo "     3. Kubernets   : https://localhost:${DASHBOARD_PORT} (change namespace from 'default' to '${NAME_SPACE}' at the top left corner dropdown window)"
echo " "
echo "         Choose the following token to access the admin console"
echo " "
echo "           ${ADMIN_TOKEN} "
echo " "
echo "    NOTE You may need to open additional terminals or browser session(s)"
echo " "
echo "     if any of the Browsers dont cime yp you can also try the following to open ports"
echo " "
echo "    kubectl -n cilium-monitoring port-forward service/grafana --address 0.0.0.0 --address :: ${GRAFANA_PORT}:3000 & "
echo "    kubectl -n cilium-monitoring port-forward service/prometheus --address 0.0.0.0 --address :: ${PROMETHEUS_PORT}:9090 &"
echo "    kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard --address 0.0.0.0 ${DASHBOARD_PORT}:443  &"
echo " "
   


}

PROGRAM=$0
export NAME_SPACE=${NAME_SPACE:-"self-test"}
PRE_REQUISITES_MET=1
GRAFANA_PORT=${GRAFANA_PORT:-"3000"}
PROMETHEUS_PORT=${PROMETHEUS_PORT:-"9090"}
DASHBOARD_PORT=${DASHBOARD_PORT:-"1244"}

ADMIN_TOKEN=""


fn_check_pre_requisites

# Initialize variables

CATEGORY=""
ACTION=""
START_TIME=`date`

CLUSTER_CONFIG_FILE=cluster-config.yaml
NUMBER_OF_CLUSTERS=1
CLUSTER_BASE_NAME=test-cluster-0


INFO=4
START_TIME=`date`
CLUSTER_CONFIG_FILE=""
CLUSTER_NAME=""

    # Log the start of the script
#fn_log "$PROGRAM" "$INFO" "Starting the cluster setup process"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster|--cilium|--tetragon)
            if [ -n "$CATEGORY" ]; then
                echo "Error: You cannot specify more than one category (--cluster, --cilium, or --tetragon)."
                usage
            fi
            CATEGORY="${1#--}" # Remove leading '--'
            shift
            ;;
        --install)
            if [ -n "$ACTION" ]; then
                echo "Error: You cannot specify both --install and --delete."
                usage
            fi
            ACTION="install"
            shift
            ;;
        --delete)
            if [ -n "$ACTION" ]; then
                echo "Error: You cannot specify both --install and --delete."
                usage
            fi
            ACTION="delete"
            shift
            ;;
        --test)
            if [ -n "$ACTION" ]; then
                echo "Error: You cannot specify both --install and --delete."
                usage
            fi
            ACTION="test"
            shift
            ;;
        --cluster-config-file)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --cluster-config-file requires a value."
                usage
            fi
            CLUSTER_CONFIG_FILE="$2"
            shift 2
            ;;
        --number-of-clusters)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: number-of-clusters requires a value."
                usage
            fi
            NUMBER_OF_CLUSTERS="$2"
            shift 2
            ;;
        --cluster-base-name)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --cluster-base-name requires a value."
                usage
            fi
            CLUSTER_BASE_NAME="$2"
            shift 2
            ;;
        *)
            echo "Error: Invalid argument '$1'."
            usage
            ;;
    esac
done



# Check required arguments
if [ -z "$CATEGORY" ]; then
    echo "Error: You must specify one of --cluster, --cilium, or --tetragon."
    usage
fi

if [ -z "$ACTION" ]; then
    echo "Error: You must specify either --install or --delete."
    usage
fi

# if [ -z "$CLUSTER_CONFIG_FILE" ]; then
#     echo "Error: --config-name is required."
#     usage
# fi

fn_get_cluster_config ${CLUSTER_CONFIG_FILE}

# Perform actions based on parsed arguments
echo "Category: $CATEGORY"
echo "Action: $ACTION"
echo "Configuration Name: $CLUSTER_CONFIG_FILE"
echo "Configuration Name: $CLUSTER_NAME"

kubectl config use-context kind-${CLUSTER_NAME}

case $CATEGORY in
    cluster)
        if [ "$ACTION" == "install" ]; then
            echo "Installing cluster configuration '$CLUSTER_NAME'..."
            fn_install_cluster ${CLUSTER_CONFIG_FILE} ${CLUSTER_NAME} ${NUMBER_OF_CLUSTERS}
            # Add your installation logic for clusters here
        elif [ "$ACTION" == "delete" ]; then
            echo "Deleting cluster configuration '$CLUSTER_NAME'..."
            fn_delete_cluster ${CLUSTER_CONFIG_FILE} ${CLUSTER_NAME} ${NUMBER_OF_CLUSTERS}
            # Add your deletion logic for clusters here
        fi
        ;;
    cilium)
        
        if [ "$ACTION" == "install" ]; then
            echo "Installing cilium configuration '$CLUSTER_NAME'..."
            fn_install_cilium 
            fn_close_program
        elif [ "$ACTION" == "delete" ]; then
            echo "Deleting cilium configuration '$CLUSTER_NAME'..."
            # Add your deletion logic for cilium here
            fn_delete_cilium 
        elif [ "$ACTION" == "test" ]; then
            echo "Testing cilium configuration '$CLUSTER_NAME'..."
            
            fn_test_cilium 
            fn_close_program
        fi
        ;;
    tetragon)
        if [ "$ACTION" == "install" ]; then
            echo "Installing tetragon configuration '$CLUSTER_NAME'..."
            # Add your installation logic for tetragon here
            fn_install_tetragon 
            fn_close_program
        elif [ "$ACTION" == "delete" ]; then
            echo "Deleting tetragon configuration '$CLUSTER_NAME'..."
            # Add your deletion logic for tetragon here
            fn_delete_tetragon 
        elif [ "$ACTION" == "test" ]; then
            echo "Testing tetragon configuration '$CLUSTER_NAME'..."
            
            fn_test_tetragon
            fn_close_program
        fi
        ;;
    *)
        echo "Error: Unknown category '$CATEGORY'."
        usage
        ;;
esac

#fn_test_tetragon_events

    
    #fn_log $PROGRAM $INFO "Ending program."

    echo " "
    echo "Started   ${START_TIME}."
    echo "Completed $(date)"
    echo " "

