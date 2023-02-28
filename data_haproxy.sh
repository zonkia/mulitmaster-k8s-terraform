#!/bin/bash
sudo su
yum update -y
yum install haproxy -y

aws ec2 describe-instances --query 'Reservations[].Instances[].PrivateIpAddress' --filters "Name=tag:Function,Values=Master" --region ${region} > mastersip.txt
sudo sed -i -e 's/\[//g' -e 's/\]//g' -e 's/\"//g' -e 's/\,//g' -e 's/\ //g' -e '/^$/d' mastersip.txt
echo "export haproxyip=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)" >> /etc/profile
source /etc/profile

cat <<EOT >> /etc/haproxy/haproxy.cfg
frontend kubernetes-frontend
    bind $haproxyip:6443
    mode tcp
    option tcplog
    default_backend kubernetes-backend

backend kubernetes-backend
    mode tcp
    option tcp-check
    balance roundrobin
EOT

i=1
while IFS= read -r line; do

cat <<EOT >> /etc/haproxy/haproxy.cfg
    server kubemaster$i $line:6443 check fall 3 rise 2
EOT

((i++))
done < mastersip.txt

systemctl restart haproxy