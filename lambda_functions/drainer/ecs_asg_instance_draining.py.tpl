import json
import time
import boto3

# These are injected by terraform
CLUSTER = "${ecs_cluster_name}"
REGION = "${aws_region}"

DRAINING_TIME = 60 * 3


ECS = boto3.client('ecs', region_name=REGION)
ASG = boto3.client('autoscaling', region_name=REGION)
SNS = boto3.client('sns', region_name=REGION)


def find_ecs_instance_info(instance_id):
    paginator = ECS.get_paginator('list_container_instances')

    for list_resp in paginator.paginate(cluster=CLUSTER):

        arns = list_resp['containerInstanceArns']
        desc_resp = ECS.describe_container_instances(cluster=CLUSTER,
                                                    containerInstances=arns)

        for container_instance in desc_resp['containerInstances']:
            if container_instance['ec2InstanceId'] != instance_id:
                continue

            print('Found instance: id=%s, arn=%s, status=%s, runningTasksCount=%s' %
                (instance_id, container_instance['containerInstanceArn'],
                    container_instance['status'], container_instance['runningTasksCount']))

            return (container_instance['containerInstanceArn'],
                    container_instance['status'], container_instance['runningTasksCount'])

    return None, None, 0


def set_instance_to_draining(instance_arn):
    try:
        ECS.update_container_instances_state(cluster=CLUSTER,
                                                containerInstances=[instance_arn],
                                                status='DRAINING')
    except Exception as e:
        print(f"Error setting instance to DRAINING: {e}")
        raise

def instance_has_running_tasks(instance_id):
    instance_arn, container_status, running_tasks = find_ecs_instance_info(instance_id)

    if instance_arn is None:
        print(f"Could not find instance ID {instance_id}. Letting autoscaling kill the instance")

        return False, None

    if container_status != 'DRAINING':
        print(f"Container instance {instance_id} ({instance_arn}) will be set to DRAINING")

        return True, instance_arn

    if running_tasks > 0:
        return True, instance_arn 
        
    return False, None

def complete_asg_lifecycle_hook(lifecycle_hook_name, instance_id, asg_name):
    try:
        ASG.complete_lifecycle_action(LifecycleHookName=lifecycle_hook_name,
                                        AutoScalingGroupName=asg_name,
                                        LifecycleActionResult='CONTINUE',
                                        InstanceId=instance_id)

        print(f"Completed lifecycle action for instance id {instance_id} in ASG {asg_name}")
    except Exception as e:
        print(f"Error completing lifecycle action: {e}")
        raise

def lambda_handler(event, context):
    msg = json.loads(event['Records'][0]['Sns']['Message'])
    print(msg)

    ec2_instance_id = msg['EC2InstanceId']
    asg_name = msg['AutoScalingGroupName']
    lifecycle_hook_name = msg['LifecycleHookName']

    print(f"Handling event for instance {ec2_instance_id} in ASG {asg_name}")

    if 'LifecycleTransition' not in msg.keys() or msg['LifecycleTransition'].find('autoscaling:EC2_INSTANCE_TERMINATING') == -1:
        print('Exiting since the lifecycle transition is not EC2_INSTANCE_TERMINATING')
        return

    there_are_running_tasks_on_instance, instance_arn = instance_has_running_tasks(ec2_instance_id)

    if there_are_running_tasks_on_instance:

        set_instance_to_draining(instance_arn)

        print(f"Tasks are still running on instance {ec2_instance_id}. Draining it for {DRAINING_TIME} seconds and then completing lifecycle action")

        # Wait for 3 minutes while instance drains
        time.sleep(DRAINING_TIME)

        complete_asg_lifecycle_hook(lifecycle_hook_name, ec2_instance_id, asg_name)

    else:
        print(f"No tasks are running on instance {ec2_instance_id}. Setting lifecycle to complete")
        complete_asg_lifecycle_hook(lifecycle_hook_name, ec2_instance_id, asg_name)