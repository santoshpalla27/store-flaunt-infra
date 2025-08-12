resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = "terraform-key"
  public_key = tls_private_key.key.public_key_openssh
}


resource "aws_iam_policy" "secretsmanager_read" {
  name        = "SecretsManagerReadOnlyPolicy"
  description = "Allow EC2 to read secrets from AWS Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = "arn:aws:secretsmanager:ap-south-1:537124971455:secret:mern-project-st/github*"
      }
    ]
  })
}


resource "aws_iam_role" "ec2_secretsmanager_role" {
  name = "EC2SecretsManagerAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.ec2_secretsmanager_role.name
  policy_arn = aws_iam_policy.secretsmanager_read.arn
}

resource "aws_iam_instance_profile" "ec2_secretsmanager_profile" {
  name = "EC2SecretsManagerInstanceProfile"
  role = aws_iam_role.ec2_secretsmanager_role.name
}


resource "aws_launch_template" "main-template" {
  name_prefix   = "main-template-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.generated.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_secretsmanager_profile.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              apt install -y git ansible unzip curl

              # Install AWS CLI v2 manually
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              sudo ./aws/install

              # Verify installation
              aws --version

              GITHUB_TOKEN=$(aws secretsmanager get-secret-value \
                              --secret-id mern-project-st/github \
                              --query SecretString \
                              --output text
                            )

              # Clone and run Ansible        # we can use the GitHub token to clone the repository
              git clone -b nginx-frontend "$GITHUB_TOKEN"
              cd mern-employee-docker-compose/ansible 
              # Store the vault password in a temporary file
              echo "qs@ansible27" > /tmp/vault_pass.txt
              chmod 600 /tmp/vault_pass.txt

              # Run the playbook with the vault password file
              ansible-playbook setup.yml --vault-password-file /tmp/vault_pass.txt
              shred -u /tmp/vault_pass.txt # Securely delete the vault password file

              EOF
  )


  network_interfaces {
    security_groups             = [aws_security_group.ec2_sg.id]
    associate_public_ip_address = true
  }

  lifecycle {
    create_before_destroy = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "MainInstance"
    }
  }
}


resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "web-alb"
  }
}
# target group for the ALB for frontend
resource "aws_lb_target_group" "frontend" {
  name     = "main-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    interval            = 10
    path                = "/"
    port                = "80"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}

resource "aws_lb_target_group" "backend" {
  name     = "backend-target-group"
  port     = 6068
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    interval            = 10
    path                = "/" # Health check on your backend API endpoint
    port                = "6068"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Name = "backend-target-group"
  }
}

data "aws_acm_certificate" "multi_domain_cert" {
  domain      = "santosh.website"
  statuses    = ["ISSUED"]
  most_recent = true
}




resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = data.aws_acm_certificate.multi_domain_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# for certificate 
resource "aws_lb_listener_rule" "frontend_main" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  condition {
    host_header {
      values = ["santosh.website"]
    }
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301" # Permanent redirect
    }
  }
}

resource "aws_lb_listener_rule" "backend_api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  # condition {
  #   path_pattern {
  #     values = ["/record", "/record/*" , "/health"]
  #   }
  # }
  condition {
    host_header {
      values = ["backend.santosh.website"]
    }
  }
}

resource "aws_autoscaling_group" "main" {
  name                      = "main-asg"
  min_size                  = 1
  max_size                  = 6
  desired_capacity          = 4
  vpc_zone_identifier       = aws_subnet.public[*].id
  health_check_type         = "ELB"
  health_check_grace_period = 300
  force_delete              = true
  target_group_arns         = [aws_lb_target_group.frontend.arn, aws_lb_target_group.backend.arn]

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.main-template.id
        version             = "$Latest"
      }

      # Optional: override instance types (different from launch_template's default)
      override {
        instance_type = "t2.medium"
      }

      override {
        instance_type = "t3.medium"
      }

      override {
        instance_type = "t3a.medium"
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 1   # Start with 1 On-Demand
      on_demand_percentage_above_base_capacity = 20   # 20% of instances will be On-Demand
      spot_allocation_strategy                 = "capacity-optimized"  # or "lowest-price"
    }
  }

  tag {
    key                 = "asg-instance"
    value               = "asg-instance"
    propagate_at_launch = true
  }
}


# Scale Up Policy
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.main.name
}


resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu-usage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_description = "Scale up if CPU usage is above 70% for 4 minutes"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}


# Scale Down Policy
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.main.name
}

# CloudWatch Alarm to trigger Scale Down Policy
resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "low-cpu-usage"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 40

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  alarm_description = "Scale down if CPU usage is below 40% for 4 minutes"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}



