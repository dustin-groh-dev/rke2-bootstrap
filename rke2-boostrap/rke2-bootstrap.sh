#!/bin/bash

RKE2_VERSION="v1.30.8+rke2r1"

# Collect number of nodes
read -p "How many TOTAL nodes would you like to have in this cluster? " num_nodes

if ! [[ "$num_nodes" =~ ^[0-9]+$ ]]; then
    echo "Please enter a valid number."
    exit 1
fi

declare -A server_nodes
declare -A agent_nodes

for (( i = 1; i <= num_nodes; i++ )); do
    read -p "  IP Address of node $i: " ip_address
    read -p "  SSH Key Path (default: ~/.ssh/id_rsa): " ssh_key
    ssh_key=${ssh_key:-~/.ssh/id_rsa}

    if [[ ! -f "$ssh_key" ]]; then
        echo "  Warning: SSH key file $ssh_key not found. Please ensure this path is correct."
    fi

    if [[ $i -eq 1 ]]; then
        echo "Node $i will be the first server node."
        node_type="server"
        first_server_ip="$ip_address"
        first_server_ssh_key="$ssh_key"
    else
        read -p "  Is $ip_address a server or agent node? (default: server) " node_type
        node_type=${node_type,,}  # Convert to lowercase
        node_type=${node_type:-server}  # Default to server
    fi

    if [[ "$node_type" == "agent" ]]; then
        agent_nodes["$ip_address"]="$ssh_key"
    else
        server_nodes["$ip_address"]="$ssh_key"
    fi
done

# Collect SSH user
read -p "What user would you like to use on the remote nodes? " node_user


# Repeat back the node ip addresses and their types
echo "Server Nodes:"
for ip in "${!server_nodes[@]}"; do
    # Ensure the node isn't also printed under agents by mistake
    if [[ -n "${server_nodes[$ip]}" && -z "${agent_nodes[$ip]}" ]]; then
        echo "  $ip -> ${server_nodes[$ip]}"
    fi
done

echo "Agent Nodes:"
for ip in "${!agent_nodes[@]}"; do
    echo "  $ip -> ${agent_nodes[$ip]}"
done

# ask to proceed
read -p "Do you want to proceed? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Exiting script."
    exit 0
fi


# bootstrap the first node (which is a server node by default)
echo " "
echo "Installing RKE2 on first server node: $first_server_ip"

ssh -i "$first_server_ssh_key" "$node_user@$first_server_ip" <<EOF
set -e
echo "Installing RKE2 server..."
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=$RKE2_VERSION sh -
sudo systemctl enable --now rke2-server.service

# Wait for node-token to be available
while ! sudo test -e /var/lib/rancher/rke2/server/node-token; do
    echo "Waiting for node-token..."
    sleep 5
done
echo "node-token found."

EOF

# retrieve token
TOKEN=$(ssh -i "$first_server_ssh_key" "$node_user@$first_server_ip" "sudo cat /var/lib/rancher/rke2/server/node-token")
echo "Fetched node token: $TOKEN"


# if installing rke2 as on this node as a server
for ip in "${!server_nodes[@]}"; do
    if [[ "$ip" == "$first_server_ip" ]]; then
        continue
    fi

    ssh_key="${server_nodes[$ip]}"
    echo "Installing RKE2 on server node: $ip"

    ssh -i "$ssh_key" "$node_user@$ip" <<EOF
set -e
echo "Installing RKE2 server on $ip..."
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=$RKE2_VERSION sh -
sudo mkdir -p /etc/rancher/rke2
echo "server: https://$first_server_ip:9345
token: $TOKEN
tls-san:" | sudo tee /etc/rancher/rke2/config.yaml
sudo systemctl enable --now rke2-server.service
EOF
done

# if installing rke2 as this node as an agent
for ip in "${!agent_nodes[@]}"; do
    ssh_key="${agent_nodes[$ip]}"
    echo "Installing RKE2 agent on $ip"

    ssh -i "$ssh_key" "$node_user@$ip" <<EOF
set -e
echo "Installing RKE2 agent on $ip..."
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=$RKE2_VERSION INSTALL_RKE2_TYPE="agent" sh -
sudo mkdir -p /etc/rancher/rke2
echo "server: https://$first_server_ip:9345
token: $TOKEN
tls-san:" | sudo tee /etc/rancher/rke2/config.yaml
sudo systemctl enable --now rke2-agent.service
EOF
done

echo " "
echo "Configuration complete!"

# set local kubeconfig to new cluster
echo "Setting kubeconfig on local machine to ~/.kube/config.yaml"
ssh -i "$first_server_ssh_key" "$node_user@$first_server_ip" "sudo cat /etc/rancher/rke2/rke2.yaml" > "/tmp/kube_config.yaml"
sed -i "s/127.0.0.1/$first_server_ip/g" /tmp/kube_config.yaml
mv /tmp/kube_config.yaml ~/.kube/config.yaml
export KUBECONFIG=~/.kube/config.yaml

# Function to check node readiness
check_nodes_ready() {
    NODE_STATUSES=$(kubectl get nodes --no-headers | awk '{print $2}')
    for status in $NODE_STATUSES; do
        if [[ "$status" != "Ready" ]]; then
            return 1
        fi
    done
    return 0
}

echo "Checking node readiness..."
while true; do
    if check_nodes_ready; then
        echo "All nodes are Ready!"
        kubectl get nodes
        break
    else
        echo "Nodes not ready yet. Retrying in 10 seconds..."
        sleep 10
    fi
done
