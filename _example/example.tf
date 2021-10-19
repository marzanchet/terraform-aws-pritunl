provider "aws" {
  region = "eu-west-1"
}

module "vpc" {
  source  = "clouddrove/vpc/aws"
  version = "0.15.0"

  name        = "vpc"
  environment = "test"
  label_order = ["name", "environment"]

  cidr_block = "172.16.0.0/16"
}

module "public_subnets" {
  source  = "clouddrove/subnet/aws"
  version = "0.15.0"

  name        = "public-subnet"
  environment = "test"
  label_order = ["name", "environment"]

  availability_zones = ["eu-west-1b", "eu-west-1c"]
  vpc_id             = module.vpc.vpc_id
  cidr_block         = module.vpc.vpc_cidr_block
  type               = "public"
  igw_id             = module.vpc.igw_id
  ipv6_cidr_block    = module.vpc.ipv6_cidr_block
}

module "vpn_sg" {
  source  = "clouddrove/security-group/aws"
  version = "0.15.0"

  name          = "pritunl"
  environment   = "test"
  label_order   = ["name", "environment"]
  protocol      = "udp"
  vpc_id        = module.vpc.vpc_id
  allowed_ip    = ["0.0.0.0/0"]
  allowed_ports = [1194]
}

module "http-https" {
  source      = "clouddrove/security-group/aws"
  version     = "0.15.0"
  name        = "http-https"
  environment = "test"
  label_order = ["name", "environment"]

  vpc_id        = module.vpc.vpc_id
  allowed_ip    = ["0.0.0.0/0"]
  allowed_ports = [80, 443]
}

module "ssh" {
  source      = "clouddrove/security-group/aws"
  version     = "0.15.0"
  name        = "ssh"
  environment = "test"
  label_order = ["name", "environment"]

  vpc_id        = module.vpc.vpc_id
  allowed_ip    = [module.vpc.vpc_cidr_block, ""]
  allowed_ports = [22]
}

module "keypair" {
  source  = "clouddrove/keypair/aws"
  version = "0.15.0"

  public_key      = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDc4AjHFctUATtd5of4u9bJtTgkh9bKogSDjxc9QqbylRORxUa422jO+t1ldTVdyqDRKltxQCJb4v23HZc2kssU5uROxpiF2fzgiHXRduL+RtyOtY2J+rNUdCRmHz4WQySblYpgteIJZpVo2smwdek8xSpjoHXhgxxa9hb4pQQwyjtVGEdH8vdYwtxgPZgPVaJgHVeJgVmhjTf2VGTATaeR9txzHsEPxhe/n1y34mQjX0ygEX8x0RZzlGziD1ih3KPaIHcpTVSYYk4LOoMK38vEI67SIMomskKn4yU043s+t9ZriJwk2V9+oU6tJU/5E1rd0SskXUhTypc3/Znc/rkYtLe8s6Uy26LOrBFzlhnCT7YH1XbCv3rEO+Nn184T4BSHeW2up8UJ1SOEd+WzzynXczdXoQcBN2kaz4dYFpRXchsAB6ejZrbEq7wyZvutf11OiS21XQ67+30lEL2WAO4i95e4sI8AdgwJgzrqVcicr3ImE+BRDkndMn5k1LhNGqwMD3Iuoel84xvinPAcElDLiFmL3BJVA/53bAlUmWqvUGW9SL5JpLUmZgE6kp+Tps7D9jpooGGJKmqgJLkJTzAmTSJh0gea/rT5KwI4j169TQD9xl6wFqns4BdQ4dMKHQCgDx8LbEd96l9F9ruWwQ8EAZBe4nIEKTV9ri+04JVhSQ== sohan@clouddrove.com"
  key_name        = "devops"
  environment     = "test"
  label_order     = ["name", "environment"]
  enable_key_pair = true
}



module "iam-role" {
  source  = "clouddrove/iam-role/aws"
  version = "0.15.0"

  name               = "iam-role-rrr"
  environment        = "test"
  label_order        = ["name", "environment"]
  assume_role_policy = data.aws_iam_policy_document.default.json

  policy_enabled = true
  policy         = data.aws_iam_policy_document.iam-policy.json
}

module "kms_key" {
  source                  = "clouddrove/kms/aws"
  version                 = "0.15.0"
  name                    = "kms"
  environment             = "test"
  label_order             = ["environment", "name"]
  enabled                 = true
  description             = "KMS key for ec2"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  alias                   = "alias/ec2"
  policy                  = data.aws_iam_policy_document.kms.json
}


data "aws_iam_policy_document" "kms" {
  version = "2012-10-17"
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

}

data "aws_iam_policy_document" "default" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "iam-policy" {
  statement {
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
    "ssmmessages:OpenDataChannel"]
    effect    = "Allow"
    resources = ["*"]
  }
}

module "ec2" {
  source      = "./../"
  name        = "pritunl"
  environment = "test"
  label_order = ["name", "environment"]

  #instance
  pritunl_enabled = true
  ami             = "ami-0a8e758f5e873d1c1"
  instance_type   = "t2.medium"
  monitoring      = false
  tenancy         = "default"

  #Networking
  vpc_security_group_ids_list = [module.ssh.security_group_ids, module.http-https.security_group_ids, module.vpn_sg.security_group_ids]
  subnet_ids                  = tolist(module.public_subnets.public_subnet_id)
  assign_eip_address          = true
  associate_public_ip_address = true

  #Keypair
  key_name = module.keypair.name

  #IAM
  instance_profile_enabled = true
  iam_instance_profile     = module.iam-role.name

  #Root Volume
  root_block_device = [
    {
      volume_type           = "gp2"
      volume_size           = 20
      delete_on_termination = true
      kms_key_id            = module.kms_key.key_arn
    }
  ]

  #user data
  user_data = file("${path.module}/pritunl.sh")

}