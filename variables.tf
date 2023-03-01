# BASIC variables
variable "my_ip" {
  description = "personal ip for ssh access"
  default     = "0.0.0.0/0"
}
variable "key_pair_name" {
  description = "key pair name"
  default     = "kubernetesKey"
}
variable "region" {
  description = "aws region"
  default     = "eu-central-1"
}

# cluster variables
variable "cni" {
  description = "Choose container network interface: enter 'flannel' or 'calico'"
  default     = "flannel"
}
variable "number_of_master_nodes" {
  description = "Number of master nodes in Kubernetes cluster"
  type        = number
  default     = 3
}
variable "number_of_worker_nodes" {
  description = "Number of worker nodes in Kubernetes cluster"
  type        = number
  default     = 1
}
variable "number_of_monitoring_nodes" {
  description = "Number of monitoring nodes in Kubernetes cluster"
  type        = number
  default     = 1
}
variable "master_node_size" {
  description = "Master node Instance size"
  default     = "t3.medium"
}
variable "worker_node_size" {
  description = "Worker node Instance size"
  default     = "t3.medium"
}
variable "monitoring_node_size" {
  description = "Monitoring node Instance size"
  default     = "t3.medium"
}
# NAT instance
variable "nat_instance_size" {
  description = "NAT Instance size"
  default     = "t2.micro"
}
# Haproxy instance
variable "haproxy_instance_size" {
  description = "Haproxy Instance size"
  default     = "t3.small"
}

# PORTS (dont' change) -----------------------
variable "http_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 80
}
variable "mysql_port" {
  description = "The port the server will use for MYSQL requests"
  type        = number
  default     = 3306
}
variable "ssh_port" {
  description = "The port the server will use for SSH"
  type        = number
  default     = 22
}
variable "https_port" {
  description = "The port the server will use for HTTPS requests"
  type        = number
  default     = 443
}
variable "efs_port" {
  description = "EFS port"
  type        = number
  default     = 2049
}
variable "elasticsearch_portA" {
  description = "Elastic Search first port"
  type        = number
  default     = 9200
}
variable "elasticsearch_portB" {
  description = "Elastic Search second port"
  type        = number
  default     = 9300
}
variable "filebeat_port" {
  description = "The port of Filebeat->Logstash communication"
  type        = number
  default     = 5044
}
variable "oauth2proxy_port" {
  description = "The port of oauth2proxy"
  type        = number
  default     = 4180
}
variable "kibana_port" {
  description = "The port of Kibana"
  type        = number
  default     = 5601
}
