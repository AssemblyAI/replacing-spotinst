# Replacing Spotinst

This is an example of how we replaced NetApp's Spotinst. There are two main pieces to this solution:
- The [on-demand increaser Lambda Function](./lambda_functions/increaser/)
- The [instance drainer Lambda Function](./lambda_functions/drainer/)

This repository is not production-ready, please don't try to download it and `terraform apply` your way out of Spotinst. We intend this to be more of a guideline. We also do not intend to update this repository with any regularity. 

## Increaser

The on-demand increaser Lambda Function handles incoming failed instance launch events by increasing the on-demand base capacity of the autoscaling group with launch failures.

This function can also be used to _reduce_ the on-demand base for a set of autoscaling groups. As it's written, the function will reduce the number of on-demand instances by half. This is not configurable - if you want to only decrease the on-demand base by, say, 20%, you'd have to modify the code itself.

A word of warning: we build and deploy this function via CI. The `lambda_od_increaser.tf` configuration won't _quite_ work out of the box.

## Drainer

This function handles draining ASG instances; ECS Capacity Providers will not do this for you. This Lambda function is a slightly modified version of the code in [this](https://aws.amazon.com/blogs/compute/how-to-automate-container-instance-draining-in-amazon-ecs/) article from AWS.