locals {
  od_increaser_enabled_autoscaling_groups = [
    aws_autoscaling_group.ecs_cpu_standard_general_purpose.name,
  ]
}

data "aws_iam_policy_document" "od_increaser_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "od_increaser_role" {
  name               = "${var.environment}-od-increaser"
  assume_role_policy = data.aws_iam_policy_document.od_increaser_role_policy.json
  tags = {
    owner   = "engineering"
    Project = "infra"
    service = "od-increaser"
    env     = var.environment
  }
}

data "aws_iam_policy_document" "od_increaser_policy" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
    ]
    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:UpdateAutoScalingGroup"
    ]
    resources = [
      "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${var.environment}-ecs*"
    ]
  }

}

resource "aws_iam_policy" "od_increaser_policy" {
  name   = "${var.environment}-od-increaser"
  path   = "/"
  policy = data.aws_iam_policy_document.od_increaser_policy.json
}

resource "aws_iam_role_policy_attachment" "od_increaser_policy_attachment" {
  role       = aws_iam_role.od_increaser_role.name
  policy_arn = aws_iam_policy.od_increaser_policy.arn
}

resource "aws_iam_role_policy_attachment" "od_increaser_logs_attachment" {
  role       = aws_iam_role.od_increaser_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

// Function
resource "aws_lambda_function" "od_increaser" {
  function_name                  = "${var.environment}-od-increaser"
  handler                        = "lambda_function.lambda_handler"
  runtime                        = "python3.9"
  role                           = aws_iam_role.od_increaser_role.arn
  s3_bucket                      = local.od_increaser_lambda_bucket
  s3_key                         = local.od_increaser_lambda_artifact_key
  timeout                        = 60
  memory_size                    = 1024 * 0.5
  package_type                   = "Zip"
  publish                        = false
  reserved_concurrent_executions = -1
  architectures                  = ["x86_64"]

  tags ={
      Project = "infra"
      service = "od-increaser"
      Name    = "${var.environment}-od-increaser"
    }
  

  environment {
    variables = {
      APP_ENV          = var.environment
      LAMBDA_LOG_LEVEL = "debug"
      ASG_GROUP_NAMES  = join(",", local.od_increaser_enabled_autoscaling_groups)
    }
  }

}

resource "aws_cloudwatch_log_group" "od_increaser" {
  name              = "/aws/lambda/${aws_lambda_function.od_increaser.function_name}"
  retention_in_days = 3
  tags ={
      Project = "infra"
      service = "od-increaser"
    }
  
}

// Cloudwatch Event
resource "aws_lambda_alias" "od_increaser_latest" {
  name             = "latest"
  description      = "latest"
  function_name    = aws_lambda_function.od_increaser.function_name
  function_version = "$LATEST"
}

// Cron to trigger job every half hour
resource "aws_cloudwatch_event_rule" "od_increaser_cron" {
  name                = "${var.environment}-od-increaser-cron"
  description         = "Trigger ${var.environment} od-increaser cleanup"
  schedule_expression = "cron(*/30 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "od_increaser" {
  arn  = aws_lambda_function.od_increaser.arn
  rule = aws_cloudwatch_event_rule.od_increaser_cron.name
}


resource "aws_lambda_permission" "od_increaser_allow_cloudwatch_cron" {
  statement_id  = "AllowExecutionFromCloudWatchCron"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.od_increaser.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.od_increaser_cron.arn
}

// Cloudwatch event from launch failure
resource "aws_cloudwatch_event_rule" "od_increaser_event" {
  name        = "${var.environment}-od-increaser-event"
  description = "Trigger ${var.environment} od-increaser on instance launch failure"
  event_pattern = jsonencode({
    "source" : ["aws.autoscaling"],
    "detail-type" : ["EC2 Instance Launch Unsuccessful"],
    "detail" : {
      "AutoScalingGroupName" : local.od_increaser_enabled_autoscaling_groups
    }
  })
}

resource "aws_lambda_permission" "od_increaser_allow_cloudwatch_event" {
  statement_id  = "AllowExecutionFromCloudWatchEvent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.od_increaser.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.od_increaser_event.arn
}

resource "aws_cloudwatch_event_target" "od_increaser_event" {
  arn  = aws_lambda_function.od_increaser.arn
  rule = aws_cloudwatch_event_rule.od_increaser_event.name
}


// Alarm
resource "aws_cloudwatch_metric_alarm" "od_increaser_failure" {
  alarm_name                = "${var.environment}-od-increaser-failure"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "1"
  metric_name               = "Errors"
  namespace                 = "AWS/Lambda"
  period                    = "300"
  statistic                 = "Maximum"
  threshold                 = "0"
  alarm_description         = "Monitor od_increaser for failures"
  actions_enabled           = true
  ok_actions                = []
  alarm_actions             = []
  insufficient_data_actions = []
  treat_missing_data        = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.od_increaser.function_name
  }

  tags ={
      Project = "infra"
      service = "od-increaser"
    }
  
}