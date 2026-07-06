output "pg_node_1_public_ip" {
  description = "Elastic IP for pg-node-1"
  value       = aws_eip.pg_node_1.public_ip
}

output "pg_node_public_ips" {
  description = "Elastic IPs for pg-node-2 and pg-node-3"
  value = {
    for k, v in aws_eip.pg_nodes : k => v.public_ip
  }
}

output "pgbr_host_public_ip" {
  description = "Elastic IP for pgbr-host"
  value       = aws_eip.pgbr_host.public_ip
}

output "vip" {
  description = "Virtual IP on pg-node-1 ENI — moved by Keepalived during failover"
  value       = "10.0.0.100"
}

output "s3_bucket" {
  description = "S3 bucket for pgBackRest backups"
  value       = aws_s3_bucket.pgbackrest.bucket
}

output "ssh_commands" {
  description = "SSH commands for all nodes"
  value = merge(
    {
      pg-node-1 = "ssh -i ${var.key_pair_path} ubuntu@${aws_eip.pg_node_1.public_ip}"
    },
    {
      for k, v in aws_eip.pg_nodes :
      k => "ssh -i ${var.key_pair_path} ubuntu@${v.public_ip}"
    },
    {
      pgbr-host = "ssh -i ${var.key_pair_path} ubuntu@${aws_eip.pgbr_host.public_ip}"
    }
  )
}
