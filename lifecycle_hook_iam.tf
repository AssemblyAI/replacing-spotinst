data "aws_iam_policy_document" "ec2_sns_lifecycle_hooks_sns" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["autoscaling.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_sns_lifecycle_hooks_sns" {
  name               = "ec2-asg-lifecycle-sns"
  assume_role_policy = data.aws_iam_policy_document.ec2_sns_lifecycle_hooks_sns.json
  tags = {
    owner   = "engineering"
    Project = "infra"
    service = "ec2-asg-lifecycle-sns"
    env     = "any"
  }
}

resource "aws_iam_role_policy_attachment" "ec2_sns_lifecycle_hooks_sns" {
  role       = aws_iam_role.ec2_sns_lifecycle_hooks_sns.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AutoScalingNotificationAccessRole"
}