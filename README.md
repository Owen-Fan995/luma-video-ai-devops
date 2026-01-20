# Luma Video AI - DevOps Infrastructure

This repository contains the complete infrastructure-as-code (IaC) and CI/CD pipeline configuration for the Luma Video AI platform.

## Overview

Luma Video AI is an AI-powered video intelligence API platform. This DevOps repository manages:

- **Infrastructure**: AWS resources provisioned via Terraform
- **CI/CD**: Automated build, test, and deployment pipelines
- **Containerization**: Docker images for all services
- **Monitoring**: Prometheus and Grafana configurations
- **Deployment Scripts**: Automated deployment and rollback procedures

## Architecture

The platform is deployed on AWS using the following architecture:

- **Compute**: EC2 instances running Dockerized services
- **Database**: RDS PostgreSQL for persistent data
- **Storage**: S3 buckets for video/audio file storage
- **Networking**: VPC with public/private subnets across multiple AZs
- **Load Balancing**: Application Load Balancer for traffic distribution
- **Monitoring**: CloudWatch, Prometheus, and Grafana

For detailed architecture diagrams and decisions, see [docs/architecture.md](docs/architecture.md).

## Repository Structure

```
luma-video-ai-devops/
├── .github/
│   └── workflows/              # GitHub Actions CI/CD pipelines
│       ├── terraform-plan.yml  # Terraform plan on PR
│       ├── terraform-apply.yml # Terraform apply on merge
│       └── docker-build.yml    # Docker image build and push
│
├── terraform/
│   ├── environments/           # Environment-specific configurations
│   │   ├── dev/               # Development environment
│   │   ├── staging/           # Staging environment
│   │   └── prod/              # Production environment
│   │
│   ├── modules/               # Reusable Terraform modules
│   │   ├── vpc/              # VPC and networking resources
│   │   ├── ec2/              # EC2 instances and auto-scaling
│   │   ├── rds/              # RDS database instances
│   │   └── s3/               # S3 buckets and policies
│   │
│   └── backend.tf            # Terraform remote state configuration
│
├── docker/
│   ├── backend/
│   │   └── Dockerfile        # Backend API container
│   ├── frontend/
│   │   └── Dockerfile        # Frontend application container
│   └── docker-compose.yml    # Local development setup
│
├── scripts/
│   ├── deploy.sh             # Deployment automation script
│   ├── rollback.sh           # Rollback to previous version
│   └── health-check.sh       # Service health verification
│
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml    # Prometheus configuration
│   └── grafana/
│       └── dashboards/       # Grafana dashboard definitions
│
└── docs/
    ├── architecture.md       # Architecture documentation
    ├── cicd.md              # CI/CD pipeline documentation
    ├── deployment.md        # Deployment procedures
    └── runbook.md           # Operations runbook
```

## Prerequisites

### Required Tools

- **Terraform** >= 1.6.0
- **AWS CLI** >= 2.13.0
- **Docker** >= 24.0.0
- **Git** >= 2.40.0

### AWS Account Setup

1. Create an AWS account with appropriate permissions
2. Configure AWS CLI credentials:
   ```bash
   aws configure
   ```
3. Set up an S3 bucket for Terraform state:
   ```bash
   aws s3 mb s3://luma-video-ai-terraform-state
   ```

### Environment Variables

Create a `.env` file in the root directory (not committed to version control):

```bash
# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=your-account-id

# Terraform Backend
TF_STATE_BUCKET=luma-video-ai-terraform-state
TF_STATE_KEY=infrastructure/terraform.tfstate

# Docker Registry
DOCKER_REGISTRY=your-account-id.dkr.ecr.us-east-1.amazonaws.com

# Secrets
DB_PASSWORD=your-secure-password
JWT_SECRET=your-jwt-secret
OPENAI_API_KEY=your-openai-key
```

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/luma-video-ai-devops.git
cd luma-video-ai-devops
```

### 2. Initialize Terraform

```bash
cd terraform/environments/dev
terraform init
```

### 3. Plan Infrastructure Changes

```bash
terraform plan -var-file=terraform.tfvars
```

### 4. Apply Infrastructure

```bash
terraform apply -var-file=terraform.tfvars
```

### 5. Build and Push Docker Images

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $DOCKER_REGISTRY

# Build and push backend
cd docker/backend
docker build -t luma-video-ai-backend:latest .
docker tag luma-video-ai-backend:latest $DOCKER_REGISTRY/luma-video-ai-backend:latest
docker push $DOCKER_REGISTRY/luma-video-ai-backend:latest

# Build and push frontend
cd ../frontend
docker build -t luma-video-ai-frontend:latest .
docker tag luma-video-ai-frontend:latest $DOCKER_REGISTRY/luma-video-ai-frontend:latest
docker push $DOCKER_REGISTRY/luma-video-ai-frontend:latest
```

### 6. Deploy Application

```bash
./scripts/deploy.sh dev
```

## Infrastructure Environments

### Development

- **Purpose**: Development and testing
- **Resources**: Minimal instance sizes (t3.medium)
- **Database**: Single RDS instance
- **Auto-scaling**: Disabled
- **Cost**: ~$200/month

### Staging

- **Purpose**: Pre-production testing and QA
- **Resources**: Production-like sizing (t3.large)
- **Database**: Single RDS instance with automated backups
- **Auto-scaling**: Enabled (2-4 instances)
- **Cost**: ~$500/month

### Production

- **Purpose**: Live customer-facing environment
- **Resources**: Optimized for performance (c5.xlarge)
- **Database**: Multi-AZ RDS with read replicas
- **Auto-scaling**: Enabled (4-10 instances)
- **Monitoring**: Enhanced monitoring enabled
- **Backups**: Automated daily backups with 30-day retention
- **Cost**: ~$1,500/month

## CI/CD Pipeline

The CI/CD pipeline is implemented using GitHub Actions:

### 1. Terraform Plan (Pull Request)

- Triggered on PR creation/update
- Runs `terraform plan` for affected environment
- Posts plan output as PR comment
- Validates Terraform syntax and formatting

### 2. Terraform Apply (Merge to Main)

- Triggered on merge to main branch
- Applies infrastructure changes to target environment
- Updates Terraform state in S3
- Sends deployment notifications

### 3. Docker Build (Push to Main/Tags)

- Builds Docker images for backend and frontend
- Runs security scanning on images
- Pushes images to Amazon ECR
- Tags images with git commit SHA and version

### 4. Application Deployment (Manual/Automated)

- Pulls latest Docker images from ECR
- Updates EC2 instances with new containers
- Performs rolling deployment with health checks
- Automatic rollback on failure

For detailed pipeline documentation, see [docs/cicd.md](docs/cicd.md).

## Deployment Procedures

### Standard Deployment

```bash
# Deploy to development
./scripts/deploy.sh dev

# Deploy to staging
./scripts/deploy.sh staging

# Deploy to production (requires approval)
./scripts/deploy.sh prod
```

### Rollback Procedure

```bash
# Rollback to previous version
./scripts/rollback.sh prod

# Rollback to specific version
./scripts/rollback.sh prod v1.2.3
```

### Health Check

```bash
# Check service health
./scripts/health-check.sh prod
```

## Monitoring and Observability

### Prometheus Metrics

- Application metrics (request rate, latency, errors)
- System metrics (CPU, memory, disk usage)
- Custom business metrics (videos processed, API calls)

### Grafana Dashboards

- **System Overview**: Infrastructure health and resource utilization
- **Application Performance**: API latency, throughput, error rates
- **Business Metrics**: Video processing statistics, user activity

### CloudWatch Alarms

- EC2 instance health
- RDS database performance
- S3 bucket access patterns
- Application error rates

Access Grafana: `https://grafana.luma-video-ai.com`

## Security

### Best Practices

- **Secrets Management**: AWS Secrets Manager for sensitive data
- **Network Security**: VPC with private subnets for databases
- **Access Control**: IAM roles with least-privilege principle
- **Encryption**: Data encrypted at rest (EBS, RDS, S3) and in transit (TLS)
- **Vulnerability Scanning**: Automated Docker image scanning
- **Compliance**: Regular security audits and penetration testing

### Secret Rotation

Secrets are automatically rotated every 90 days. Manual rotation:

```bash
aws secretsmanager rotate-secret --secret-id luma-video-ai/db-password
```

## Cost Optimization

### Strategies Implemented

- **Auto-scaling**: Scale down during off-peak hours
- **Spot Instances**: Use for non-critical workloads (dev/staging)
- **Reserved Instances**: 1-year commitment for production RDS
- **S3 Lifecycle Policies**: Move old videos to Glacier after 90 days
- **Right-sizing**: Regular review of instance types

### Cost Monitoring

```bash
# View monthly costs by service
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY --metrics BlendedCost --group-by Type=SERVICE
```

## Disaster Recovery

### Backup Strategy

- **Database**: Automated daily snapshots with 30-day retention
- **Application Data**: Continuous S3 replication to secondary region
- **Configuration**: Infrastructure-as-code in version control

### Recovery Procedures

- **RTO** (Recovery Time Objective): 4 hours
- **RPO** (Recovery Point Objective): 1 hour

See [docs/runbook.md](docs/runbook.md) for detailed recovery procedures.

## Troubleshooting

### Common Issues

#### Terraform State Lock

```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

#### Docker Build Failures

```bash
# Clear Docker cache
docker system prune -a

# Rebuild without cache
docker build --no-cache -t image:tag .
```

#### EC2 Instance Not Responding

```bash
# Check instance status
aws ec2 describe-instance-status --instance-ids i-1234567890abcdef0

# View system logs
aws ec2 get-console-output --instance-id i-1234567890abcdef0
```

## Contributing

### Infrastructure Changes

1. Create a feature branch: `git checkout -b feature/new-infrastructure`
2. Make changes to Terraform files
3. Run `terraform fmt` and `terraform validate`
4. Create a PR with detailed description
5. Wait for `terraform plan` to complete
6. Get approval from DevOps team
7. Merge to main to apply changes

### Pipeline Changes

1. Test GitHub Actions workflows locally using `act`
2. Create PR with workflow changes
3. Test in development environment first
4. Document changes in [docs/cicd.md](docs/cicd.md)

## Support

### Documentation

- [Architecture Guide](docs/architecture.md)
- [CI/CD Documentation](docs/cicd.md)
- [Deployment Guide](docs/deployment.md)
- [Operations Runbook](docs/runbook.md)

### Contact

- **DevOps Team**: devops@luma-video-ai.com
- **On-Call**: Use PagerDuty for urgent issues
- **Slack**: #devops-support

## License

This infrastructure repository is proprietary and confidential.

## Changelog

### v1.0.0 (2024-01-20)

- Initial infrastructure setup
- Terraform modules for VPC, EC2, RDS, S3
- GitHub Actions CI/CD pipelines
- Docker containerization
- Prometheus and Grafana monitoring
- Deployment automation scripts
