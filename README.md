# RKE2 Boostrap Script

### *This script is in development. Don't use it in production.*

## What is it?
A script to bootstrap an RKE2 cluster using existing nodes and `ssh`. <br>

## Prerequisites
The assumption of this script is that wherever you're running it from (a local machine, utility host, etc) has: 
1. ssh keys set up for all the nodes you want to bootstrap
2. kubectl set up in your path. <br>

Because of the nature of RKE2, you'll need to make sure root access to download and run the RKE2 installation script.

## How it works
At a high level all this script is doing is using ```ssh``` to connect to pre-existing linux nodes, download the RKE2 install script, and join nodes using the generated token to set up an RKE2 cluster. More specifically it'll connect to your specified hosts and run a do a few things: <br>

1. For the first "server" node (i.e. the first node created and what all other controlplane nodes will connect to) it will install RKE2, start the service, and then grab the token necessary for joining other nodes to the cluster and the kubeconfig. <br>
2. For the other nodes, it will inject the token and server URL into a ```config.yaml``` and place it at```/etc/rancher/rke2/config.yaml``` prior to starting the RKE2 service, allowing them to join the cluster as they start up the RKE2 binary. <br>
3. Once all nodes have been added to the cluster, it will create a kubeconfig on the local machine (i.e. where you ran the script) with the necessary contents to connect to this new cluster using ```kubectl```. It will then wait until all nodes report as "Ready" and run a test "kubectl get nodes" to show that the cluster has been created and is running.<br>


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
5. Follow the script prompts to input node IPs and ssh key paths, then let the script run. When complete it should look like the below screenshot.


![Screenshot of completed script](https://i.imgur.com/ShXF3Vb.png))


## Known Issues/Missing features
- There is no way to specify a node to be an agent. Currently all nodes get joined as "all" roles. <br>
- There's basically no error handling
- Adding directory validation for node token

Server node docs: <br>
https://docs.rke2.io/install/quickstart#server-node-installation <br>
https://docs.rke2.io/install/ha#2-launch-the-first-server-node
