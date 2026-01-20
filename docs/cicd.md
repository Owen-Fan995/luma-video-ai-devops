# Luma Video AI - CI/CD Pipeline Documentation

## Table of Contents

1. [Overview](#overview)
2. [Pipeline Architecture](#pipeline-architecture)
3. [GitHub Actions Workflows](#github-actions-workflows)
4. [Terraform Automation](#terraform-automation)
5. [Docker Build Pipeline](#docker-build-pipeline)
6. [Deployment Pipeline](#deployment-pipeline)
7. [Secrets Management](#secrets-management)
8. [Testing Strategy](#testing-strategy)
9. [Rollback Procedures](#rollback-procedures)
10. [Monitoring and Notifications](#monitoring-and-notifications)
11. [Best Practices](#best-practices)

## Overview

The CI/CD pipeline for Luma Video AI automates infrastructure provisioning, application building, testing, and deployment across multiple environments (dev, staging, production).

### Pipeline Goals

- **Automation**: Minimize manual intervention in deployment process
- **Safety**: Prevent broken code from reaching production
- **Speed**: Deploy changes to production within 30 minutes
- **Traceability**: Complete audit trail of all deployments
- **Rollback**: Quick rollback capability (< 5 minutes)

### Technology Stack

- **CI/CD Platform**: GitHub Actions
- **Infrastructure as Code**: Terraform
- **Containerization**: Docker
- **Container Registry**: Amazon ECR
- **Deployment**: Custom bash scripts + AWS CLI
- **Notifications**: Slack, Email, PagerDuty

## Pipeline Architecture

### High-Level Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Developer Workflow                           │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │  Git Push / Pull Request │
                    └────────────┬────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     GitHub Actions Triggers                          │
└─────────────────────────────────────────────────────────────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Infrastructure │  │   Application   │  │  Security &     │
│  Pipeline       │  │   Build Pipeline│  │  Quality        │
│  (Terraform)    │  │   (Docker)      │  │  Pipeline       │
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                    │
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Plan → Validate │  │ Build → Test    │  │ Lint → Scan     │
│ → Apply         │  │ → Scan → Push   │  │ → Audit         │
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                              ▼
         ┌────────────────────────────────────┐
         │      Deployment Gate               │
         │  (Manual Approval for Production)  │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │       Deploy to Environment        │
         │   Dev → Staging → Production       │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │      Post-Deployment               │
         │  Health Checks → Smoke Tests       │
         │  → Notifications                   │
         └────────────────────────────────────┘
```

### Pipeline Stages

1. **Code Quality & Security Checks** (on every PR)
   - Linting (ESLint, Prettier, Terraform fmt)
   - Unit tests
   - Security scanning (npm audit, Trivy)
   - Terraform validation

2. **Infrastructure Plan** (on PR to main)
   - Terraform plan for changed environments
   - Cost estimation
   - Plan output posted as PR comment

3. **Build & Test** (on push to main)
   - Docker image builds
   - Integration tests
   - Container vulnerability scanning

4. **Deploy to Dev** (automatic on merge to main)
   - Apply infrastructure changes
   - Deploy application containers
   - Run smoke tests

5. **Deploy to Staging** (automatic after dev success)
   - Blue-green deployment
   - Run full test suite
   - Performance tests

6. **Deploy to Production** (manual approval required)
   - Manual approval gate
   - Blue-green deployment
   - Canary release (10% → 50% → 100%)
   - Automated rollback on errors

## GitHub Actions Workflows

### Workflow Files

All workflows are located in `.github/workflows/`

#### 1. terraform-plan.yml

**Trigger**: Pull request to main branch
**Purpose**: Validate Terraform changes and show planned infrastructure modifications

```yaml
name: Terraform Plan

on:
  pull_request:
    branches: [main]
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-plan.yml'

jobs:
  plan:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [dev, staging, prod]

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Terraform Init
        working-directory: terraform/environments/${{ matrix.environment }}
        run: terraform init

      - name: Terraform Format Check
        working-directory: terraform/environments/${{ matrix.environment }}
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        working-directory: terraform/environments/${{ matrix.environment }}
        run: terraform validate

      - name: Terraform Plan
        working-directory: terraform/environments/${{ matrix.environment }}
        run: |
          terraform plan -var-file=terraform.tfvars -out=tfplan
          terraform show -no-color tfplan > plan-output.txt

      - name: Post Plan to PR
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('terraform/environments/${{ matrix.environment }}/plan-output.txt', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `### Terraform Plan - ${{ matrix.environment }}\n\`\`\`\n${plan}\n\`\`\``
            });
```

**Key Features**:
- Runs for all environments (dev, staging, prod)
- Posts plan output as PR comment for review
- Blocks merge if Terraform validation fails
- Checks formatting and syntax

#### 2. terraform-apply.yml

**Trigger**: Push to main branch (after PR merge)
**Purpose**: Apply approved infrastructure changes

```yaml
name: Terraform Apply

on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'

jobs:
  apply-dev:
    runs-on: ubuntu-latest
    environment: dev

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Terraform Init
        working-directory: terraform/environments/dev
        run: terraform init

      - name: Terraform Apply
        working-directory: terraform/environments/dev
        run: terraform apply -var-file=terraform.tfvars -auto-approve

      - name: Notify Slack
        if: always()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "Terraform Apply - Dev: ${{ job.status }}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Terraform Apply - Dev*\nStatus: ${{ job.status }}\nCommit: ${{ github.sha }}"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}

  apply-staging:
    runs-on: ubuntu-latest
    needs: apply-dev
    environment: staging
    # Similar steps for staging environment

  apply-prod:
    runs-on: ubuntu-latest
    needs: apply-staging
    environment: production
    # Similar steps with manual approval gate
```

**Key Features**:
- Sequential deployment (dev → staging → prod)
- Manual approval required for production
- Slack notifications on success/failure
- State locking prevents concurrent applies

#### 3. docker-build.yml

**Trigger**: Push to main or tags
**Purpose**: Build and push Docker images to ECR

```yaml
name: Docker Build and Push

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]

env:
  AWS_REGION: us-east-1
  ECR_REGISTRY: ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.us-east-1.amazonaws.com

jobs:
  build-backend:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.ECR_REGISTRY }}/luma-video-ai-backend
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha,prefix={{branch}}-
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./docker/backend
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.ECR_REGISTRY }}/luma-video-ai-backend:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-results.sarif'

      - name: Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-results.sarif'

  build-frontend:
    runs-on: ubuntu-latest
    # Similar steps for frontend
```

**Key Features**:
- Builds backend and frontend images in parallel
- Tags images with git SHA, branch, and semantic version
- Security scanning with Trivy
- Pushes to Amazon ECR
- Layer caching for faster builds

#### 4. deploy.yml

**Trigger**: Manual workflow dispatch or after successful docker-build
**Purpose**: Deploy application to target environment

```yaml
name: Deploy Application

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        type: choice
        options:
          - dev
          - staging
          - production
      image_tag:
        description: 'Docker image tag to deploy'
        required: true
        default: 'latest'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Deploy to EC2
        run: |
          chmod +x ./scripts/deploy.sh
          ./scripts/deploy.sh ${{ github.event.inputs.environment }} ${{ github.event.inputs.image_tag }}

      - name: Run health checks
        run: |
          chmod +x ./scripts/health-check.sh
          ./scripts/health-check.sh ${{ github.event.inputs.environment }}

      - name: Run smoke tests
        run: |
          # Run basic API tests to verify deployment
          curl -f https://api-${{ github.event.inputs.environment }}.luma-video-ai.com/health || exit 1

      - name: Notify deployment
        if: always()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "Deployment to ${{ github.event.inputs.environment }}: ${{ job.status }}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Deployment Complete*\nEnvironment: ${{ github.event.inputs.environment }}\nImage: ${{ github.event.inputs.image_tag }}\nStatus: ${{ job.status }}"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

**Key Features**:
- Manual trigger with environment selection
- Automated health checks after deployment
- Slack notifications
- Rollback on health check failure

## Terraform Automation

### State Management

**Remote State Configuration** (`terraform/backend.tf`):

```hcl
terraform {
  backend "s3" {
    bucket         = "luma-video-ai-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # State versioning for rollback capability
    versioning = true
  }
}
```

**Benefits**:
- Centralized state storage in S3
- State locking via DynamoDB (prevents concurrent modifications)
- State encryption at rest
- Versioning for rollback capability

### Terraform Workflow

#### Pull Request Workflow

1. Developer creates PR with infrastructure changes
2. `terraform-plan.yml` workflow triggers
3. Terraform validates syntax and formatting
4. `terraform plan` runs for all affected environments
5. Plan output posted as PR comment
6. Team reviews infrastructure changes
7. PR approved and merged

#### Deployment Workflow

1. PR merged to main branch
2. `terraform-apply.yml` workflow triggers
3. Changes applied to dev environment first
4. If successful, applies to staging
5. Manual approval required for production
6. On approval, applies to production
7. Slack notifications sent

### Environment-Specific Variables

Each environment has its own `terraform.tfvars`:

**Dev** (`terraform/environments/dev/terraform.tfvars`):
```hcl
environment = "dev"
instance_type = "t3.medium"
min_instances = 1
max_instances = 2
rds_instance_class = "db.t3.small"
enable_multi_az = false
```

**Production** (`terraform/environments/prod/terraform.tfvars`):
```hcl
environment = "prod"
instance_type = "c5.xlarge"
min_instances = 4
max_instances = 10
rds_instance_class = "db.r5.xlarge"
enable_multi_az = true
```

## Docker Build Pipeline

### Multi-Stage Builds

**Backend Dockerfile** optimized for size and security:

```dockerfile
# Stage 1: Build
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# Stage 2: Production
FROM node:18-alpine
RUN apk add --no-cache dumb-init
ENV NODE_ENV=production
USER node
WORKDIR /app
COPY --chown=node:node --from=builder /app/dist ./dist
COPY --chown=node:node --from=builder /app/node_modules ./node_modules
EXPOSE 3000
CMD ["dumb-init", "node", "dist/index.js"]
```

**Benefits**:
- Smaller final image (only production dependencies)
- Security: runs as non-root user
- Process management with dumb-init

### Image Tagging Strategy

| Tag Format           | Example                | Use Case                    |
|---------------------|------------------------|----------------------------|
| `latest`            | `latest`               | Latest stable build        |
| `<git-sha>`         | `abc123def`            | Specific commit tracking   |
| `<branch>-<sha>`    | `main-abc123def`       | Branch-specific builds     |
| `v<semver>`         | `v1.2.3`               | Production releases        |
| `<env>-<timestamp>` | `prod-20240120-1430`   | Environment deployments    |

### Security Scanning

**Trivy Scan** in pipeline:
- Scans for OS and application vulnerabilities
- Fails build if critical vulnerabilities found
- Uploads results to GitHub Security tab
- Generates SARIF reports for tracking

## Deployment Pipeline

### Deployment Script (`scripts/deploy.sh`)

```bash
#!/bin/bash

set -euo pipefail

ENVIRONMENT=$1
IMAGE_TAG=${2:-latest}

echo "Deploying to $ENVIRONMENT with image tag $IMAGE_TAG"

# Get EC2 instance IDs for the environment
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=$ENVIRONMENT" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

# Update each instance
for INSTANCE_ID in $INSTANCE_IDS; do
  echo "Updating instance $INSTANCE_ID"

  # SSH into instance and update containers
  aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="[
      'docker pull $ECR_REGISTRY/luma-video-ai-backend:$IMAGE_TAG',
      'docker-compose -f /opt/luma/docker-compose.yml up -d --no-deps backend',
      'docker system prune -f'
    ]" \
    --output text
done

echo "Deployment to $ENVIRONMENT complete"
```

### Blue-Green Deployment

For zero-downtime deployments to production:

1. **Blue Environment**: Current production (v1.0)
2. **Green Environment**: New version being deployed (v1.1)
3. Deploy to green environment
4. Run health checks on green
5. Switch ALB target group from blue to green
6. Monitor green for 10 minutes
7. If stable, terminate blue; if issues, switch back to blue

### Canary Deployment

For high-risk production changes:

1. Deploy new version to 10% of instances
2. Monitor metrics for 15 minutes
3. If stable, increase to 50%
4. Monitor for 15 minutes
5. If stable, deploy to 100%
6. Automatic rollback on error rate spike

## Secrets Management

### GitHub Secrets

Required secrets configured in GitHub repository settings:

```
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_ACCOUNT_ID
SLACK_WEBHOOK_URL
PAGERDUTY_API_KEY
```

### AWS Secrets Manager

Runtime secrets stored in AWS Secrets Manager:

```bash
# Database credentials
luma-video-ai/db-password

# API keys
luma-video-ai/openai-api-key

# JWT secrets
luma-video-ai/jwt-secret
```

Accessed by EC2 instances via IAM roles (no hardcoded credentials).

### Secret Rotation

- **Automated**: AWS Secrets Manager rotates DB passwords every 90 days
- **Manual**: API keys rotated on-demand via AWS CLI
- **Audit**: All secret access logged in CloudTrail

## Testing Strategy

### Test Pyramid

```
           ┌─────────────────┐
           │   E2E Tests     │  (5% - slow, expensive)
           │   (Selenium)    │
           └─────────────────┘
        ┌──────────────────────┐
        │  Integration Tests   │  (15% - moderate speed)
        │  (API tests, DB)     │
        └──────────────────────┘
   ┌────────────────────────────────┐
   │       Unit Tests               │  (80% - fast, cheap)
   │  (Jest, Mocha, PyTest)         │
   └────────────────────────────────┘
```

### Test Stages in Pipeline

#### 1. Unit Tests (Every PR)

```yaml
- name: Run unit tests
  run: |
    npm run test:unit
    npm run test:coverage
```

**Coverage Requirements**:
- Overall: > 80%
- Critical paths (auth, billing): > 95%

#### 2. Integration Tests (Merge to Main)

```yaml
- name: Run integration tests
  env:
    DATABASE_URL: ${{ secrets.TEST_DATABASE_URL }}
  run: |
    npm run test:integration
```

**Test Scope**:
- API endpoint tests
- Database operations
- External service mocks (OpenAI, S3)

#### 3. Smoke Tests (Post-Deployment)

```yaml
- name: Run smoke tests
  run: |
    curl -f https://api-$ENV.luma-video-ai.com/health
    curl -f https://api-$ENV.luma-video-ai.com/api/v1/status
```

**Test Scope**:
- API availability
- Database connectivity
- S3 access

#### 4. Performance Tests (Staging)

```yaml
- name: Run load tests
  run: |
    artillery run load-test.yml
```

**Test Criteria**:
- Latency p95 < 500ms
- Throughput > 1,000 req/sec
- Error rate < 1%

## Rollback Procedures

### Automated Rollback

Rollback triggers automatically if:
- Health checks fail after deployment
- Error rate > 5% for 5 minutes
- Latency p95 > 3 seconds for 5 minutes

### Manual Rollback

**Option 1: Rollback Script**

```bash
./scripts/rollback.sh production v1.2.3
```

**Option 2: Re-deploy Previous Version**

```bash
# Via GitHub Actions
gh workflow run deploy.yml \
  -f environment=production \
  -f image_tag=v1.2.3
```

**Option 3: Terraform Rollback**

```bash
# Revert to previous Terraform state
cd terraform/environments/prod
terraform apply -var-file=terraform.tfvars -target=module.ec2
```

### Rollback Time Targets

- **Application Rollback**: < 5 minutes
- **Infrastructure Rollback**: < 15 minutes
- **Database Rollback**: Restore from snapshot (< 30 minutes)

## Monitoring and Notifications

### Deployment Metrics

Tracked in Grafana:

- Deployment frequency (DORA metric)
- Lead time for changes (DORA metric)
- Change failure rate (DORA metric)
- Mean time to recovery (DORA metric)

### Notification Channels

#### Slack Notifications

- Deployment started
- Deployment succeeded
- Deployment failed
- Rollback initiated

#### Email Notifications

- Production deployment summary (daily)
- Failed deployment alerts
- Security scan results

#### PagerDuty Alerts

- Production deployment failures
- Critical rollback events
- Infrastructure failures

### Deployment Dashboard

Grafana dashboard showing:

- Current deployed versions per environment
- Deployment timeline (last 30 days)
- Success/failure rates
- Average deployment duration

## Best Practices

### 1. Infrastructure Changes

- Always run `terraform fmt` before committing
- Add comments explaining non-obvious resource configurations
- Use modules for reusable components
- Never commit `.tfvars` files with secrets

### 2. Docker Images

- Use specific base image tags (not `latest`)
- Run containers as non-root user
- Minimize layer count (combine RUN commands)
- Scan images before pushing to ECR
- Tag images with git commit SHA

### 3. Deployments

- Deploy to dev/staging before production
- Run smoke tests after every deployment
- Monitor metrics for 15 minutes after production deployment
- Keep previous version running during blue-green switch

### 4. Testing

- Write tests before code (TDD)
- Mock external dependencies
- Use separate test databases
- Clean up test data after tests

### 5. Secrets

- Never commit secrets to Git
- Rotate secrets every 90 days
- Use IAM roles instead of access keys when possible
- Audit secret access regularly

### 6. Rollbacks

- Keep last 5 versions deployable
- Test rollback procedures monthly
- Document rollback decision criteria
- Automate rollback for known failure patterns

## Troubleshooting

### Common Pipeline Issues

#### Issue: Terraform State Lock

```bash
# Error: Error acquiring the state lock
# Solution: Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

#### Issue: Docker Build Timeout

```bash
# Solution: Increase timeout in workflow
timeout-minutes: 30
```

#### Issue: ECR Push Failed

```bash
# Solution: Re-authenticate to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_REGISTRY
```

#### Issue: Deployment Health Check Failed

```bash
# Check instance logs
aws logs tail /aws/ec2/luma-video-ai --follow

# Check application logs
ssh ec2-instance "docker logs backend-container"
```

## Continuous Improvement

### Metrics to Track

- **Deployment Frequency**: Target 10+ per week
- **Lead Time**: Target < 1 hour (commit to production)
- **Change Failure Rate**: Target < 15%
- **MTTR**: Target < 1 hour

### Future Enhancements

- Implement feature flags for gradual rollouts
- Add automated performance regression testing
- Implement chaos engineering (randomly kill instances)
- Add deployment approval workflows via Slack
- Implement GitOps with ArgoCD or Flux

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [Docker Security Best Practices](https://docs.docker.com/develop/security-best-practices/)
- [AWS DevOps Best Practices](https://aws.amazon.com/devops/)
- [DORA Metrics](https://cloud.google.com/blog/products/devops-sre/using-the-four-keys-to-measure-your-devops-performance)
