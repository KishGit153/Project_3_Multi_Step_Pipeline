variable "aws_region" {
  description = "AWS region"
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Project name used for naming resources"
  default     = "project-3-pipeline"
}

variable "your_name" {
  description = "Your name suffix to make S3 bucket names unique"
  type        = string
}

variable "alert_email" {
  description = "Email address for pipeline success and failure alerts"
  type        = string
}
