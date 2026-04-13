## What's different from Project 2

Project 2 was event-driven but had no error handling — if the Glue job failed, 
nothing happened. Project 3 adds full orchestration:
- Every step is tracked and visible in the Step Functions console
- Failed steps automatically retry up to 2 times with exponential backoff
- Success and failure both trigger email notifications via SNS
- The full execution history is stored and auditable

## Tech Stack

- **Terraform** — all infrastructure provisioned as code
- **AWS Step Functions** — orchestrates the pipeline as a state machine
- **AWS Glue** — serverless PySpark ETL job
- **AWS S3** — data lake with raw and processed layers
- **AWS SNS** — email notifications on success and failure
- **AWS Athena** — serverless SQL querying
- **AWS IAM** — least privilege roles for Glue and Step Functions separately

## State machine steps

| Step | Type | Description |
|---|---|---|
| RunGlueJob | Task | Runs PySpark job, retries 2x on failure |
| RunCrawler | Task | Catalogues processed schema |
| NotifySuccess | Task | Publishes success message to SNS |
| NotifyFailure | Task | Publishes failure message to SNS |
| PipelineSucceeded | Succeed | End state on success |
| PipelineFailed | Fail | End state on failure |

## Glue job transforms

- Drop rows with nulls in key columns
- Cast columns to correct types (timestamps, doubles)
- Filter out trips with zero or negative distance, fare, or total amount
- Add derived column `fare_per_mile` (fare_amount / trip_distance)

## Results

- **3,560,826** clean rows processed from NYC Yellow Taxi data
- Full execution visible in Step Functions console
- Success email received on every successful run
- Retries and error handling built into every step

## How to run

### Prerequisites
- AWS CLI configured (`aws configure`)
- Terraform installed
- IAM user with Glue, S3, Step Functions, SNS, Athena permissions

### Deploy
```bash
cd terraform
terraform init
terraform apply -var="your_name=yourname" -var="alert_email=your@email.com"
```

### Upload data
```bash
aws s3 cp yellow_tripdata_2026-01.parquet s3://project-3-pipeline-raw-yourname/data/
```

### Trigger the pipeline
```bash
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw state_machine_arn)
```

### Tear down
```bash
terraform destroy -var="your_name=yourname" -var="alert_email=your@email.com"
```

## Production considerations

- Would add S3 event notification to trigger Step Functions automatically on file upload
- Would store Terraform state in S3 backend for team environments
- Would partition processed data by date for better Athena query performance
- Would add data quality checks as a separate state before writing to processed layer
- Would use AWS Secrets Manager for sensitive configuration values
- Would add CloudWatch alarms on Step Functions execution failures