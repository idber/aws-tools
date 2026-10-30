REDIS_LIST=$(aws elasticache describe-replication-groups \
          --query 'ReplicationGroups[*].ReplicationGroupId' \
            --output text)

for REDIS_NAME in $REDIS_LIST
do
    echo "Processing $REDIS_NAME ..."
    /bin/bash ./redis-add-ip.sh "$REDIS_NAME" 
done
