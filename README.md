# RKE2-Boostrap Script

## What is it?
A simple script to bootstrap an RKE2 cluster using existing nodes and `ssh`. <br>

## Prerequisites
The assumption of this script is that wherever you're running it from (a local machine, utility host, etc) has: 
1. `ssh` keys set up for all the nodes you want to bootstrap
2. kubectl set up in your path, ready to use. <br>

Because of the nature of RKE2, you'll need to make sure the user you plan to use to ssh to the existing nodes has root access to download and run the RKE2 installation script.

## How it works
At a high level all this script is doing is using ```ssh``` to connect to pre-existing linux nodes, download the RKE2 install script, and join nodes using the generated token to set up an RKE2 cluster. More specifically it'll connect to your specified hosts and run a do a few things: <br>

1. For each node you'd like to add it will ask for IP address, `ssh` key path, and node role (server or agent).
2. For the first node in the list (i.e. the first node is assumed to be a server node) it will install RKE2, start the service, grab the generated token (necessary for joining other nodes to the cluster) and also grab the kubeconfig. <br>
3. For the other nodes, it will inject the token and server URL into a ```config.yaml``` and place it at```/etc/rancher/rke2/config.yaml``` prior to starting the RKE2 service, allowing them to join the cluster as they start up the RKE2 binary. <br>
4. Once all nodes have been added to the cluster, it will create a kubeconfig on the local machine (i.e. where you ran the script) with the necessary contents to connect to this new cluster using ```kubectl```. It will then wait until all nodes report as "Ready" and run a test "kubectl get nodes" to show that the cluster is healthy, all nodes are up with their respective roles, and has the proper version.<br>


## How to Use
1. Download the script. <br/>
```
wget https://raw.githubusercontent.com/dustin-groh-dev/rke2-bootstrap/refs/heads/main/rke2-boostrap/rke2-bootstrap.sh
```
2. Set your desired RKE2 version in the script variable `RKE2_VERSION` <br>
3. Make it executable
```
chmod +x rke2-bootstrap.sh
```
4. Run it
```
. rke2-bootstrap.sh
```
5. Follow the script prompts to input node IPs and ssh key paths, then let the script run. The gif below shows the end of the process as the script waits for all nodes to be ready before continuing. 


![Screenshot of completed script](https://i.imgur.com/tQybaIQ.gif))


## Known Issues/Missing features
- There's little error handling  <br>

Server node docs: <br>
https://docs.rke2.io/install/quickstart#server-node-installation <br>
https://docs.rke2.io/install/ha#2-launch-the-first-server-node
