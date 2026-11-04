#!/usr/bin/env bash
# Creates a temporary NAT Gateway so the private subnet can reach the internet.
# Use only for build, deploy and admin sessions. Run nat-off.sh afterwards.
set -euo pipefail
PROFILE="${PROFILE:-dev-developer}"
REGION="eu-west-2"
TAGS="{Key=Project,Value=Portfolio},{Key=Env,Value=Dev},{Key=Owner,Value=Emmy}"
aws_() { aws --profile "$PROFILE" --region "$REGION" "$@"; }

EXISTING=$(aws_ ec2 describe-nat-gateways \
  --filter Name=tag:Name,Values=portfolio-nat Name=state,Values=pending,available \
  --query 'NatGateways[0].NatGatewayId' --output text)
if [ "$EXISTING" != "None" ]; then echo "NAT already exists: $EXISTING"; exit 0; fi

SUBNET=$(aws_ ec2 describe-subnets --filters Name=tag:Name,Values=portfolio-public-a \
  --query 'Subnets[0].SubnetId' --output text)
RT=$(aws_ ec2 describe-route-tables --filters Name=tag:Name,Values=portfolio-private-rt \
  --query 'RouteTables[0].RouteTableId' --output text)
if [ "$SUBNET" = "None" ] || [ "$RT" = "None" ]; then
  echo "Could not find portfolio-public-a or portfolio-private-rt. Check the Name tags."; exit 1
fi

EIP=$(aws_ ec2 allocate-address --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=portfolio-nat-eip},$TAGS]" \
  --query AllocationId --output text)
NAT=$(aws_ ec2 create-nat-gateway --subnet-id "$SUBNET" --allocation-id "$EIP" \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=portfolio-nat},$TAGS]" \
  --query NatGateway.NatGatewayId --output text)

echo "Waiting for $NAT to become available (2-3 minutes)..."
aws_ ec2 wait nat-gateway-available --nat-gateway-ids "$NAT"

aws_ ec2 create-route --route-table-id "$RT" --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$NAT" >/dev/null 2>&1 || \
aws_ ec2 replace-route --route-table-id "$RT" --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$NAT"

echo "NAT ON: $NAT. Billing has started (about \$0.053 per hour). Run nat-off.sh when finished."
