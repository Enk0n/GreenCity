variable "aws_region" {
  description = "AWS for deployment"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "GreenCity"
  type        = string
  default     = "greencity"
}

variable "environment" {
  description = "deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR for VPC"
  type        = string
  default     = "10.0.0.0/16"
}