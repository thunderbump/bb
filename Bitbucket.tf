##############################################
#  ____                 _     _
# |  _ \ _ __ _____   _(_) __| | ___ _ __ ___
# | |_) | '__/ _ \ \ / / |/ _` |/ _ \ '__/ __|
# |  __/| | | (_) \ V /| | (_| |  __/ |  \__ \
# |_|   |_|  \___/ \_/ |_|\__,_|\___|_|  |___/
#
##############################################

provider "aws" {
  region  = "${var.AwsRegion}"
  profile = "${var.AwsProfile}"
}

##############################################
#  _   _                __     __
# | | | |___  ___ _ __  \ \   / /_ _ _ __ ___
# | | | / __|/ _ \ '__|  \ \ / / _` | '__/ __|
# | |_| \__ \  __/ |      \ V / (_| | |  \__ \
#  \___/|___/\___|_|       \_/ \__,_|_|  |___/
#
##############################################

variable "AwsProfile" {
  description = "AWS profile to use"
}

variable "AwsRegion" {
  description = "EC2 Region for the VPC"
}

##############################################
# __     __
# \ \   / /_ _ _ __ ___
#  \ \ / / _` | '__/ __|
#   \ V / (_| | |  \__ \
#    \_/ \__,_|_|  |___/
#
##############################################

variable "ClusterNodeMin" {
  description = "Minimum number of cluster nodes allowed by autoscaling group"
  default     = 2
}

variable "ClusterNodeMax" {
  description = "Maximum number of cluster nodes allowed by autoscaling group"
  default     = 2
}

variable "SshKeyPair" {
  description = "SSH Key Pair to be used for EC2 instances"
}

variable "dbUser" {
  description = "Username for common database"
}

variable "dbPassword" {
  description = "Password for common database"
}

##############################################
#  ____        _
# |  _ \  __ _| |_ __ _
# | | | |/ _` | __/ _` |
# | |_| | (_| | || (_| |
# |____/ \__,_|\__\__,_|
#
##############################################

data "local_file" "ClusterNodeRoleAssumeRolePolicyDocument" {
  filename = "${path.module}/Policies/BitbucketClusterNodeRole/AssumeRolePolicyDocument.json"
}

data "local_file" "ClusterNodeRoleClusterNodePolicy" {
  filename = "${path.module}/Policies/BitbucketClusterNodeRole/Policies/BitbucketClusterNodePolicy.json"
}

data "local_file" "FileServerRoleAssumeRolePolicyDocument" {
  filename = "${path.module}/Policies/BitbucketFileServerRole/AssumeRolePolicyDocument.json"
}

data "local_file" "FileServerRoleFileServerPolicy" {
  filename = "${path.module}/Policies/BitbucketFileServerRole/Policies/BitbucketFileServerPolicy.json"
}

data "aws_vpc" "TargetVpc" {
  default = true
}

data "aws_subnet_ids" "TargetVpcSubnetIds" {
  vpc_id = "${data.aws_vpc.TargetVpc.id}"
}

#data "aws_ami" "BitbucketClusterNodeAmi" {
#  most_recent = true

#  filter {
#    name   = "tag:Release"
#    values = ["v.1.2.3.4"]
#  }
#}

data "aws_availability_zones" "available" {
  state = "available"
}

##############################################
#  ____
# |  _ \ ___  ___  ___  _   _ _ __ ___ ___  ___
# | |_) / _ \/ __|/ _ \| | | | '__/ __/ _ \/ __|
# |  _ <  __/\__ \ (_) | |_| | | | (_|  __/\__ \
# |_| \_\___||___/\___/ \__,_|_|  \___\___||___/
#
##############################################

############
# Policies #
############

#############################
# _                 _ ___       _                      
#| |   ___  __ _ __| | _ ) __ _| |__ _ _ _  __ ___ _ _ 
#| |__/ _ \/ _` / _` | _ \/ _` | / _` | ' \/ _/ -_) '_|
#|____\___/\__,_\__,_|___/\__,_|_\__,_|_||_\__\___|_|
#
#############################

##############################
# Load Balancer Target Group #
##############################

resource "aws_lb_target_group" "BitbucketAppServerClusterHttp" {
  name   = "BitbucketAppServerClusterHttp"
  vpc_id = "${data.aws_vpc.TargetVpc.id}"
}

##########################
# Load Balancer Listener #
##########################

resource "aws_lb_listener" "InboundSsh" {
  load_balancer_arn = "${aws_lb.BitbucketLoadBalancer.arn}"
  port              = 22
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.BitbucketAppServerClusterHttp.id}"
  }
}

resource "aws_lb_listener" "InboundHttp" {
  load_balancer_arn = "${aws_lb.BitbucketLoadBalancer.arn}"
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.BitbucketAppServerClusterHttp.id}"
  }
}

#########################
# Network Load Balancer #
#########################

resource "aws_lb" "BitbucketLoadBalancer" {
  name     = "BitbucketLoadBalancer"
  internal = false
  subnets  = ["${data.aws_subnet_ids.TargetVpcSubnetIds.ids[count.index]}"]

  tags {
    Name       = "Bitbucket Database"
    Membership = "Bitbucket"
  }
}

#############################
#  ___            _    _           _     ___ _                         
# | _ \___ _ _ __(_)__| |_ ___ _ _| |_  / __| |_ ___ _ _ __ _ __ _ ___ 
# |  _/ -_) '_(_-< (_-<  _/ -_) ' \  _| \__ \  _/ _ \ '_/ _` / _` / -_)
# |_| \___|_| /__/_/__/\__\___|_||_\__| |___/\__\___/_| \__,_\__, \___|
#                                                            |___/  
#############################

###################
# Security Groups #
###################

resource "aws_security_group" "NfsTrafficToClusterStorage" {
  name        = "AllowNfsTrafficToClusterStorage"
  description = "Allow NFS traffic to Cluster Storage"

  ingress {
    to_port         = 2049
    from_port       = 2049
    protocol        = "tcp"
    security_groups = ["${aws_security_group.WebTrafficToAppServers.id}"]
  }
}

#######
# EFS #
#######

resource "aws_efs_file_system" "ClusterStorage" {
  creation_token = "BitbucketClusterStorage"
  encrypted      = true

  tags = {
    Name    = "Bitbucket Cluster Storage"
    Project = "bb"
  }
}

####################
# EFS Mount Points #
####################

resource "aws_efs_mount_target" "Clusterstorage" {
  count = "${length(data.aws_subnet_ids.TargetVpcSubnetIds.ids)}"

  file_system_id = "${aws_efs_file_system.ClusterStorage.id}"
  subnet_id      = "${data.aws_subnet_ids.TargetVpcSubnetIds.ids[count.index]}"
}

#############################
#    _             _ _         _   _          
#   /_\  _ __ _ __| (_)__ __ _| |_(_)___ _ _  
#  / _ \| '_ \ '_ \ | / _/ _` |  _| / _ \ ' \ 
# /_/ \_\ .__/ .__/_|_\__\__,_|\__|_\___/_||_|
#       |_|  |_|                              
#############################

################
# IAM Policies #
################

resource "aws_iam_policy" "ClusterNodeRoleClusterNodePolicy" {
  name        = "ClusterNodeRoleClusterNodePolicy"
  description = "Policy to allow nodes to discover and join HAProxy cluster"
  policy      = "${data.local_file.ClusterNodeRoleClusterNodePolicy.content}"
}

#############
# IAM Roles #
#############

resource "aws_iam_role" "BitbucketAppServerMember" {
  name               = "BitbucketAppServerMember"
  assume_role_policy = "${data.local_file.ClusterNodeRoleAssumeRolePolicyDocument.content}"
}

###############################
# IAM Role Policy Attachments #
###############################

resource "aws_iam_role_policy_attachment" "ClusterNodeRoleClusterNodePolicyAttachment" {
  role       = "${aws_iam_role.BitbucketAppServerMember.name}"
  policy_arn = "${aws_iam_policy.ClusterNodeRoleClusterNodePolicy.arn}"
}

###################
# Security Groups #
###################

resource "aws_security_group" "AllowSsh" {
  name        = "AllowSsh"
  description = "Allow SSH from corp"

  ingress {
    to_port     = 22
    from_port   = 22
    protocol    = "tcp"
    cidr_blocks = ["199.47.246.156/32"]
  }
}

resource "aws_security_group" "WebTrafficToAppServers" {
  name        = "WebTrafficToAppServers"
  description = "Web traffic to App servers"

  ingress {
    to_port     = 80
    from_port   = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#########################
# IAM Instance Profiles #
#########################

resource "aws_iam_instance_profile" "BitbucketAppServerMember" {
  name = "BitbucketAppServerMember"
  role = "${aws_iam_role.BitbucketAppServerMember.id}"
}

#########################
# Launch Configurations #
#########################

/*
resource "aws_launch_configuration" "BitbucketAppServerMember" {
  name_prefix = "BitbucketAppServerMember"

  #image_id      = "${data.aws_ami.BitbucketClusterNodeAmi.id}"
  instance_type = "t2.micro"
  key_name      = "${var.SshKeyPair}"
  image_id      = "ami-095cd038eef3e5074"
  owner         = "709874730918"

  security_groups = ["${aws_security_group.AllowSsh.id}",
    "${aws_security_group.WebTrafficToAppServers.id}",
  ]

  iam_instance_profile = "${aws_iam_instance_profile.BitbucketAppServerMember.name}"
}
*/

####################
# Placement Groups #
####################

/*
resource "aws_placement_group" "BitbucketAppServerMembers" {
  name     = "BitbucketAppServerMembers"
  strategy = "spread"
}
*/

######################
# Autoscaling Groups #
######################

/*
resource "aws_autoscaling_group" "BitbucketAppServerMembers" {
  name                      = "BitbucketAppServerMembers"
  max_size                  = "${var.ClusterNodeMax}"
  min_size                  = "${var.ClusterNodeMin}"
  health_check_grace_period = 300
  health_check_type         = "EC2"
  placement_group           = "${aws_placement_group.BitbucketAppServerMembers.id}"
  launch_configuration      = "${aws_launch_configuration.BitbucketAppServerMember.id}"
  vpc_zone_identifier       = ["${data.aws_subnet_ids.TargetVpcSubnetIds.ids}"]

  tag {
    key                 = "membership"
    value               = "Bitbucket"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "Bitbucket App Server Node"
    propagate_at_launch = true
  }
}
*/

#############################
#  ___       _        _                  
# |   \ __ _| |_ __ _| |__  __ _ ___ ___ 
# | |) / _` |  _/ _` | '_ \/ _` (_-</ -_)
# |___/\__,_|\__\__,_|_.__/\__,_/__/\___|
#
#############################

######################
# RDS Security Group #
######################

resource "aws_security_group" "BitbucketDBSecurityGroup" {
  name = "BitbucketDBSecurityGroup"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = ["${aws_security_group.WebTrafficToAppServers.id}"]
  }
}

################
# RDS instance #
################

resource "aws_db_instance" "BitbucketDBInstance" {
  count                  = 2
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  name                   = "BitbucketDB"
  username               = "${var.dbUser}"
  password               = "${var.dbPassword}"
  multi_az               = true
  availability_zone      = "${data.aws_availability_zones.available.names[count.index]}"
  skip_final_snapshot    = true
  vpc_security_group_ids = ["${aws_security_group.BitbucketDBSecurityGroup.id}"]

  tags {
    Name       = "Bitbucket Database"
    Membership = "Bitbucket"
  }
}
