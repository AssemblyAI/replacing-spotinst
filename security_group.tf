resource "aws_security_group" "ecs_container_instance" {
  name   = "${var.environment}-ecs-container-instance"
  vpc_id = data.aws_vpc.vpc.id

  tags = {
    Name    = "${var.environment}-ecs-container-instance"
    owner   = "engineering"
    env     = var.environment
    Project = "infra"
    service = "ecs"
    tier    = "worker"
  }
}