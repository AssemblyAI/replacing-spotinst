import boto3
import math
import logging
import os

from pythonjsonlogger import jsonlogger

ON_DEMAND_BASE_TAG_KEY = "od-increaser/od-minimum"

# Custom logging class to inject env
class LoggingContextFiler(logging.Filter):
    def filter(self, record):
        record.env = os.environ.get("APP_ENV", "dev")
        return True


filter = LoggingContextFiler()

log_format = jsonlogger.JsonFormatter('%(asctime)s %(levelname)s %(env)s %(name)s %(funcName)s %(message)s')

logger = logging.getLogger("od-increaser")        
logger.setLevel(os.environ.get("LAMBDA_LOG_LEVEL", "info").upper())
ch = logging.StreamHandler()
ch.setLevel(os.environ.get("LAMBDA_LOG_LEVEL", "info").upper())
ch.setFormatter(log_format)
logger.addFilter(filter)
logger.addHandler(ch)


# AWS autoscaling client
asg_client = boto3.client('autoscaling')

def check_for_on_demand_base_tag(tags):
    for tag in tags:
        if tag['Key'] == ON_DEMAND_BASE_TAG_KEY:
            logger.debug(f"Found on-demand base tag key with value of '{tag['Value']}'")
            return int(tag['Value'])
    return 0


def update_autoscaling_group_on_demand_base(asg_name, new_on_demand_base_count):
    mixed_instances_policy = {
        "InstancesDistribution": { 
            "OnDemandBaseCapacity": new_on_demand_base_count
        }
    }

    try:
        response = asg_client.update_auto_scaling_group(
            AutoScalingGroupName=asg_name,
            MixedInstancesPolicy=mixed_instances_policy
        )

        logger.debug(f"Response object {response}")

        return response

    # Rather than eat this error, we want to raise so that we get alerted
    except Exception as e:
        logger.critical("Error updating ASG on-demand base", extra={"error": e})
        raise


# Eventually we should autodiscover ASGs using tags
def asgs_to_check_for_on_demand_reduction():
    asgs_to_check = os.environ["ASG_GROUP_NAMES"].split(",")
    logger.debug(f"{asgs_to_check} will have their on-demand base reduced")

    return asgs_to_check


def half_of_current_on_demand_base(current_od_base, minimum_od_base):
    logger.debug(f"Current on-demand base is {current_od_base}, minimum on-demand base is {minimum_od_base}")

    return_value = 0

    # If the current on-demand base is less than the minimum, we need to increase the number of on-demand instances
    # This check guards against some upstream change 
    if current_od_base < minimum_od_base:
        # This will set the ASG back to the minimum number of on-demand instances
        logger.warning(f"Current on-demand base is less than minimum. Setting on-demand base to {minimum_od_base}")
        return minimum_od_base

    # Explicitly check if base is 1 because math.ceil(1/2)=1
    # which means we'll never scale down to 0
    if current_od_base == 1:
        logger.warning("Current base is 1, setting current_od_base to 0")
        return_value = 0 + minimum_od_base

    else:
        return_value = math.ceil(current_od_base / 2)
        # Make sure we don't ignore the minimum set by the tag
        if return_value < minimum_od_base:
            return_value = minimum_od_base

    logger.debug(f"Returning {return_value} for new on-demand base")

    return return_value


def new_on_demand_base(current_od_base):
    return_value = current_od_base + 1
    logger.debug(f"Returning {return_value}")
    return return_value


def describe_asg(asg_name):
    resp = asg_client.describe_auto_scaling_groups(
        AutoScalingGroupNames=[asg_name]
    )

    logger.debug(f"Response object {resp}")

    return resp


def current_on_demand_base(asg_object):
    logger.debug(f"Incoming asg object {asg_object}")
    return asg_object['AutoScalingGroups'][0]['MixedInstancesPolicy']['InstancesDistribution']['OnDemandBaseCapacity']


def lambda_handler(event, context):
    # We could also check to ensure that event['source'] == "aws.autoscaling"
    # If this event didn't trigger the Lambda, then we assume the cron did
    if event.get("detail-type") != "EC2 Instance Launch Unsuccessful":
        logger.info("Starting cron-invoked run")
        # Get our list of ASG names
        asgs_to_check = asgs_to_check_for_on_demand_reduction()
        # Iterate through ASGs and reduce their on-demand instance base if appropriate
        # TODO: In the future, we should probably describe all ASGs at once and iterate through the response
        # rather than making an API call to describe each ASG
        for asg in asgs_to_check:
            logger.debug(f"Starting on-demand base reduction for {asg}")
            # This object is the entire ASG including tags, on demand instance settings, etc
            asg_object = describe_asg(asg_name=asg)
            # Determine what the current on demand base capacity for the ASG is
            current_base = current_on_demand_base(asg_object)
            # Determine if the ASG has our special tag
            minimum_on_demand_base = check_for_on_demand_base_tag(asg_object['AutoScalingGroups'][0]['Tags'])
            # Calculate new, potentially downsized on-demand base capacity
            # This call factors in the minimum on-demand instance tag
            new_base = half_of_current_on_demand_base(current_base, minimum_on_demand_base)

            if current_base == new_base:
                logger.info("Skipping ASG modification as current and new on-demand bases are the same")
            else:
                # Make the update to the ASG
                update_autoscaling_group_on_demand_base(asg, new_base)
    else:
        logger.info("Starting failed launch-invoked run")
        asg_name = event['detail']['AutoScalingGroupName']

        logger.info(f"Increasing on-demand base for ASG '{asg_name}'")

        asg_object = describe_asg(asg_name=asg_name)
        
        current_base = current_on_demand_base(asg_object)
        new_base = new_on_demand_base(current_base)
        update_autoscaling_group_on_demand_base(asg_name, new_base)