This is a DIY CNI plugin implemetation for BGP underlay routing network design.

Config file: 10-demoCNI.conf, need to be placed under /etc/cni/net.d/
Daemon: init.sh, only need to be executed once
Binary: opt-cni-bin-democni, need to be moved to /opt/cni/bin/democni and gave "x" permission


Steps:

0. Make sure the hosts have BIRD/kubectl/kubeconfig/jq installed, it's assumed that each host has unique AS.(Similar to Calico AS per computer design)
1. Place config file 10-demoCNI.conf to /etc/cni/net.d/
2. Modify daemon script init.sh accordingly and execute it (Make sure the Rack ToR AS is right for each host)
3. Move binary file opt-cni-bin-democni to /opt/cni/bin/democni


Tested on the following diagram and works:
![image](https://user-images.githubusercontent.com/44422591/210294241-829c17b0-0b2b-4ede-b265-a166cbbe4c56.png)
