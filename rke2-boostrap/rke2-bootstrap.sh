#!/bin/bash


RKE2_VERSION="v1.30.8+rke2r1"


# Collect number of nodes and details as before
read -p "How many TOTAL nodes would you like to have in this cluster? " num_nodes

if ! [[ "$num_nodes" =~ ^[0-9]+$ ]]; then
    echo "Please enter a valid number."
    exit 1
fi

declare -A nodes
for (( i = 1; i <= num_nodes; i++ )); do
    if [[ i -eq 1 ]]; then
        echo "Enter details for node $i, this will be the first server node:"
    else
        echo "Enter details for node $i:"
    fi

    read -p "  IP Address: " ip_address
    read -p "  SSH Key Path (default: ~/.ssh/id_rsa): " ssh_key
    ssh_key=${ssh_key:-~/.ssh/id_rsa}

    if [[ ! -f "$ssh_key" ]]; then
        echo "  Warning: SSH key file $ssh_key not found. Please ensure this path is correct."
    fi

    if [[ $i -eq 1 ]]; then
        server_node="$ip_address"
        server_ssh_key="$ssh_key"
    fi

    nodes["$ip_address"]="$ssh_key"
done


# Collect rke2 version
read -p "What user would you like to use on the remote nodes? " node_user


# Confirm input
echo "You have entered the following details:"
for ip in "${!nodes[@]}"; do
    echo "  Node IP: $ip (SSH Key: ${nodes[$ip]})"
done
echo "  and the Server Node is $server_node "
echo " User: $node_user"

read -p "Do you want to proceed? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Exiting script."
    exit 0
fi

# Iterate over nodes and run commands



# Process the server node first
server_key="${nodes[$server_node]}"

echo " "
echo "Processing node: $server_node"

echo " "

ssh -i "$server_key" "$node_user@$server_node" <<OUTER_EOF
echo "Running commands on server node $server_node ..."

# Download RKE2 binary
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=$RKE2_VERSION sh -

# Enable and start RKE2 server service
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

# test if rke2-server service activates, sleep for 5 seconds if it doesnt
echo " "
echo "Waiting for rke2-server service to start..."
until sudo systemctl is-active --quiet rke2-server.service; do
  echo "rke2-server service is not active yet. Retrying..."
  sleep 5
done

echo "rke2-server service is active."

# Wait for node-token to be created, sleep for 5 seconds if it's not created yet
echo "Waiting for node-token to be available..."
until sudo test -f /var/lib/rancher/rke2/server/node-token; do
  echo "node-token not found, waiting..."
  sleep 5
  ls -l /var/lib/rancher/rke2/server/node-token || echo "Still no node-token."
done

echo "node-token found."
OUTER_EOF

# Grab the token after confirming the file exists
TOKEN=$(ssh -T -o BatchMode=yes -i "$server_key" "$node_user@$server_node" "sudo cat /var/lib/rancher/rke2/server/node-token")
echo "Token retrieved successfully."

# Print the fetched token
echo " "
echo "Fetched node token: $TOKEN"

# Process the other nodes
for ip in "${!nodes[@]}"; do
    if [[ "$ip" == "$server_node" ]]; then
        continue
    fi

    ssh_key="${nodes[$ip]}"

    echo " "
    echo "Processing node: $ip"
    echo " "

    # Create the config locally for other nodes
    echo "server: https://$server_node:9345
token: $TOKEN
tls-san: " > server_config.yaml

    # Copy the config to the node
    scp -i "$ssh_key" server_config.yaml "$node_user"@"$ip":/tmp/config.yaml

    # SSH to the node and run commands
    ssh -i "$ssh_key" "$node_user"@"$ip" <<OUTER_EOF
echo "Running commands on node $ip ..."
echo " "

# Download RKE2 binary
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=$RKE2_VERSION sh -

# Create RKE2 config directory and file
sudo mkdir -p /etc/rancher/rke2

# Move and rename the config
sudo mv /tmp/config.yaml /etc/rancher/rke2/config.yaml

echo "RKE2 config placed on node, continuing... "
echo " "

# Enable and start RKE2 agent
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

# test if service activates
echo " "
echo "Waiting for rke2-server service to start..."
until sudo systemctl is-active --quiet rke2-server.service; do
  echo "rke2-server service is not active yet. Retrying..."
  sleep 5
done

echo "rke2-server service is active."

OUTER_EOF

    # Remove the config file after it's been moved to the node
    rm -f server_config.yaml
done


echo " "
echo "Configuration complete!"
echo " "

echo "Setting kubeconfig to the new cluster. "
echo "kubeconfig will be placed at ~/.kube/config.yaml  "
echo " "

# output the kubeconfig from the server node and create a new file on the local machine as the kubeconfig
ssh -i "$ssh_key" "$node_user"@"$server_node" "sudo cat /etc/rancher/rke2/rke2.yaml" > "/tmp/kube_config.yaml"

# replace 127.0.0.1 with the IP of the server node in the kubeconfig.
sed -i "s/127.0.0.1/$server_node/g" /tmp/kube_config.yaml

# move to default location for kube config
mv /tmp/kube_config.yaml ~/.kube/config.yaml

# set kubeconfig context
export KUBECONFIG=~/.kube/config.yaml

# Function to check the readiness of all nodes
check_nodes_ready() {
    # Get the node statuses
    NODE_STATUSES=$(kubectl get nodes --no-headers | awk '{print $2}')
    
    # Loop through statuses to check if any node is not "Ready"
    for status in $NODE_STATUSES; do
        if [[ "$status" != "Ready" ]]; then
            return 1 # At least one node is not ready
        fi
    done

    return 0 # All nodes are ready
}

# Loop until all nodes are ready
echo "Checking node readiness..."
echo " "

while true; do
    if check_nodes_ready; then
        echo " "
        echo "All nodes are in the Ready state!"
        echo " "
        
        # test kubectl command
        kubectl get nodes

        break
    else
        echo "Not all nodes are Ready. Retrying in 10 seconds..."
        sleep 10
    fi
done
