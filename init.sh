#!/bin/bash


## This is the init script to set up environment for democni, make sure BIRD/kubectl/kubeconfig/jq are installed on all nodes.


log=/var/log/democni.log
echo >> $log
echo "#### Start the initialization..... ###" >> $log
echo >> $log


# Set default config directory and config file
defaultConfDir="/etc/cni/net.d"
if [ ! -d $defaultConfDir ]; then
		mkdir -p $defaultConfDir
fi
confFileName="${defaultConfDir}/10-demoCNI.conf"
if [ ! -f $confFileName ]; then
        echo "Config file $confFileName doesn't exist in $defaultConfDir, exiting..."
        exit 1
fi
echo "Default config directory is: $defaultConfDir" >> $log
echo "Default config file is: $confFileName" >> $log


# Get podcidrs and bridge name
podcidrs=$(cat $confFileName | jq -r ".podcidrs")
bridgeName=$(cat $confFileName | jq -r ".bridge")
echo "PodCIDRs is: $podcidrs" >> $log
echo "Bridge name is: $bridgeName" >> $log


# Get podcidr/nodeIP for local node
NODENAME=$(hostname)
kubeConfigFile="/root/.kube/config"
if [ ! -f $kubeConfigFile ]; then
        echo "Kubeconfig file $kubeConfigFile doesn't exist, exiting..."
        exit 1
fi
localPodCIDR=$(kubectl --kubeconfig=$kubeConfigFile get node $NODENAME -o json | jq -r ".spec.podCIDR")
localNodeIP=$(kubectl --kubeconfig=$kubeConfigFile get node $NODENAME -o json  | jq -r ".status.addresses" | jq -r ".[0].address")
echo "Local PodCIDR is: $localPodCIDR" >> $log
echo "Local NodeIP is: $localNodeIP" >> $log


# Save the local PodCIDR
if [ ! -d /run/democni ]; then
	mkdir -p /run/democni
	touch /run/democni/subnet.env
fi
subnet='{
	"localpodcidr": "%s"
}
'
printf "${subnet}" $localPodCIDR > /run/democni/subnet.env


# Create and Configure bridge with gateway IP
if ! ip link show $bridgeName &> /dev/null ; then
        ip link add dev $bridgeName type bridge
fi
ip link set $bridgeName up
bridgeIP=$(echo $localPodCIDR | cut -d '/' -f 1 | cut -d "." -f 1-3).254
bridgeIPNetmask=$(echo $localPodCIDR | cut -d '/' -f 2)
ip addr add ${bridgeIP}/${bridgeIPNetmask} dev $bridgeName
echo "Local bridge name and its IP is: ${bridgeName}: ${bridgeIP}/${bridgeIPNetmask}"  >> $log


# Allow pod to pod communication
iptables -A FORWARD -s $podcidrs -i $bridgeName -j ACCEPT
iptables -A FORWARD -d $podcidrs -o $bridgeName -j ACCEPT


# Allow outgoing Internet for local Pods
iptables -t nat -A POSTROUTING -s $localPodCIDR ! -o $bridgeName ! -d $podcidrs -j MASQUERADE


# Set up communication across nodes(Assuming Rack 1 SW has 65100, Rack 2 SW has 65200, ...; And all ToR has IP: a.b.c.254)
ToR_AS=65100
localNodeASIndex=$(echo $localNodeIP | cut -d "." -f 4)
localNodeAS=$(expr $ToR_AS + $localNodeASIndex)
ToR_IP=$(echo $localNodeIP | cut -d "." -f 1-3).254
echo "Local ToR AS is: $ToR_AS" >> $log
echo "Local ToR IP is: $ToR_IP" >> $log
echo "Local Node AS is: $localNodeAS" >> $log


birdConf_template='
router id %s;

protocol kernel {
        scan time 60;
        import all;
        export all;   # Actually insert routes into the kernel routing table
}

protocol device {
        scan time 60;
}

protocol direct {
        interface "%s";
}

protocol bgp upstream {
   import all;
   export where source = RTS_DEVICE;

   local as %d;
   source address %s;
   neighbor %s as %d;
}
'
cp /etc/bird/bird.conf /etc/bird/bird.conf.bak
printf "${birdConf_template}" ${localNodeIP} ${bridgeName} ${localNodeAS} ${localNodeIP} ${ToR_IP} ${ToR_AS} > /etc/bird/bird.conf
systemctl restart bird


echo >> $log
echo "#### Finish the initialization..... ###" >> $log
echo >> $log
