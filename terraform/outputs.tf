output "instance_public_ip" {
  description = "Static public IP of the Boardgame K3s node (Elastic IP)"
  value       = aws_eip.boardgame_eip.public_ip
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i ~/.ssh/boardgame-ec2 ubuntu@${aws_eip.boardgame_eip.public_ip}"
}
