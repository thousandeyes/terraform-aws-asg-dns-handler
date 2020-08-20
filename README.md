# ASG DNS handler

## Source

This is heavily based on [Meltwater's work](https://github.com/meltwater/terraform-aws-asg-dns-handler), modified extensively for our own use.

## Purpose

This Terraform module sets up everything necessary for dynamically setting hostnames following a certain pattern on instances spawned by AWS Auto Scaling Groups (ASGs). 

Learn more about our motivation to build this module in [this blog post](https://underthehood.meltwater.com/blog/2020/02/07/dynamic-route53-records-for-aws-auto-scaling-groups-with-terraform/).

## Requirements

- [Terraform](https://www.terraform.io/downloads.html) 0.12+
- [Terraform AWS provider](https://github.com/terraform-providers/terraform-provider-aws) 2.0+

## Usage

Create an ASG and set the `hostname_pattern` tag for example like this:

```text
puppetserver-{{color}}-{{animal}}
k8s2-3-{{rand6}}
```

which will produce

```text
puppetserver-bittersweet-mouse
puppetserver-indigo-emu
puppetserver-red-goldendoodle
k8s2-3-rtoyce
k8s2-3-rhiixf
k8s2-3-czmkqg
```

This should be in your ASG tags in Terraform like this:

```hcl
tag {
  key                 = "hostname_pattern"
  value               = "${var.hostname_prefix}-{{rand8}}"
  propagate_at_launch = true
}
```

The list of available variables are:

```text
rand1
rand4
rand6
rand8
color
animal
```

When setting up your ASG, ensure that the LAUNCH and TERMINATION lifecycle hooks point to `data.terraform_remote_state.dns.outputs.autoscale_handling_sns_topic_arn`

## How does it work

The module sets up the following

- A SNS topic
- A Lambda function
- A topic subscription sending SNS events to the Lambda function

The Lambda function then does the following:

- Fetch the `hostname_pattern` tag value from the ASG, and parse out the hostname oattern from it.
- If it's a instance being created
  - Generate a unique hostname, based on a comination of prefix, random number of characters, colors, or animals
  - Fetch internal IP from EC2 API.
  - Create a Route53 record pointing the hostname to the IP
  - Set the Name tag of the instance to the initial part of the generated hostname
  - If it's an instance being deleted
  - Fetch the internal IP from the existing record from the Route53 API
  - Delete the record

The domain is pulled in from the layer of Terraform that we're running in, which sets `stg.sfo.thousandeyes.com`, and limits the area where each Lambda runs

## Setup

Add `initial_lifecycle_hook` definitions to your `aws_autoscaling_group resource` , like so:

```hcl
resource "aws_autoscaling_group" "my_asg" {
  name = "myASG"

  vpc_zone_identifier = var.aws_subnets

  min_size                  = var.asg_min_count
  max_size                  = var.asg_max_count
  desired_capacity          = var.asg_desired_count
  health_check_type         = "EC2"
  health_check_grace_period = 300
  force_delete              = false

  launch_configuration = aws_launch_configuration.my_launch_config.name

  lifecycle {
    create_before_destroy = true
  }

  initial_lifecycle_hook {
    name                    = "lifecycle-launching"
    default_result          = "ABANDON"
    heartbeat_timeout       = 60
    lifecycle_transition    = "autoscaling:EC2_INSTANCE_LAUNCHING"
    notification_target_arn = data.terraform_remote_state.dns.outputs.autoscale_handling_sns_topic_arn
    role_arn                = data.terraform_remote_state.dns.outputs.agent_lifecycle_iam_role_arn
  }

  initial_lifecycle_hook {
    name                    = "lifecycle-terminating"
    default_result          = "ABANDON"
    heartbeat_timeout       = 60
    lifecycle_transition    = "autoscaling:EC2_INSTANCE_TERMINATING"
    notification_target_arn = data.terraform_remote_state.dns.outputs.autoscale_handling_sns_topic_arn
    role_arn                = data.terraform_remote_state.dns.outputs.agent_lifecycle_iam_role_arn
  }

  tag {
    key                 = "asg:hostname_pattern"
    value               = "${var.hostname_prefix}-{{color}}-{{animal}}
    propagate_at_launch = true
  }
}
```

## Difference between Lifecycle action

Lifecycle_hook can have `CONTINUE` or `ABANDON` as default_result. By setting default_result to `ABANDON` will terminate the instance if the lambda function fails to update the DNS record as required. `Complete_lifecycle_action` in lambda function returns `LifecycleActionResult` as `CONTINUE` on success to Lifecycle_hook. But if lambda function fails, Lifecycle_hook doesn't get any response from `Complete_lifecycle_action` which results in timeout and terminates the instance.

At the conclusion of a lifecycle hook, the result is either ABANDON or CONTINUE.
If the instance is launching, CONTINUE indicates that your actions were successful, and that the instance can be put into service. Otherwise, ABANDON indicates that your custom actions were unsuccessful, and that the instance can be terminated.

If the instance is terminating, both ABANDON and CONTINUE allow the instance to terminate. However, ABANDON stops any remaining actions, such as other lifecycle hooks, while CONTINUE allows any other lifecycle hooks to complete.

## TODO

- Reverse lookup records?

## License and Copyright

This project was built at Meltwater. It is licensed under the [Apache License 2.0](LICENSE).
