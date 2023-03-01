I. Prequisities
1. Install AWS CLI on your local machine
2. Run "aws configure" and enter your AWS account secrets.
3. Download Terraform https://www.terraform.io/downloads, extract terraform.exe to any directory and add this directory to system PATH

II. Project info
1. Cluster init and node joins are done with kubeadm. 
2. In variables.tf you can set any number of master/worker/monitoring nodes. For all nodes you can change types, the default is t3.medium
3. Once deployed, it's better not to decrease master nodes count in ASG settings. If it's necessary to decrease it, then you need to remove inactive nodes from Haproxy and ETCD members manually.
4. It's possible to increase the master count in ASG settings.
5. Master and worker nodes are configured to withstand termination and to recreate themselves.
6. In variables.tf you can change the Container Network Interface - "cni" to be 'calico' or 'flannel'.
7. In variables.tf you can change "my_ip" if you want to restrict SSH access to the instances. The default 0.0.0.0/0 allows any IP to SSH to master instances.
8. After "terraform apply" a private key file "kubernetesKey.pem" will be created in project directory - use it to SSH to the instances.
9. Cluster is deployed with already configured cluster autoscaler for worker and monitoring nodes.
10. Worker nodes are labeled as "node-role.kubernetes.io/worker=worker" and monitoring nodes as "node-role.kubernetes.io/worker=monitoring"
11. Worker nodes and monitoring nodes are tainted as "NoSchedule" and thus every deployment should include tolerations for those taints. If you don't want default taints just remove them from join config files in data_worker.sh and data_monitoring.sh files 
12. Cluster is configured to be able to deploy resources in AWS e.g. LoadBalancers
13. IAM policies already include all necessary actions for Worpress + MySQL + EFS deployment.
14. RTO for destroyed master instance is ~3min and ~2,5min for worker node.

III. Deployment
1. In terminal change directory to main.tf file directory
2. Run "terraform init" and "terraform apply"
3. Wait ~5min for cluster to deploy and initial master to terminate itself
4. SSH to any master node by using auto generated "kubernetesKey.pem" - it will appear in main.tf directory
