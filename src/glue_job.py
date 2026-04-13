import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, to_timestamp, round

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'RAW_BUCKET', 'PROCESSED_BUCKET'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

RAW_BUCKET = args['RAW_BUCKET']
PROCESSED_BUCKET = args['PROCESSED_BUCKET']

print(f"Reading from: {RAW_BUCKET}")
print(f"Writing to: {PROCESSED_BUCKET}")

# Read
df = spark.read.parquet(RAW_BUCKET)
print(f"Raw row count: {df.count()}")
df.printSchema()

# Drop nulls in key columns
key_cols = ["tpep_pickup_datetime", "tpep_dropoff_datetime", "trip_distance", "fare_amount"]
df_clean = df.dropna(subset=key_cols)

# Cast columns to correct types
df_clean = df_clean \
    .withColumn("tpep_pickup_datetime", to_timestamp(col("tpep_pickup_datetime"))) \
    .withColumn("tpep_dropoff_datetime", to_timestamp(col("tpep_dropoff_datetime"))) \
    .withColumn("trip_distance", col("trip_distance").cast("double")) \
    .withColumn("fare_amount", col("fare_amount").cast("double")) \
    .withColumn("total_amount", col("total_amount").cast("double"))

# Filter out bad rows
df_clean = df_clean.filter(
    (col("trip_distance") > 0) &
    (col("fare_amount") > 0) &
    (col("total_amount") > 0)
)

# Add derived column
df_clean = df_clean.withColumn(
    "fare_per_mile", round(col("fare_amount") / col("trip_distance"), 2)
)

print(f"Clean row count: {df_clean.count()}")

# Write as Parquet
df_clean.write.mode("overwrite").parquet(PROCESSED_BUCKET)
print("ETL complete.")

job.commit()