output "instance_id" {
  value = aws_instance.lab_node.id
}

output "public_ip" {
  value = aws_instance.lab_node.public_ip
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/gmt_lab_ed25519 ${var.admin_username}@${aws_instance.lab_node.public_ip}"
}

output "extra_ebs_volume_id" {
  value = aws_ebs_volume.extra_data_gp3.id
}
