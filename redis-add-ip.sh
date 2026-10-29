#!/bin/bash

REGION="ap-southeast-1"
REDIS_ID="your-redis-cluster"

# 要添加的IP
IPS=(
    "1.1.1.1/32"
    "2.2.2.2/32"
    "3.3.3.3/32"
)

TARGET_SG_NAME="dddd"

# 获取redis安全组
REDIS_SGS=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id "${REDIS_ID}" \
    --show-cache-node-info \
    --region "${REGION}" \
    --query 'CacheClusters[0].SecurityGroups[*].SecurityGroupId' \
    --output text)

if [ -z "$REDIS_SGS" ]; then
    echo "未获取到Redis安全组"
    exit 1
fi

echo "Redis绑定安全组: $REDIS_SGS"

# 查找 dddd
TARGET_SG_ID=$(aws ec2 describe-security-groups \
    --region "${REGION}" \
    --filters "Name=group-name,Values=${TARGET_SG_NAME}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

if [ "$TARGET_SG_ID" != "None" ] && [ -n "$TARGET_SG_ID" ]; then
    SG_ID=$TARGET_SG_ID
    echo "找到安全组 ${TARGET_SG_NAME}: ${SG_ID}"
else
    SG_ID=$(echo "$REDIS_SGS" | awk '{print $1}')
    echo "未找到 ${TARGET_SG_NAME}，使用Redis第一个安全组: ${SG_ID}"
fi

for IP in "${IPS[@]}"
do
    echo "添加 ${IP}"

    aws ec2 authorize-security-group-ingress \
        --region "${REGION}" \
        --group-id "${SG_ID}" \
        --protocol tcp \
        --port 6379 \
        --cidr "${IP}" \
        2>/tmp/err.log

    if [ $? -eq 0 ]; then
        echo "成功: ${IP}"
    elif grep -q "InvalidPermission.Duplicate" /tmp/err.log; then
        echo "已存在: ${IP}"
    else
        echo "失败: ${IP}"
        cat /tmp/err.log
    fi
done
