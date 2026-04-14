output "ssm_instances" {
  value = {
    nat = {
      # instance_id = aws_instance.nat.id
      ssm_command = "aws ssm start-session --target ${aws_instance.nat.id}"
    }

    ssm_host_1 = {
      # instance_id = aws_instance.ssm_host_1.id
      ssm_command = "aws ssm start-session --target ${aws_instance.ssm_host_1.id}"
    }
  }
}
