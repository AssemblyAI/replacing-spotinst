/*
This is a recreation of this cloudformation template: https://github.com/aws-samples/ecs-cid-sample/blob/master/cform/ecs.yaml

Reference this blog post for more information: https://aws.amazon.com/blogs/compute/how-to-automate-container-instance-draining-in-amazon-ecs/
*/

// Render the file and output the rendered version to the filesystem
// so that we can consume it with archive_file
data "archive_file" "ecs_asg_instance_drainer" {
  type = "zip"

  source_content = templatefile(
    "${path.module}/lambda_functions/drainer/ecs_asg_instance_draining.py.tpl",
    {
      ecs_cluster_name = "${var.environment}-cluster",
      aws_region       = data.aws_region.current.name
    }
  )
  source_content_filename = "ecs_asg_instance_draining.py"
  output_path             = "${path.module}/lambda_functions/drainer/ecs_asg_instance_draining.zip"
}

// Lambda

// Lambda IAM
data "aws_iam_policy_document" "ecs_asg_instance_drainer_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_asg_instance_drainer_role" {
  name               = "${var.environment}-ecs-asg-instance-drainer"
  assume_role_policy = data.aws_iam_policy_document.ecs_asg_instance_drainer_role_policy.json
  tags = {
    owner   = "engineering"
    Project = "infra"
    service = "ecs-asg-instance-drainer"
    env     = var.environment
  }
}

data "aws_iam_policy_document" "ecs_asg_instance_drainer_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:UpdateContainerInstancesState",
      "ecs:DescribeContainerInstances"
    ]
    resources = [
      "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:container-instance/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecs:ListContainerInstances"
    ]
    resources = [
      "arn:aws:ecs:*:${data.aws_caller_identity.current.account_id}:cluster/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:CompleteLifecycleAction"
    ]
    resources = [
      "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${var.environment}-ecs-*"
    ]
  }
}

resource "aws_iam_policy" "ecs_asg_instance_drainer_policy" {
  name   = "${var.environment}-ecs-asg-instance-drainer"
  path   = "/"
  policy = data.aws_iam_policy_document.ecs_asg_instance_drainer_policy.json
}


resource "aws_iam_role_policy_attachment" "ecs_asg_instance_drainer_attachment" {
  role       = aws_iam_role.ecs_asg_instance_drainer_role.name
  policy_arn = aws_iam_policy.ecs_asg_instance_drainer_policy.arn
}

resource "aws_iam_role_policy_attachment" "ecs_asg_instance_drainer_logs_attachment" {
  role       = aws_iam_role.ecs_asg_instance_drainer_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

// Lambda function
resource "aws_lambda_function" "ecs_asg_instance_drainer" {
  filename         = data.archive_file.ecs_asg_instance_drainer.output_path
  function_name    = "${var.environment}-ecs-asg-instance-drainer"
  description      = "Drain ECS instances when their ASG terminates them"
  role             = aws_iam_role.ecs_asg_instance_drainer_role.arn
  handler          = "ecs_asg_instance_draining.lambda_handler"
  runtime          = "python3.6"
  timeout          = 60 * 6
  memory_size      = 128 * 2
  source_code_hash = data.archive_file.ecs_asg_instance_drainer.output_base64sha256

  tags = {
    Project = "infra"
    service = "ecs"
    env     = var.environment
  }

  depends_on = [
    data.archive_file.ecs_asg_instance_drainer
  ]

}

// SNS topic
resource "aws_sns_topic" "ecs_asg_instance_drainer" {
  name         = "${var.environment}-ecs-asg-instance-drainer"
  display_name = "${var.environment}-ecs-asg-instance-drainer"

  tags = {
    Project = "infra"
    service = "ecs"
    env     = var.environment
  }

}

// Log group
resource "aws_cloudwatch_log_group" "ecs_asg_instance_drainer" {
  name              = "/aws/lambda/${aws_lambda_function.ecs_asg_instance_drainer.function_name}"
  retention_in_days = 3
}

// SNS IAM
resource "aws_lambda_permission" "ecs_asg_instance_drainer" {
  statement_id  = "AllowInvocationFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_asg_instance_drainer.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.ecs_asg_instance_drainer.arn
}

// Subscribe lambda function to topic
resource "aws_sns_topic_subscription" "ecs_asg_instance_drainer" {
  topic_arn = aws_sns_topic.ecs_asg_instance_drainer.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ecs_asg_instance_drainer.arn
}

// Alarm
resource "aws_cloudwatch_metric_alarm" "ecs_asg_instance_drainer_failure" {
  alarm_name                = "${var.environment}-ecs-asg-instance-drainer"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "1"
  metric_name               = "Errors"
  namespace                 = "AWS/Lambda"
  period                    = "300"
  statistic                 = "Maximum"
  threshold                 = "0"
  alarm_description         = "Monitor ASG instance drainer for failures"
  actions_enabled           = true
  ok_actions                = []
  alarm_actions             = [] // You should actually send the alert somewhere in real life
  insufficient_data_actions = []
  treat_missing_data        = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.ecs_asg_instance_drainer.function_name
  }

  tags = {
    Project = "infra"
    service = "ecs-asg-instance-drainer"
    env     = var.environment
  }

}