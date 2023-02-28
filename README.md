I. Prequisities
1. Install AWS CLI on your local machine
2. Run "aws configure" and enter your AWS account secrets.
3. Download Terraform https://www.terraform.io/downloads, extract terraform.exe to any directory and add this directory to system PATH

II. Project info
1. In variables.tf you can set any number of master/worker/monitoring nodes. For all nodes you can change types, the default is t3.medium
2. Once deployed, it's better not to decrease master nodes count in ASG settings. If it's necessary to decrease it, then you need to remove inactive nodes from Haproxy and ETCD members manually.
3. It's possible to increase the master count in ASG settings.
4. Master and worker nodes are configured to withstand termination and to recreate themselves.
5. In variables.tf you can change the Container Network Interface - "cni" to be 'calico' or 'flannel'.
6. In variables.tf you can change "my_ip" if you want to restrict SSH access to the instances. The default 0.0.0.0/0 allows any IP to SSH to master instances.
7. After "terraform apply" a private key file "kubernetesKey.pem" will be created in project directory - use it to SSH to the instances.
8. Cluster is deployed with already configured cluster autoscaler for worker and monitoring nodes.
9. Worker nodes are labeled as "node-role.kubernetes.io/worker=worker" and monitoring nodes as "node-role.kubernetes.io/worker=monitoring"
10. Monitoring and Worker nodes are tainted as NoSchedule
11. Cluster is configured to be able to deploy resources in AWS e.g. LoadBalancers
12. IAM policies already include all necessary actions for Worpress + MySQL + EFS deployment.

III. Deployment
1. In terminal change directory to main.tf file directory
2. Run "terraform init" and "terraform apply"
3. Wait ~5min for cluster to deploy and initial master to terminate itself
4. SSH to any master node by using auto generated "kubernetesKey.pem" - it will appear in main.tf directory
