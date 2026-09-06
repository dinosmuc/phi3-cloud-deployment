
// APPLICATION LOAD BALANCER
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  idle_timeout       = 300

  tags = {
    Name = "${var.project_name}-alb"
  }
}


// TARGET GROUP
resource "aws_lb_target_group" "main" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 60

  tags = {
    Name = "${var.project_name}-tg"
  }
}


// HTTP LISTENER
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}


// WAF WEB ACL
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-waf"
  description = "Baseline WAF for ALB: AWS Managed Common Rule Set + 1000 req/IP/5min rate limit."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"

        // Five rules in this group inspect the request BODY, which for a chat API is
        // the user's free-form prose — so with the group's default Block action they
        // reject legitimate messages, not attacks. Each is switched to Count: the rule
        // still evaluates and still reports to CloudWatch, but it no longer blocks.
        // Everything else in the Core Rule Set (headers, URI, query string, bad bots)
        // keeps blocking, which is what actually protects this endpoint.
        //
        // What each one rejects in practice:
        //   SizeRestrictions_BODY    bodies over 8 KB — pasting an article to summarise.
        //                            The 8 KB inspection limit is fixed for an ALB.
        //   CrossSiteScripting_BODY  "what does <script>alert(1)</script> do?"
        //   GenericLFI_BODY          any "../" in a question about file paths.
        //   GenericRFI_BODY          URLs with IPv4 hosts, e.g. http://127.0.0.1:8000.
        //   EC2MetaDataSSRF_BODY     asking the model about 169.254.169.254.
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "CrossSiteScripting_BODY"
          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "GenericLFI_BODY"
          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "GenericRFI_BODY"
          action_to_use {
            count {}
          }
        }

        rule_action_override {
          name = "EC2MetaDataSSRF_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit = 1000

        // The ALB sits behind CloudFront, so the source IP it sees is a CloudFront
        // edge server, not the visitor. Aggregating on "IP" would therefore share
        // one budget across everyone behind the same edge. Count the client IP that
        // CloudFront forwards instead.
        //
        // fallback_behavior MATCH blocks requests whose header value is malformed,
        // which is the AWS-recommended pairing for a rule whose action is block. It
        // does not cover a missing header: AWS WAF skips a forwarded-IP rule entirely
        // when the header is absent. See the README limitations for what that means.
        aggregate_key_type = "FORWARDED_IP"

        forwarded_ip_config {
          header_name       = "X-Forwarded-For"
          fallback_behavior = "MATCH"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-waf"
  }
}

resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}