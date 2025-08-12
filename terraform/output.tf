output "alb_dns_name" {
  value = aws_lb.web_alb.dns_name
}
#output "ec2_public_ip" {
#  value = aws_launch_template.web.public_ip
#}

output "ssh_private_key" {
  value     = tls_private_key.key.private_key_pem
  sensitive = true
}

