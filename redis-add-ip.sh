#!/bin/bash

# =========================
# 配置区
# =========================

REDIS_ARN="$1"

if [ -z "$REDIS_ARN" ]; then
    echo "Usage:"
    echo "$0 <redis-cluster-arn>"
    exit 1
fi

REDIS_NAME=$(echo "$REDIS_ARN" | awk -F: '{print $NF}')

echo "Redis ARN  : $REDIS_ARN"
echo "Cluster ID : $REDIS_NAME"

DESC="db-"

IPS=(
    # 1.1.1.1/32
    # 2.2.2.2/32
)

PORTS=(
    6379
)

# =========================
# 获取Redis关联安全组
# =========================

CACHE_CLUSTER=$(aws elasticache describe-replication-groups \
    --replication-group-id "$REDIS_NAME" \
    --query "ReplicationGroups[0].MemberClusters[0]" \
    --output text 2>/dev/null)

if [ -n "$CACHE_CLUSTER" ] && [ "$CACHE_CLUSTER" != "None" ]; then
    REDIS_NAME="$CACHE_CLUSTER"
    echo "Detected Replication Group."
    echo "Using Member Cluster: $REDIS_NAME"
fi

SG_IDS=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id "$REDIS_NAME" \
    --query "CacheClusters[0].SecurityGroups[*].SecurityGroupId" \
    --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$SG_IDS" ] || [ "$SG_IDS" = "None" ]; then
    echo "[ERROR] Redis Cluster not found: $REDIS_NAME"
    exit 1
fi

TARGET_SGS=()

# =========================
# 遍历安全组
# =========================

for SG in $SG_IDS
do
    SG_NAME=$(aws ec2 describe-security-groups \
        --group-ids "$SG" \
        --query "SecurityGroups[0].GroupName" \
        --output text)

    echo "Found SG: $SG ($SG_NAME)"

    if [[ "$SG_NAME" == *"-db"* ]]; then
        TARGET_SGS+=("$SG")
    fi
done

# =========================
# 如果没找到-db安全组
# =========================

if [ ${#TARGET_SGS[@]} -eq 0 ]; then
    FIRST_SG=$(echo "$SG_IDS" | awk '{print $1}')
    TARGET_SGS=("$FIRST_SG")

    echo "No '-db' SG found."
    echo "Using first SG: $FIRST_SG"
fi

echo "===================================="
echo "Redis: $REDIS_NAME"
echo "Target Security Groups:"
printf '%s\n' "${TARGET_SGS[@]}"
echo "===================================="

# =========================
# 开始处理
# =========================

for SG in "${TARGET_SGS[@]}"
do
    echo
    echo "Processing Security Group: $SG"

    for PORT in "${PORTS[@]}"
    do
        for IP in "${IPS[@]}"
        do
            EXISTS=$(aws ec2 describe-security-groups \
                --group-ids "$SG" \
                --query "SecurityGroups[0].IpPermissions[?FromPort==\`$PORT\` && ToPort==\`$PORT\`].IpRanges[].CidrIp" \
                --output text | tr '\t' '\n' | grep -Fx "$IP")

            if [ -n "$EXISTS" ]; then
                echo "[SKIP] $IP Port:$PORT already exists"
                continue
            fi

            echo "[ADD ] $IP Port:$PORT"

            aws ec2 authorize-security-group-ingress \
                --group-id "$SG" \
                --ip-permissions "[
                {
                    \"IpProtocol\":\"tcp\",
                    \"FromPort\":$PORT,
                    \"ToPort\":$PORT,
                    \"IpRanges\":[
                    {
                        \"CidrIp\":\"$IP\",
                        \"Description\":\"$DESC\"
                    }
                    ]
                }
                ]"

            if [ $? -eq 0 ]; then
                echo "[ OK ] Added"
            else
                echo "[FAIL] Add Failed"
            fi
        done
    done
done

echo
echo "===================================="
echo "Finished"
echo "===================================="
