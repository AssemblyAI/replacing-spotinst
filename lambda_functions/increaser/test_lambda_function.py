# Force debug when running tests
import os
os.environ["LAMBDA_LOG_LEVEL"] = "debug"

import lambda_function

def test_new_on_demand_base():
    expected_value = 3
    current = 2
    
    new = lambda_function.new_on_demand_base(current_od_base=current)

    assert new == expected_value


def test_half_of_current_on_demand_base_even_number():
    expected = 4
    current = 8

    new = lambda_function.half_of_current_on_demand_base(current_od_base=current, minimum_od_base=0)

    assert new == expected


def test_half_of_current_on_demand_base_odd_number():
    expected = 4
    current = 7

    new = lambda_function.half_of_current_on_demand_base(current_od_base=current, minimum_od_base=0)

    assert new == expected

def test_half_of_current_on_demand_base_odd_number_again():
    expected = 10
    current = 19

    new = lambda_function.half_of_current_on_demand_base(current_od_base=current, minimum_od_base=0)

    assert new == expected

def test_half_of_current_on_demand_base_when_base_is_1():
    expected = 0
    current = 1

    new = lambda_function.half_of_current_on_demand_base(current_od_base=current, minimum_od_base=0)

    assert new == expected


def test_asgs_to_check_for_on_demand_reduction():
    asg_names = "group-one,group-two"
    asg_names_list = asg_names.split(",")

    os.environ["ASG_GROUP_NAMES"] = "group-one,group-two"

    asgs = lambda_function.asgs_to_check_for_on_demand_reduction()

    assert asgs == asg_names_list



def test_check_for_on_demand_base_tag_tag_exists():
    expected = 5

    tags = [{'ResourceId': 'staging-ecs-gpu-standard-spot', 'ResourceType': 'auto-scaling-group', 'Key': 'AmazonECSManaged', 'Value': '', 'PropagateAtLaunch': True}, {'ResourceId': 'staging-ecs-gpu-standard-spot', 'ResourceType': 'auto-scaling-group', 'Key': lambda_function.ON_DEMAND_BASE_TAG_KEY, 'Value': str(expected), 'PropagateAtLaunch': True}]

    rv = lambda_function.check_for_on_demand_base_tag(tags)

    assert rv == 5



def test_check_for_on_demand_base_tag_tag_does_not_exist():
    expected = 0

    tags = [{'ResourceId': 'staging-ecs-gpu-standard-spot', 'ResourceType': 'auto-scaling-group', 'Key': 'AmazonECSManaged', 'Value': '', 'PropagateAtLaunch': True}, {'ResourceId': 'staging-ecs-gpu-standard-spot', 'ResourceType': 'auto-scaling-group', 'Key': 'foo', 'Value': 'bar', 'PropagateAtLaunch': True}]

    rv = lambda_function.check_for_on_demand_base_tag(tags)

    assert rv == expected

def test_half_of_current_on_demand_base_desired_less_than_min():
    minimum = 5
    current = 4

    new = lambda_function.half_of_current_on_demand_base(current_od_base=current, minimum_od_base=minimum)

    assert new == minimum