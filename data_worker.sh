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

### WORKER CONFIG

# create ssh key file
cat << EOF | sudo tee -a ${key_pair_name}.pem
${key_pair}
EOF
# change permissions for ssh key
chmod 600 ${key_pair_name}.pem
# try to get initial master node IP and get one of secondary master nodes IP
aws ec2 describe-instances --query 'Reservations[].Instances[].PrivateIpAddress | [0]' --filters "Name=tag:Name,Values=Kube-First-Master-Node" "Name=instance-state-name,Values=running" --output text --region ${region} >> initialmasternodeip.txt
aws ec2 describe-instances --query 'Reservations[].Instances[].PrivateIpAddress | [0]' --filters "Name=tag:Name,Values=Kube-Master-Node" --output text --region ${region} >> masternodeip.txt
# export both IPs as variables
echo "export initialmasterip=$(head -1 initialmasternodeip.txt)" >> /etc/profile
echo "export masternodeip=$(head -1 masternodeip.txt)" >> /etc/profile
source /etc/profile

# if there is no initial master running then create new token on running secondary master via ssh and save to file, otherwise download already saved token from secondary master (its still valid)
if [ "None" = "$initialmasterip" ]
  then
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" sudo kubeadm token create > token.txt
  else
    sleep 3m
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" cat /token.txt > token.txt
fi
# get pubkey from secondary master
ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' > pubkey.txt
# export token, pubkey and hostname as variables
echo "export token=$(head -1 token.txt)" >> /etc/profile
echo "export pubkey=$(head -1 pubkey.txt)" >> /etc/profile
echo "export hostname=$(hostname)" >> /etc/profile
source /etc/profile
# create worker join config file
cat << EOF | sudo tee -a joincfg.yaml
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    token: "$token"
    apiServerEndpoint: "$masternodeip:6443"
    caCertHashes:
      - "sha256:$pubkey"
nodeRegistration:
  taints:
  - effect: NoSchedule
    key: worker
    value: 'yes'
  name: $hostname
  kubeletExtraArgs:
    cloud-provider: aws
EOF
# join worker to cluster
kubeadm join --config joincfg.yaml
# label node via master node
ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" sudo kubectl label nodes $hostname node-role.kubernetes.io/worker=worker
