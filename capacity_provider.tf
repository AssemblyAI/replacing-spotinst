data "cloudinit_config" "ecs_cpu_standard_general_purpose" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.txt"
    content      = <<EOF
#cloud-config
cloud_final_modules:
- [scripts-user, always]
EOF
  }

  part {
    content_type = "text/x-shellscript"
    filename     = "userdata.txt"
    content      = <<USERDATA
#!/usr/bin/env bash

set -xe

cat << EOF | sudo tee /etc/ecs/ecs.config
ECS_DATADIR=/data
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
ECS_LOGFILE=/log/ecs-agent.log
ECS_AVAILABLE_LOGGING_DRIVERS=["awslogs","fluentd","gelf","json-file","journald","logentries","syslog"]
ECS_LOGLEVEL=info
ECS_CLUSTER=${var.environment}-cluster
ECS_IMAGE_PULL_BEHAVIOR=prefer-cached
ECS_CONTAINER_STOP_TIMEOUT=5m
ECS_CONTAINER_START_TIMEOUT=5m
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_DISABLE_IMAGE_CLEANUP=false
ECS_IMAGE_CLEANUP_INTERVAL=720m
ECS_ENABLE_TASK_ENI=true
ECS_ENABLE_SPOT_INSTANCE_DRAINING=true
ECS_ENABLE_AWSLOGS_EXECUTIONROLE_OVERRIDE=true
ECS_RESERVED_MEMORY=256
ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=30m
ECS_INSTANCE_ATTRIBUTES={"instance.type":"cpu","instance.class":"standard","instance.subclass":"general_purpose","instance.lifecycle": "spot"}

EOF

sudo systemctl restart docker --no-block
sudo systemctl restart ecs --no-block

USERDATA
  }
}

resource "aws_launch_template" "ecs_cpu_standard_general_purpose" {
  name                                 = "${var.environment}-ecs-cpu-standard-general-purpose"
  description                          = "${var.environment}-ecs-cpu-standard-general-purpose"
  disable_api_termination              = false
  ebs_optimized                        = false
  image_id                             = data.aws_ami.ami_id.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "m5a.2xlarge"
  key_name                             = local.ssh_key_name
  user_data                            = data.cloudinit_config.ecs_cpu_standard_general_purpose.rendered

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 300
      delete_on_termination = true
      volume_type           = "gp3"
    }
  }


  iam_instance_profile {
    arn = data.aws_iam_instance_profile.ecs_container_instance_role.arn
  }

  metadata_options {
    http_endpoint = "enabled"
    // Make using v2 metadata API optional
    http_tokens                 = "optional"
    http_put_response_hop_limit = 3
  }

  monitoring {
    enabled = false
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    description                 = "${var.environment}-ecs-cpu-standard-general-purpose"
    security_groups             = [aws_security_group.ecs_container_instance.id]
  }

  tags = merge(
    {
      env     = var.environment
      Name    = "${var.environment}-ecs-cpu-standard-general-purpose"
      owner   = "engineering"
      Project = "infra"
      service = "ecs"
    }
  )
}

resource "aws_autoscaling_group" "ecs_cpu_standard_general_purpose" {
  name                      = "${var.environment}-ecs-cpu-standard-general-purpose"
  capacity_rebalance        = true
  max_size                  = 25
  min_size                  = 5
  desired_capacity          = 5
  vpc_zone_identifier       = data.aws_subnet_ids.worker_subnet_ids.ids
  default_cooldown          = 60 * 2.5
  health_check_grace_period = 120
  health_check_type         = null
  termination_policies      = ["OldestLaunchTemplate", "OldestInstance", "ClosestToNextInstanceHour", "Default"]
  suspended_processes       = null
  max_instance_lifetime     = 60 * 60 * 24 * 7
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupStandbyCapacity",
    "GroupTerminatingCapacity",
    "GroupTerminatingInstances",
    "GroupTotalCapacity",
    "GroupTotalInstances"
  ]

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs_cpu_standard_general_purpose.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = [
          "m5a.2xlarge",
          "m5ad.2xlarge",
          "m5zn.2xlarge",
          "m6i.2xlarge",
          "m5n.2xlarge",
          "m5d.2xlarge",
          "m5.2xlarge",
          "m4.2xlarge",
        ]

        content {
          instance_type     = override.value
          weighted_capacity = "1"
        }
      }
    }

    instances_distribution {
      spot_allocation_strategy = "capacity-optimized-prioritized"
      on_demand_base_capacity  = 0
      // If you want a minimum number of on-demand instances, set on_demand_base_capacity > 0
      // on_demand_base_capacity = 4
      on_demand_percentage_above_base_capacity = 0
    }
  }


  tags = concat(
    [
      {
        "key"                 = "Name"
        "value"               = "${var.environment}-ecs-cpu-standard-general-purpose"
        "propagate_at_launch" = true
      },
      {
        "key"                 = "env"
        "value"               = var.environment
        "propagate_at_launch" = true
      },
      {
        "key"                 = "Project"
        "value"               = "infra"
        "propagate_at_launch" = true
      },
      {
        "key"                 = "service"
        "value"               = "ecs"
        "propagate_at_launch" = true
      },
      {
        "key"                 = "owner"
        "value"               = "engineering"
        "propagate_at_launch" = true
      },
      {
        "key"                 = "asg/name"
        "value"               = "${var.environment}-ecs-cpu-standard-general-purpose"
        "propagate_at_launch" = true
      },
      {
        "key"                 = "AmazonECSManaged"
        "value"               = ""
        "propagate_at_launch" = true
      },
      {
        "key"                 = "VantaNonProd"
        "value"               = var.environment == "production" ? "false" : "true"
        "propagate_at_launch" = true
      },
      {
        "key"                 = "VantaDescription"
        "value"               = "ECS ASG for non-specialized workloads"
        "propagate_at_launch" = true
      },
      /*
      // Set this tag to set the minimum number of on-demand instances in this ASG
      {
        "key"                 = "od-increaser/od-minimum"
        "value"               = "4"
        "propagate_at_launch" = true
      },
      */
    ]
  )

  lifecycle {
    ignore_changes = [
      desired_capacity,
      mixed_instances_policy[0].instances_distribution[0].on_demand_base_capacity
    ]
  }
}

// Lifecycle hook for instance draining
resource "aws_autoscaling_lifecycle_hook" "ecs_cpu_standard_general_purpose" {
  name                   = "drain-before-terminate"
  autoscaling_group_name = aws_autoscaling_group.ecs_cpu_standard_general_purpose.name
  /*
  Either ABANDON or CONTINUE will work here.
  AWS Docs:
 
  If the instance is terminating, both abandon and continue allow the instance to terminate.
  However, abandon stops any remaining actions, such as other lifecycle hooks, and continue allows any other lifecycle hooks to complete. 
  */
  default_result          = "ABANDON"
  heartbeat_timeout       = 60 * 8
  lifecycle_transition    = "autoscaling:EC2_INSTANCE_TERMINATING"
  notification_target_arn = aws_sns_topic.ecs_asg_instance_drainer.arn
  role_arn                = data.aws_iam_role.ec2_asg_sns_lifecycle_hook.arn
}

resource "aws_ecs_capacity_provider" "ecs_cpu_standard_general_purpose" {
  name = "${var.environment}-ecs-cpu-standard-general-purpose"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_cpu_standard_general_purpose.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 6
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
      instance_warmup_period    = 60 * 3.5
    }
  }


  tags = {
    env     = var.environment
    Name    = "${var.environment}-ecs-cpu-standard-general-purpose"
    owner   = "engineering"
    Project = "infra"
    service = "ecs"
  }
}
