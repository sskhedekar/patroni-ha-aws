variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.0.0/24"
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name — set via TF_VAR_key_pair_name"
  type        = string
  sensitive   = true
}

variable "key_pair_path" {
  description = "Local path to the .pem key file — used only in ssh_commands output"
  type        = string
  default     = "~/.ssh/pg-cluster-key.pem"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for pgBackRest"
  type        = string
  default     = "pg-cluster-pgbackrest"
}

variable "pg_nodes" {
  description = "PG node configuration"
  type = map(object({
    private_ip    = string
    instance_type = string
    volume_size   = number
  }))
}

variable "pgbr_host" {
  description = "pgBackRest host configuration"
  type = object({
    private_ip    = string
    instance_type = string
    volume_size   = number
  })
  default = {
    private_ip    = "10.0.0.20"
    instance_type = "t3.micro"
    volume_size   = 8
  }
}
