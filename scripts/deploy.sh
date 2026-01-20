#!/bin/bash
# Deployment script for Luma Video AI
# Usage: ./deploy.sh <environment> [image_tag]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-}
IMAGE_TAG=${2:-latest}
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Validate environment
if [[ -z "$ENVIRONMENT" ]]; then
  echo -e "${RED}Error: Environment not specified${NC}"
  echo "Usage: ./deploy.sh <environment> [image_tag]"
  echo "Environments: dev, staging, prod"
  exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  echo -e "${RED}Error: Invalid environment: $ENVIRONMENT${NC}"
  echo "Valid environments: dev, staging, prod"
  exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploying to: $ENVIRONMENT${NC}"
echo -e "${GREEN}Image tag: $IMAGE_TAG${NC}"
echo -e "${GREEN}========================================${NC}"

# Get EC2 instance IDs for the environment
echo -e "${YELLOW}Finding EC2 instances in $ENVIRONMENT...${NC}"
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=$ENVIRONMENT" \
            "Name=tag:Project,Values=luma-video-ai" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text \
  --region "$AWS_REGION")

if [[ -z "$INSTANCE_IDS" ]]; then
  echo -e "${RED}Error: No running instances found for environment: $ENVIRONMENT${NC}"
  exit 1
fi

echo -e "${GREEN}Found instances: $INSTANCE_IDS${NC}"

# Deploy to each instance
for INSTANCE_ID in $INSTANCE_IDS; do
  echo -e "${YELLOW}Deploying to instance: $INSTANCE_ID${NC}"

  # Send deployment command via SSM
  COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="[
      'echo \"Starting deployment...\"',
      'aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY',
      'docker pull $ECR_REGISTRY/luma-video-ai-backend:$IMAGE_TAG',
      'docker pull $ECR_REGISTRY/luma-video-ai-frontend:$IMAGE_TAG',
      'cd /opt/luma',
      'docker-compose down',
      'docker-compose up -d',
      'docker system prune -f',
      'echo \"Deployment complete\"'
    ]" \
    --output text \
    --query 'Command.CommandId' \
    --region "$AWS_REGION")

  echo -e "${GREEN}Command sent. Command ID: $COMMAND_ID${NC}"

  # Wait for command to complete
  echo -e "${YELLOW}Waiting for deployment to complete...${NC}"
  aws ssm wait command-executed \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" || true

  # Get command output
  OUTPUT=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query 'StandardOutputContent' \
    --output text \
    --region "$AWS_REGION")

  echo -e "${GREEN}Deployment output:${NC}"
  echo "$OUTPUT"
done

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment to $ENVIRONMENT completed!${NC}"
echo -e "${GREEN}========================================${NC}"

# Run health checks
echo -e "${YELLOW}Running health checks...${NC}"
./scripts/health-check.sh "$ENVIRONMENT"
