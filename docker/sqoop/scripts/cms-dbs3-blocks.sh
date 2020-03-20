#!/bin/bash
. $(dirname $0)/sqoop_utils.sh
setJava

BASE_PATH="/project/awg/cms/dbs3verify/CMS_DBS3_PROD_GLOBAL/blocks"

me=`basename $0`_$$

if [ -n "$1" ]
then
	START_DATE=$1
else
	START_DATE=`date +'%F' -d "1 day ago"`
fi

year=`date +'%Y' -d "$START_DATE"`
month=`date +'%-m' -d "$START_DATE"`
day=`date +'%-d' -d "$START_DATE"`
END_DATE=`date +'%F' -d "$START_DATE + 1 day"`

START_DATE_S=`date +'%s' -d "$START_DATE"`
END_DATE_S=`date +'%s' -d "$END_DATE"`

LOG_FILE=log/`date +'%F_%H%m%S'`_`basename $0`

OUTPUT_FOLDER=$BASE_PATH/diff/date=$START_DATE
MERGED_FOLDER=$BASE_PATH/merged
echo "Timerange: $START_DATE to $END_DATE" >> $LOG_FILE.cron
echo "Folder: $OUTPUT_FOLDER" >> $LOG_FILE.cron
echo "quering..." >> $LOG_FILE.cron
#exit;

sqoop import --direct --connect $(sed '1q;d' cmsr_cstring) --fetch-size 10000 --username hadoop_data_reader --password $(sed '2q;d' cmsr_cstring) --target-dir $OUTPUT_FOLDER -m 1 --query \
"SELECT D.DATASET_ID, B.BLOCK_NAME, B.OPEN_FOR_WRITING, B.BLOCK_SIZE, B.FILE_COUNT FROM CMS_DBS3_PROD_GLOBAL_OWNER.BLOCKS B JOIN CMS_DBS3_PROD_GLOBAL_OWNER.DATASETS D ON D.DATASET_ID = B.DATASET_ID  where ( B.creation_date >= ${START_DATE_S} or B.LAST_MODIFICATION_DATE >= ${START_DATE_S} ) and ( B.creation_date < ${END_DATE_S} and B.LAST_MODIFICATION_DATE < ${END_DATE_S} ) AND \$CONDITIONS" \
--fields-terminated-by , --escaped-by \\ --optionally-enclosed-by '\"' \
1>$LOG_FILE.stdout 2>$LOG_FILE.stderr

OUTPUT_ERROR=`cat $LOG_FILE.stderr | egrep "ERROR tool.ImportTool: Error during import: Import job failed!"`
TRANSF_INFO=`cat $LOG_FILE.stderr | egrep "INFO mapreduce.ImportJobBase: Transferred"`

if [[ $OUTPUT_ERROR == *"ERROR"* || ! $TRANSF_INFO == *"INFO"* ]]
then
	echo "Error occured, check $LOG_FILE"
	sendMail $LOG_FILE.stdout cms-dbs3-blocks $START_DATE
	sendMail $LOG_FILE.stderr cms-dbs3-blocks $START_DATE
else
	hdfs dfs -cat $OUTPUT_FOLDER/part-m-00000 | hdfs dfs -appendToFile - $MERGED_FOLDER/part-m-00000
fi
