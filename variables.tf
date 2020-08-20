variable "environment" {
  description = "Environment that we're in"
}

variable "region" {
  description = "AWS Region that we're in"
}

variable "route53-zone-id" {
  description = "The ZONE ID of the forward DNS zone"
}

variable "route53-rev-zone-id" {
  description = "The ZONE ID of the reverse DNS zone"
}
