#!/bin/sh -l

uuid="a$(cat /proc/sys/kernel/random/uuid)"

if [ "$INPUT_S3_BUCKET" ]; then
  echo "Uploading template to S3 bucket..."
  aws s3 cp $INPUT_TEMPLATE_BODY s3://$INPUT_S3_BUCKET/$uuid
fi

if [ "$INPUT_S3_BUCKET" ]; then
  aws cloudformation create-change-set --stack-name $INPUT_STACK_NAME --template-url s3://$INPUT_S3_BUCKET/$uuid --change-set-name=$uuid
else 
  aws cloudformation create-change-set --stack-name $INPUT_STACK_NAME --template-body file://$INPUT_TEMPLATE_BODY --change-set-name=$uuid
fi
if [ $? -ne 0 ]; then
  echo "[ERROR] failed to create change set."
  exit 1
fi

for i in `seq 1 5`; do
  aws cloudformation describe-change-set --change-set-name=$uuid --stack-name=$INPUT_STACK_NAME --output=json > $uuid.json 
  status=$(cat $uuid.json | jq -r '.Status')
  if [ ${status} = "CREATE_COMPLETE" ] || [ ${status} = "FAILED" ]; then    
    break
  else
    echo "change set is now creating..."
    sleep 3
  fi
done

if ["$INPUT_S3_BUCKET" ]; then
  aws s3 rm s3://$INPUT_S3_BUCKET/$uuid
fi

aws cloudformation delete-change-set --change-set-name=$uuid --stack-name=$INPUT_STACK_NAME
if [ $? -ne 0 ]; then
  echo "[ERROR] failed to delete change set."
fi

if [ ${status} != "CREATE_COMPLETE" ] && [ ${status} != "FAILED" ]; then
  echo "[ERROR] failed to create change set."
  exit 1
fi

result=$(cat $uuid.json | jq -c .)
echo "::set-output name=change_set_name::$uuid"
echo "::set-output name=result::$result"
echo "::set-output name=result_file_path::$uuid.json"

python /pretty_format.py $uuid $INPUT_STACK_NAME
echo "::set-output name=diff_file_path::$uuid.html"
