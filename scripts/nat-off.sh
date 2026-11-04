#!/usr/bin/env bash
# Removes the NAT route, deletes the NAT Gateway and releases its Elastic IP.
set -euo pipefail
PROFILE="${PROFILE:-dev-developer}"
REGION="eu-west-2"
aws_() { aws --profile "$PROFILE" --region "$REGION" "$@"; }

RT=$(aws_ ec2 describe-route-tables --filters Name=tag:Name,Values=portfolio-private-rt \
  --query 'RouteTables[0].RouteTableId' --output text)
aws_ ec2 delete-route --route-table-id "$RT" --destination-cidr-block 0.0.0.0/0 2>/dev/null \
  && echo "Removed 0.0.0.0/0 route from $RT" || echo "No NAT route to remove"

NAT=$(aws_ ec2 describe-nat-gateways \
  --filter Name=tag:Name,Values=portfolio-nat Name=state,Values=pending,available \
  --query 'NatGateways[0].NatGatewayId' --output text)
if [ "$NAT" != "None" ]; then
  aws_ ec2 delete-nat-gateway --nat-gateway-id "$NAT" >/dev/null
  echo "Deleting $NAT (about 1 minute)..."
  until [ "$(aws_ ec2 describe-nat-gateways --nat-gateway-ids "$NAT" \
           --query 'NatGateways[0].State' --output text)" = "deleted" ]; do sleep 15; done
fi

for EIP in $(aws_ ec2 describe-addresses --filters Name=tag:Name,Values=portfolio-nat-eip \
               --query 'Addresses[].AllocationId' --output text); do
  for i in 1 2 3 4 5 6; do
    aws_ ec2 release-address --allocation-id "$EIP" 2>/dev/null && { echo "Released $EIP"; break; }
    sleep 10
  done
done

echo "NAT OFF. The private subnet has no internet route."
