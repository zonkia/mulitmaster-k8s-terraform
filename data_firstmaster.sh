#!/bin/bash
sudo su
yum update -y
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
yum install -y containerd
containerd config default | sudo tee /etc/containerd/config.toml
systemctl restart containerd

cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

### INITIAL MASTER CONFIG

# sleep 1m for HAproxy service to start
sleep 1m
# get haproxy private IP
aws ec2 describe-instances --query 'Reservations[].Instances[].PrivateIpAddress | [0]' --filters "Name=tag:Name,Values=Kube-Haproxy-Instance" --output text --region ${region} >> haproxyip.txt
# export necessary variables
echo "export haproxyip=$(head -1 haproxyip.txt)" >> /etc/profile
echo "export host=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)" >> /etc/profile
echo "export instanceid=$(curl http://169.254.169.254/latest/meta-data/instance-id)" >> /etc/profile
source /etc/profile
# assign pod subnet CIDR depending on chosen CNI
if [ "flannel" = ${cni} ]
  then
    echo "export podsubnet=10.244.0.0" >> /etc/profile
    source /etc/profile
  else
    echo "export podsubnet=192.168.0.0" >> /etc/profile
    source /etc/profile
fi
# create cluster config file
cat << EOF | sudo tee -a clustercfg.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$host"
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  serviceSubnet: "10.100.0.0/16"
  podSubnet: "$podsubnet/16"
controlPlaneEndpoint: "$haproxyip:6443"
apiServer:
  extraArgs:
    cloud-provider: "aws"
controllerManager:
  extraArgs:
    cloud-provider: "aws"
EOF
# initialize cluster
kubeadm init --config /clustercfg.yaml --upload-certs
# create necessary script
cat << EOF | sudo tee -a script.sh
#!/bin/bash
mkdir -p root/.kube
cp -i etc/kubernetes/admin.conf root/.kube/config
chown \$(id -u):\$(id -g) root/.kube/config
EOF
# run the script
bash script.sh
# create token, pubkey and certificate key for secondary masters and upload to secrets so they are available cluster-wide
kubeadm token create > token.txt
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' > pubkey.txt
kubeadm init phase upload-certs --upload-certs > cert_ori.txt
sed '1d;2d' cert_ori.txt > cert.txt
# apply CNI (depends on variable name 'flannel' or 'canico')
if [ "flannel" = ${cni} ]
  then
    wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    sudo kubectl apply -f /kube-flannel.yml
  else
    wget https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml
    wget https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml
    sudo kubectl create -f tigera-operator.yaml
    sudo kubectl create -f custom-resources.yaml
fi
# create ssh key
cat << EOF | sudo tee -a ${key_pair_name}.pem
${key_pair}
EOF
# change permissions for key file
chmod 600 ${key_pair_name}.pem
# sleep for 6 min before deploying cluster autoscaler and destroying initial master instance
sleep 4m
# deploy cluster autoscaler
wget https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
sed -i -e "s/<YOUR CLUSTER NAME>/kubernetes/g" cluster-autoscaler-autodiscover.yaml
sudo kubectl apply -f cluster-autoscaler-autodiscover.yaml
# export hostname as variable
echo "export dnshostname=$(hostname)" >> /etc/profile
source /etc/profile
# get running EC2 instances with tag Function=Master and create a helper file mastersip.txt
aws ec2 describe-instances --query 'Reservations[].Instances[].PrivateDnsName' --filters "Name=tag:Function,Values=Master" "Name=instance-state-name,Values=running" --region ${region} > mastersip.txt
sed -i -e 's/\[//g' -e 's/\]//g' -e 's/\"//g' -e 's/\,//g' -e 's/\ //g' -e '/^$/d' mastersip.txt
# get etcd member list
sudo kubectl exec etcd-$dnshostname -n kube-system -- etcdctl --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/peer.crt --key /etc/kubernetes/pki/etcd/peer.key member list > etcdmembers.txt
# iterate over running master nodes and remove all nodes from etcdmembers.txt except current one
while IFS= read -r line; do
  if [ "$line" != "$dnshostname" ]
    then
      sudo sed -i "/$line/d" etcdmembers.txt
  fi
done < mastersip.txt
# delete everything after comma to leave etcd member id
sed -i -e 's/[,].*$//' etcdmembers.txt
# export etcdmemberid as var
echo "export etcdmemberid=$(head -1 etcdmembers.txt)" >> /etc/profile
source /etc/profile
# delete etcd member id from cluster
sudo kubectl exec etcd-$dnshostname -n kube-system -- etcdctl --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/peer.crt --key /etc/kubernetes/pki/etcd/peer.key member remove $etcdmemberid
# delete initial master node IP from haproxy.cfg and from helper file mastersip.txt
ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" sudo sed -i "/$host/d" /etc/haproxy/haproxy.cfg
ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" sudo sed -i "/$host/d" /mastersip.txt
# restart haproxy service
ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" sudo systemctl restart haproxy
# terminate initial master instance
aws ec2 terminate-instances --instance-ids $instanceid --region ${region}