output "instance_public_ip" {
  description = "Public IP of the Boardgame K3s node"
  value       = aws_instance.boardgame_node.public_ip
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i ~/.ssh/boardgame-ec2 ubuntu@${aws_instance.boardgame_node.public_ip}"
}
