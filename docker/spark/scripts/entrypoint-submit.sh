#!/bin/bash

# Default values
SPARK_MASTER_PORT=${SPARK_MASTER_PORT:=7077}
SPARK_WEBUI_PORT=${SPARK_WEBUI_PORT:=8080}
SPARK_MASTER_HOST=${SPARK_MASTER_HOST:=spark-master}
MAX_RETRIES=${MAX_RETRIES:=300}
MIN_WORKERS=${MIN_WORKERS:=1}
SPARK_UI_PORT=${SPARK_UI_PORT:=4040}
POST_SCRIPT=${POST_SCRIPT:=/scripts/finish-submit.sh}
HADOOP_S3A_COMMITTERS=${HADOOP_S3A_COMMITTERS:=true}

# Atlas
/scripts/add-atlas-integration.sh

# Logs
/scripts/init-logs-metrics.sh

# Wait until cluster is up
URL="http://${SPARK_MASTER_HOST}:${SPARK_WEBUI_PORT}"

active_workers=0
echo "Checking if master ${URL} have minimum workers ${MIN_WORKERS}"
until [[ ${active_workers} -ge ${MIN_WORKERS} ]] || [[ ${MAX_RETRIES} -eq 0 ]] ; do
    sleep 1s
    active_workers=`curl --connect-timeout 10 --max-time 10 -s ${URL}/json/ | jq '.aliveworkers'`
    echo "waiting for ${URL}, to have minimum workers: ${MIN_WORKERS}, active workers: ${active_workers}"
    ((MAX_RETRIES--))
done

if [[ ${MAX_RETRIES} -eq 0 ]] ; then
    echo "Cluster $URL is not ready - stopping"
    ${POST_SCRIPT}
    exit 1
fi

# Run command
SPARK_MASTER="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"
echo -e "
spark.master=$SPARK_MASTER
spark.ui.port=$SPARK_UI_PORT
" >> /spark/conf/spark-defaults.conf

if [[ ! -z ${HIVE_METASTORE_URI} ]]; then
echo -e "
spark.sql.hive.metastore.version=$HIVE_VERSION
spark.sql.hive.metastore.jars=/opt/hive/lib/*
spark.sql.catalogImplementation=hive
spark.hadoop.hive.metastore.uris=thrift://$HIVE_METASTORE_URI
spark.hadoop.hive.metastore.schema.verification=false
spark.hadoop.hive.metastore.schema.verification.record.version=false
" >> /spark/conf/spark-defaults.conf
fi

if [ $HADOOP_S3A_COMMITTERS == "true" ]; then
echo -e "
spark.hadoop.fs.s3a.committer.name=partitioned
spark.hadoop.fs.s3a.committer.staging.conflict-mode=replace
spark.hadoop.mapreduce.outputcommitter.factory.scheme.s3a=org.apache.hadoop.fs.s3a.commit.S3ACommitterFactory
spark.hadoop.mapreduce.outputcommitter.factory.scheme.s3=org.apache.hadoop.fs.s3a.commit.S3ACommitterFactory
spark.sql.sources.commitProtocolClass=org.apache.spark.internal.io.cloud.PathOutputCommitProtocol
spark.sql.parquet.output.committer.class=org.apache.spark.internal.io.cloud.BindingParquetOutputCommitter
" >> /spark/conf/spark-defaults.conf
fi

echo "Running command: ${SUBMIT_COMMAND}"
eval ${SUBMIT_COMMAND}
EXIT_CODE=$?

${POST_SCRIPT}

exit ${EXIT_CODE}
