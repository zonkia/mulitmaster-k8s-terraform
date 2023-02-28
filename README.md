I. Prequisities
1. Install AWS CLI on your local machine
2. Run "aws configure" and enter your AWS account secrets.
3. Download Terraform https://www.terraform.io/downloads, extract terraform.exe to any directory and add this directory to system PATH

II. Project info
1. In variables.tf you can set any number of master/worker/monitoring nodes. For all nodes you can change types, the default is t3.medium
2. In variables.tf you can change the Container Network Interface - "cni" to be 'calico' or 'flannel'.
3. In variables.tf you can change "my_ip" if you want to restrict SSH access to the instances. The default 0.0.0.0/0 allows any IP to SSH to master instances.
4. After "terraform apply" a private key file "kubernetesKey.pem" will be created in project directory - use it to SSH to the instances.
5. Cluster is deployed with already configured cluster autoscaler for worker and monitoring nodes.

III. Deployment
1. In terminal change directory to main.tf file directory
2. Run "terraform init" and "terraform apply"
3. Wait ~5min for cluster to deploy and initial master to terminate itself
4. SSH to any master node by using auto generated "kubernetesKey.pem" - it will appear in main.tf directory
