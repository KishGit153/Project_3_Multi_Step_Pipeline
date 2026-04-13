terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- S3 Buckets ---
resource "aws_s3_bucket" "raw" {
  bucket        = "${var.project_name}-raw-${var.your_name}"
  force_destroy = true

  tags = {
    Project     = var.project_name
    Environment = "dev"
  }
}

resource "aws_s3_bucket" "processed" {
  bucket        = "${var.project_name}-processed-${var.your_name}"
  force_destroy = true

  tags = {
    Project     = var.project_name
    Environment = "dev"
  }
}

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.project_name}-athena-${var.your_name}"
  force_destroy = true

  tags = {
    Project     = var.project_name
    Environment = "dev"
  }
}

# --- Upload Glue script to S3 ---
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.raw.id
  key    = "scripts/glue_job.py"
  source = "../src/glue_job.py"
  etag   = filemd5("../src/glue_job.py")
}

# --- SNS Topic ---
resource "aws_sns_topic" "pipeline_alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Project     = var.project_name
    Environment = "dev"
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Glue Job ---
resource "aws_glue_job" "etl" {
  name         = "${var.project_name}-job"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    script_location = "s3://${aws_s3_bucket.raw.bucket}/scripts/glue_job.py"
    python_version  = "3"
  }

  default_arguments = {
    "--RAW_BUCKET"          = "s3://${aws_s3_bucket.raw.bucket}/data/"
    "--PROCESSED_BUCKET"    = "s3://${aws_s3_bucket.processed.bucket}/output/"
    "--job-language"        = "python"
    "--enable-job-insights" = "true"
  }

  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 30

  tags = {
    Project     = var.project_name
    Environment = "dev"
  }
}

# --- Glue Crawler ---
resource "aws_glue_catalog_database" "db" {
  name = "project3_nyc_taxi_db"
}

resource "aws_glue_crawler" "processed" {
  name          = "${var.project_name}-crawler"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.db.name

  s3_target {
    path = "s3://${aws_s3_bucket.processed.bucket}/output/"
  }

  tags = {
    Project     = var.project_name
    Environment = "dev"
  }
}

# --- Athena Workgroup ---
resource "aws_athena_workgroup" "main" {
  name = "${var.project_name}-workgroup"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"
    }
  }

  tags = {
    Project     = var.project_name
    Environment = "dev"
  }
}

# --- Step Functions State Machine ---
resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.project_name}-state-machine"
  role_arn = aws_iam_role.sfn_role.arn

  definition = jsonencode({
    Comment = "NYC Taxi ETL Pipeline orchestrated by Step Functions"
    StartAt = "RunGlueJob"

    States = {
      RunGlueJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.etl.name
          Arguments = {
            "--RAW_BUCKET"       = "s3://${aws_s3_bucket.raw.bucket}/data/"
            "--PROCESSED_BUCKET" = "s3://${aws_s3_bucket.processed.bucket}/output/"
          }
        }
        Retry = [{
          ErrorEquals     = ["States.ALL"]
          IntervalSeconds = 30
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyFailure"
        }]
        Next = "RunCrawler"
      }

      RunCrawler = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:glue:startCrawler"
        Parameters = {
          Name = aws_glue_crawler.processed.name
        }
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "NotifyFailure"
        }]
        Next = "NotifySuccess"
      }

      NotifySuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.pipeline_alerts.arn
          Message  = "NYC Taxi ETL pipeline completed successfully!"
          Subject  = "Pipeline Success"
        }
        Next = "PipelineSucceeded"
      }

      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.pipeline_alerts.arn
          Message  = "NYC Taxi ETL pipeline failed. Check Step Functions console for details."
          Subject  = "Pipeline Failed"
        }
        Next = "PipelineFailed"
      }

      PipelineSucceeded = {
        Type = "Succeed"
      }

      PipelineFailed = {
        Type  = "Fail"
        Error = "PipelineFailed"
        Cause = "One or more pipeline steps failed"
      }
    }
  })

  tags = {
    Project     = var.project_name
    Environment = "dev"
  }
}
