data "aws_route53_zone" "selected" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "infer" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "infer.${var.domain_name}"
  type    = "A"
  ttl     = "300"
  records = [var.instance_public_ip]
  
  # No longer need to ignore changes since we're using a variable
  # that will be updated with proper value
}
