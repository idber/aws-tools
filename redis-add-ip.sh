#!/bin/bash

# =========================
# 配置区
# =========================

REDIS_NAME="$1"
echo "$REDIS_NAME"

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

SG_IDS=$(aws elasticache describe-cache-clusters \
  --cache-cluster-id "$REDIS_NAME" \
  --show-cache-node-info \
  --query "CacheClusters[0].SecurityGroups[*].SecurityGroupId" \
  --output text)

if [ -z "$SG_IDS" ]; then
    echo "Redis not found: $REDIS_NAME"
    exit 1
fi

TARGET_SGS=()

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

if [ ${#TARGET_SGS[@]} -eq 0 ]; then
    FIRST_SG=$(echo "$SG_IDS" | awk '{print $1}')
    TARGET_SGS=("$FIRST_SG")

    echo "No '-db' SG found."
    echo "Using first SG: $FIRST_SG"
fi

echo "===================================="
echo "Redis: $REDIS_NAME"
echo "===================================="

# =========================
# 开始处理
# =========================

for SG in "${TARGET_SGS[@]}"
do
    echo ""
    echo "Processing Security Group: $SG"

    for PORT in "${PORTS[@]}"
    do
        for IP in "${IPS[@]}"
        do

            EXISTS=$(aws ec2 describe-security-groups \
              --group-ids "$SG" \
              --query "SecurityGroups[0].IpPermissions[?FromPort==\`$PORT\` && ToPort==\`$PORT\`].IpRanges[].CidrIp" \
              --output text | grep -w "$IP")

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

echo ""
echo "===================================="
echo "Finished"
echo "===================================="
