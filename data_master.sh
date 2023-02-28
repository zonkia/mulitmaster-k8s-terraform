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

### SECONDARY MASTERS CONFIG

# create ssh key
cat << EOF | sudo tee -a ${key_pair_name}.pem
${key_pair}
EOF
# change permissions for ssh key
chmod 600 ${key_pair_name}.pem
# TRY to get initial master IP and get haproxy IP
aws ec2 describe-instances --query 'Reservations[].Instances[].PrivateIpAddress | [0]' --filters "Name=tag:Name,Values=Kube-First-Master-Node" "Name=instance-state-name,Values=running" --output text --region ${region} >> masternodeip.txt
aws ec2 describe-instances --query 'Reservations[].Instances[].PrivateIpAddress | [0]' --filters "Name=tag:Name,Values=Kube-Haproxy-Instance" --output text --region ${region} >> haproxyip.txt
# export IPs and host DNS name as variables
echo "export masternodeip=$(head -1 masternodeip.txt)" >> /etc/profile
echo "export haproxyip=$(head -1 haproxyip.txt)" >> /etc/profile
echo "export hostip=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)" >> /etc/profile
echo "export hostname=$(hostname)" >> /etc/profile
source /etc/profile

# check if InitialMasterNode is running; if NO then masternodeip will return None
if [ "None" = "$masternodeip" ]
  # if initial master is not running then:
  then
    # get running EC2 instances with tag Function=Master and create a helper file mastersip.txt
    aws ec2 describe-instances --query 'Reservations[].Instances[].PrivateIpAddress' --filters "Name=tag:Function,Values=Master" "Name=instance-state-name,Values=running" --region ${region} > mastersip.txt
    sudo sed -i -e 's/\[//g' -e 's/\]//g' -e 's/\"//g' -e 's/\,//g' -e 's/\ //g' -e '/^$/d' mastersip.txt
    # iterate over running master instances IPs and get first one which is != current machine IP
    while IFS= read -r line; do
      if [ "$line" != "$hostip" ]
        then
          # export master IP address and a random int to create name in haproxy.cfg
          echo "export masternodeip=$line" >> /etc/profile
          echo "export randint=$(echo $(( $RANDOM % 1000 + 1 )))"  >> /etc/profile
          source /etc/profile
      fi
    done < mastersip.txt
    # add current machine IP to haproxy.cfg and to mastersip.txt on haproxy instance, restart haproxy service, download updated mastersip file and save as downloaded_mastersips
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" "echo '    server kubemaster$randint $hostip:6443 check fall 3 rise 2' | sudo tee -a /etc/haproxy/haproxy.cfg >/dev/null"
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" "echo '$hostip' | sudo tee -a /mastersip.txt"
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" cat /mastersip.txt > downloaded_mastersips.txt
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" sudo systemctl restart haproxy
    # iterate over master IP addresses file downloaded from haproxy to find IPs of terminated instances
    while IFS= read -r line; do
      if grep -Fxq "$line" mastersip.txt
        # if IP from haproxy list exists in currently running master instances then do nothing:
        then
          echo "OK"
        # if IP from haproxy doesn't exits in list of currently running master instances then delete inactive IP from Haproxy and from ETCD members:
        else
          # delete inactive master IP from Haproxy config file and mastersip file
          ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" sudo sed -i "/$line/d" /etc/haproxy/haproxy.cfg
          ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" sudo sed -i "/$line/d" /mastersip.txt
          # restart haproxy service
          ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$haproxyip" sudo systemctl restart haproxy
          # get DNS name for inactive master node and export it to variable
          aws ec2 describe-instances --query "Reservations[].Instances[?PrivateIpAddress=='$masternodeip'].PrivateDnsName" --output text --region ${region} > masterhostname.txt
          echo "export masterhostname=$(head -1 masterhostname.txt)" >> /etc/profile
          source /etc/profile
          # get current etcd members and save to file
          ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" sudo kubectl exec etcd-$masterhostname -n kube-system -- etcdctl --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/peer.crt --key /etc/kubernetes/pki/etcd/peer.key member list > etcdmembers.txt
          # delete lines containing working master instances IPs in etcd members file
          while IFS= read -r line; do
            sudo sed -i "/$line/d" etcdmembers.txt
          done < mastersip.txt
          # sed to get only member id of inactive master instance
          sed -i -e 's/[,].*$//' etcdmembers.txt
          # iterate over inactive etcd members ids and delete them from cluster
          while IFS= read -r line; do
            # delete inactive etcd member
            ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" sudo kubectl exec etcd-$masterhostname -n kube-system -- etcdctl --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/peer.crt --key /etc/kubernetes/pki/etcd/peer.key member remove $line
          done < etcdmembers.txt
      fi
    done < downloaded_mastersips.txt
    # if initial master is down we need to ssh to another working master and create new token and certificate key for cluster join of this master and save them to files
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" sudo kubeadm token create > /token.txt
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" sudo kubeadm init phase upload-certs --upload-certs > /cert_ori.txt
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" sudo sed '1d;2d' /cert_ori.txt > /cert.txt
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' > pubkey.txt
    sed '1d;2d' cert_ori.txt > cert.txt
  # if initial master IS running then:
  else
    # wait 2m for first master node to fully initialize cluster to make sure we can get token, pubkey and cert
    sleep 2m
    # get tokens/certs from files saved on initial master node and save them to files
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" cat /token.txt > token.txt
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" cat /pubkey.txt > pubkey.txt
    ssh -i ${key_pair_name}.pem -o StrictHostKeyChecking=no "ec2-user@$masternodeip" cat /cert.txt > cert.txt
fi
# export necessary values as variables
echo "export token=$(head -1 token.txt)" >> /etc/profile
echo "export pubkey=$(head -1 pubkey.txt)" >> /etc/profile
echo "export certkey=$(head -1 cert.txt)" >> /etc/profile
source /etc/profile
# create join config file for master node
cat << EOF | sudo tee -a joincfg.yaml
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    token: "$token"
    apiServerEndpoint: "$haproxyip:6443"
    caCertHashes:
      - "sha256:$pubkey"
controlPlane:
  localAPIEndpoint:
    advertiseAddress: "$hostip"
    bindPort: 6443
  certificateKey: "$certkey"
nodeRegistration:
  name: $hostname
  kubeletExtraArgs:
    cloud-provider: aws
EOF
# join new master to cluster
kubeadm join --config /joincfg.yaml
# create necessary script
cat << EOF | sudo tee -a script.sh
#!/bin/bash
mkdir -p root/.kube
cp -i etc/kubernetes/admin.conf root/.kube/config
chown \$(id -u):\$(id -g) root/.kube/config
EOF
# run the script
bash script.sh