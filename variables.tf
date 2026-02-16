variable "name" {
  type        = string
  default     = "demo"
  description = "Base name"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR"
}

variable "cluster_version" {
  type        = string
  default     = "1.29"
  description = "EKS Kubernetes version"
}

variable "allowed_api_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Who can reach EKS public API (443). In prod set to your office/VPN public IPs."
}

variable "enable_public_api" {
  type        = bool
  default     = true
  description = "If false, cluster public endpoint is disabled (recommended if you have VPN/DirectConnect)."
}

# --- Node access (PROD: prefer SSM) ---
variable "enable_ssh" {
  type        = bool
  default     = false
  description = "Enable SSH to worker nodes (NOT recommended for prod; prefer SSM)."
}

variable "ssh_key_name" {
  type        = string
  default     = "mykeypair2"
  description = "EC2 keypair for SSH (used only when enable_ssh=true)."
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs allowed to SSH to nodes (only when enable_ssh=true). In prod set your IP/32."
}
