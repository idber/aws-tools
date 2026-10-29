#!/bin/bash

REGION="cn-hangzhou"     # 修改区域
REDIS_ID="r-xxxxx"       # Redis实例ID

IPS=(
    "1.1.1.1/32"
    "2.2.2.2/32"
    "3.3.3.3/32"
)

TARGET_SG_NAME="xr_dms_sg"
REDIS_PORT=6379

# 获取Redis绑定的安全组
SG_IDS=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id "$REDIS_ID" \
    --show-cache-node-info \
    --query 'CacheClusters[0].SecurityGroups[*].SecurityGroupId' \
    --output text)

if [ -z "$SG_IDS" ] || [ "$SG_IDS" = "None" ]; then
    echo "未获取到Redis安全组"
    exit 1
fi

echo "Redis绑定安全组:"
echo "$SG_IDS"

TARGET_SG_ID=""

for SG_ID in $SG_IDS
do
    SG_NAME=$(aws ec2 describe-security-groups \
        --group-ids "$SG_ID" \
        --query 'SecurityGroups[0].GroupName' \
        --output text)

    echo "$SG_ID -> $SG_NAME"

    if [ "$SG_NAME" = "$TARGET_SG_NAME" ]; then
        TARGET_SG_ID="$SG_ID"
        break
    fi
done

# 如果不存在，则取第一个安全组
if [ -z "$TARGET_SG_ID" ]; then
    TARGET_SG_ID=$(echo "$SG_IDS" | awk '{print $1}')
    echo "未发现 $TARGET_SG_NAME"
    echo "使用第一个安全组: $TARGET_SG_ID"
else
    echo "发现目标安全组: $TARGET_SG_ID"
fi

# 添加IP
for IP in "${IPS[@]}"
do
    echo "添加: $IP"

    aws ec2 authorize-security-group-ingress \
        --group-id "$TARGET_SG_ID" \
        --protocol tcp \
        --port "$REDIS_PORT" \
        --cidr "$IP" \
        >/tmp/sg.out 2>/tmp/sg.err

    if [ $? -eq 0 ]; then
        echo "成功: $IP"
    elif grep -q "Duplicate" /tmp/sg.err; then
        echo "已存在: $IP"
    else
        echo "失败: $IP"
        cat /tmp/sg.err
    fi
done
