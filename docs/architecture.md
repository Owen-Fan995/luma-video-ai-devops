# Luma Video AI - Infrastructure Architecture

## Table of Contents

1. [Overview](#overview)
2. [Architecture Principles](#architecture-principles)
3. [System Architecture](#system-architecture)
4. [Network Architecture](#network-architecture)
5. [Compute Architecture](#compute-architecture)
6. [Data Architecture](#data-architecture)
7. [Storage Architecture](#storage-architecture)
8. [Security Architecture](#security-architecture)
9. [Monitoring and Observability](#monitoring-and-observability)
10. [Scalability and High Availability](#scalability-and-high-availability)
11. [Disaster Recovery](#disaster-recovery)
12. [Architecture Decision Records](#architecture-decision-records)

## Overview

The Luma Video AI platform is deployed on AWS using a modern, cloud-native architecture. The infrastructure is designed to handle AI-powered video processing workloads with high availability, scalability, and security.

### Key Design Goals

- **Scalability**: Handle variable workloads from 10 to 10,000+ concurrent video processing jobs
- **Reliability**: 99.9% uptime SLA with automated failover
- **Performance**: Video processing latency < 5 minutes for typical 1-hour videos
- **Security**: Enterprise-grade security with encryption at rest and in transit
- **Cost Efficiency**: Optimize resource utilization through auto-scaling and rightsizing

## Architecture Principles

### 1. Infrastructure as Code (IaC)

All infrastructure is defined and managed through Terraform:

- **Version Controlled**: All infrastructure changes tracked in Git
- **Reproducible**: Identical environments across dev/staging/prod
- **Auditable**: Complete history of infrastructure changes
- **Automated**: Infrastructure provisioned via CI/CD pipelines

### 2. Immutable Infrastructure

- EC2 instances replaced rather than modified
- Docker containers for application deployment
- Blue-green deployments for zero-downtime updates

### 3. Defense in Depth

Multiple layers of security:

- Network isolation via VPC and security groups
- IAM roles with least-privilege access
- Encryption at rest and in transit
- Web Application Firewall (WAF) for API protection

### 4. Observability First

- Comprehensive logging (CloudWatch, application logs)
- Metrics collection (Prometheus, CloudWatch)
- Distributed tracing for video processing pipelines
- Real-time alerting and monitoring

### 5. Cost Optimization

- Auto-scaling to match demand
- Spot instances for dev/staging
- S3 lifecycle policies for archival
- Reserved instances for predictable workloads

## System Architecture

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Users / API Clients                        │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ HTTPS
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Route 53 (DNS)                                  │
│                  luma-video-ai.com                                   │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    AWS WAF (Web Application Firewall)                │
│              Rate Limiting, SQL Injection Protection                 │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Application Load Balancer (ALB)                         │
│                     SSL/TLS Termination                              │
│              Health Checks, Sticky Sessions                          │
└───────────────────┬─────────────────────┬───────────────────────────┘
                    │                     │
        ┌───────────▼─────────┐  ┌────────▼──────────┐
        │   Target Group      │  │  Target Group     │
        │   Backend API       │  │  Frontend Web     │
        └───────────┬─────────┘  └────────┬──────────┘
                    │                     │
    ┌───────────────┼─────────────────────┼───────────────┐
    │               │     VPC             │               │
    │   ┌───────────▼─────────┐  ┌────────▼──────────┐   │
    │   │  Auto Scaling Group │  │ Auto Scaling Group│   │
    │   │   Backend API       │  │  Frontend Web     │   │
    │   │  (EC2 + Docker)     │  │  (EC2 + Docker)   │   │
    │   │                     │  │                   │   │
    │   │  ┌──────────────┐   │  │  ┌────────────┐  │   │
    │   │  │ EC2 Instance │   │  │  │ EC2 Instance│ │   │
    │   │  │   Backend    │   │  │  │  Frontend   │ │   │
    │   │  └──────┬───────┘   │  │  └─────────────┘ │   │
    │   │         │           │  │                   │   │
    │   │  ┌──────▼───────┐   │  │                   │   │
    │   │  │ EC2 Instance │   │  │                   │   │
    │   │  │   Backend    │   │  │                   │   │
    │   │  └──────────────┘   │  │                   │   │
    │   └─────────┬───────────┘  └───────────────────┘   │
    │             │                                       │
    │             │         ┌──────────────────┐          │
    │             └────────►│  Worker Queue    │          │
    │                       │  (SQS/Redis)     │          │
    │                       └────────┬─────────┘          │
    │                                │                    │
    │                       ┌────────▼─────────┐          │
    │                       │ Video Processing │          │
    │                       │  Worker Nodes    │          │
    │                       │  (EC2 + Docker)  │          │
    │                       └────────┬─────────┘          │
    │                                │                    │
    │    ┌───────────────────────────┼────────────┐       │
    │    │                           │            │       │
    │    ▼                           ▼            ▼       │
    │ ┌──────────┐            ┌──────────┐   ┌────────┐  │
    │ │   RDS    │            │    S3    │   │ Redis  │  │
    │ │PostgreSQL│            │  Buckets │   │ Cache  │  │
    │ │ (Multi-AZ│            │ - Videos │   │        │  │
    │ │  Primary)│            │ - Audio  │   │        │  │
    │ │          │            │ - Outputs│   │        │  │
    │ └──────┬───┘            └──────────┘   └────────┘  │
    │        │                                            │
    │        ▼                                            │
    │ ┌──────────┐                                        │
    │ │   RDS    │                                        │
    │ │PostgreSQL│                                        │
    │ │Read Replica                                       │
    │ └──────────┘                                        │
    │                                                     │
    └─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                     Monitoring & Logging                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │  CloudWatch  │  │  Prometheus  │  │   Grafana    │              │
│  │    Logs      │  │   Metrics    │  │  Dashboards  │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

#### Application Load Balancer (ALB)

- **Purpose**: Distribute incoming traffic across multiple EC2 instances
- **Features**:
  - SSL/TLS termination (HTTPS)
  - Path-based routing (/api/* → Backend, /* → Frontend)
  - Health checks every 30 seconds
  - Sticky sessions for stateful operations
  - Request/response logging

#### Backend API (Auto Scaling Group)

- **Purpose**: RESTful API for video processing, analysis, and generation
- **Technology**: Node.js/Express running in Docker containers
- **Scaling**: 2-10 instances based on CPU and request count
- **Instance Type**: c5.xlarge (4 vCPU, 8 GB RAM)
- **Responsibilities**:
  - API request handling and validation
  - Job queuing for video processing
  - Database operations
  - Webhook notifications

#### Frontend Web (Auto Scaling Group)

- **Purpose**: Admin dashboard and API documentation
- **Technology**: React/Vue.js served via Nginx in Docker
- **Scaling**: 2-4 instances
- **Instance Type**: t3.medium (2 vCPU, 4 GB RAM)
- **Responsibilities**:
  - User interface rendering
  - API explorer and documentation
  - Admin console

#### Video Processing Workers

- **Purpose**: Execute video processing jobs (transcription, segmentation, analysis)
- **Technology**: Python/FFmpeg in Docker containers
- **Scaling**: 4-20 instances based on queue depth
- **Instance Type**: c5.2xlarge (8 vCPU, 16 GB RAM) with GPU support
- **Responsibilities**:
  - Video transcoding and segmentation
  - AI model inference (OpenAI API calls)
  - Thumbnail generation
  - Subtitle generation

#### Message Queue (SQS/Redis)

- **Purpose**: Decouple API layer from video processing workers
- **Technology**: AWS SQS for job queue, Redis for result caching
- **Configuration**:
  - Message retention: 14 days
  - Visibility timeout: 1 hour (max processing time)
  - Dead letter queue for failed jobs

## Network Architecture

### VPC Configuration

```
VPC: 10.0.0.0/16 (65,536 IPs)

├── Public Subnets (Internet Gateway attached)
│   ├── us-east-1a: 10.0.1.0/24 (256 IPs) - ALB, NAT Gateway
│   ├── us-east-1b: 10.0.2.0/24 (256 IPs) - ALB, NAT Gateway
│   └── us-east-1c: 10.0.3.0/24 (256 IPs) - ALB, NAT Gateway
│
├── Private Subnets (Application Tier)
│   ├── us-east-1a: 10.0.11.0/24 (256 IPs) - EC2 Instances
│   ├── us-east-1b: 10.0.12.0/24 (256 IPs) - EC2 Instances
│   └── us-east-1c: 10.0.13.0/24 (256 IPs) - EC2 Instances
│
└── Private Subnets (Database Tier)
    ├── us-east-1a: 10.0.21.0/24 (256 IPs) - RDS, Redis
    ├── us-east-1b: 10.0.22.0/24 (256 IPs) - RDS, Redis
    └── us-east-1c: 10.0.23.0/24 (256 IPs) - RDS, Redis
```

### Security Group Rules

#### ALB Security Group

- **Inbound**:
  - Port 443 (HTTPS) from 0.0.0.0/0
  - Port 80 (HTTP) from 0.0.0.0/0 (redirect to HTTPS)
- **Outbound**:
  - All traffic to backend/frontend security groups

#### Backend API Security Group

- **Inbound**:
  - Port 3000 from ALB security group
  - Port 22 (SSH) from bastion host only
- **Outbound**:
  - Port 5432 to RDS security group
  - Port 6379 to Redis security group
  - Port 443 to 0.0.0.0/0 (external API calls)

#### RDS Security Group

- **Inbound**:
  - Port 5432 from backend API security group
  - Port 5432 from worker security group
- **Outbound**:
  - None (database doesn't initiate connections)

### Network Flow

1. **Client Request**: User → Route 53 → WAF → ALB (HTTPS)
2. **Load Balancing**: ALB → Target Group → EC2 Backend Instances
3. **Database Access**: Backend → RDS (PostgreSQL) via private subnet
4. **File Storage**: Backend → S3 via VPC Endpoint (no internet traversal)
5. **Worker Processing**: Backend → SQS → Workers → S3/RDS

## Compute Architecture

### EC2 Instance Strategy

#### Production Environment

| Service         | Instance Type | vCPU | RAM   | Count | Auto-Scaling |
|----------------|---------------|------|-------|-------|--------------|
| Backend API    | c5.xlarge     | 4    | 8 GB  | 4-10  | Yes          |
| Frontend Web   | t3.medium     | 2    | 4 GB  | 2-4   | Yes          |
| Video Workers  | c5.2xlarge    | 8    | 16 GB | 4-20  | Yes          |
| Bastion Host   | t3.micro      | 2    | 1 GB  | 1     | No           |

#### Auto-Scaling Policies

**Backend API**:
- Scale up: CPU > 70% for 5 minutes
- Scale down: CPU < 30% for 10 minutes
- Min instances: 4, Max instances: 10
- Cooldown: 300 seconds

**Video Workers**:
- Scale up: SQS queue depth > 100 messages
- Scale down: SQS queue depth < 20 messages
- Min instances: 4, Max instances: 20
- Cooldown: 600 seconds (allow time for job completion)

### Container Strategy

All applications run in Docker containers for:

- **Consistency**: Same environment across dev/staging/prod
- **Portability**: Easy migration between EC2 and ECS/EKS if needed
- **Isolation**: Application dependencies isolated from host OS
- **Version Control**: Docker images tagged with Git commit SHA

#### Docker Image Repository

- **Registry**: Amazon Elastic Container Registry (ECR)
- **Retention**: Keep last 10 images per service
- **Scanning**: Automated vulnerability scanning on push
- **Tagging Strategy**:
  - `latest`: Most recent build
  - `<git-sha>`: Specific commit (e.g., `abc123def`)
  - `v<version>`: Semantic version (e.g., `v1.2.3`)

## Data Architecture

### Database Schema Strategy

#### PostgreSQL (RDS)

**Instance Configuration** (Production):
- Instance class: db.r5.xlarge (4 vCPU, 32 GB RAM)
- Storage: 500 GB GP3 SSD (auto-scaling enabled up to 2 TB)
- Multi-AZ: Enabled (automatic failover)
- Backup retention: 30 days
- Maintenance window: Sunday 03:00-04:00 UTC

**Key Tables**:

```sql
-- API clients and authentication
api_keys (id, client_name, key_hash, rate_limit, created_at)

-- Video processing jobs
jobs (id, client_id, status, input_url, output_urls, created_at, completed_at)

-- Video segments/chapters
segments (id, job_id, start_time, end_time, title, summary, transcript)

-- Usage tracking and billing
usage_logs (id, api_key_id, endpoint, request_time, processing_time, cost)

-- Webhook configurations
webhooks (id, client_id, url, events, secret, enabled)
```

**Performance Optimization**:
- Indexes on frequently queried columns (job_id, client_id, status)
- Partitioning for large tables (usage_logs by month)
- Connection pooling (PgBouncer) for efficient connection management
- Read replicas for analytics and reporting queries

#### Redis Cache

**Use Cases**:
- API response caching (TTL: 5 minutes)
- Rate limiting counters
- Session management
- Job result caching before database write

**Configuration**:
- Instance type: cache.r5.large (2 vCPU, 13.07 GB RAM)
- Engine version: Redis 7.0
- Cluster mode: Enabled (3 shards, 1 replica each)
- Eviction policy: allkeys-lru

### Data Retention Policies

| Data Type           | Retention Period | Archive Location |
|--------------------|------------------|------------------|
| Video input files  | 90 days          | S3 Glacier       |
| Video output files | 180 days         | S3 Glacier       |
| Processing logs    | 30 days          | CloudWatch       |
| Database backups   | 30 days          | Automated RDS    |
| Audit logs         | 7 years          | S3 Glacier Deep  |

## Storage Architecture

### S3 Bucket Strategy

#### Input Videos Bucket

- **Name**: `luma-video-ai-inputs-prod`
- **Purpose**: Store uploaded video/audio files for processing
- **Lifecycle**:
  - Day 0-7: S3 Standard
  - Day 8-90: S3 Standard-IA (Infrequent Access)
  - Day 91+: Glacier Flexible Retrieval
- **Versioning**: Enabled
- **Encryption**: AES-256 (SSE-S3)

#### Output Videos Bucket

- **Name**: `luma-video-ai-outputs-prod`
- **Purpose**: Store processed video segments and generated content
- **Lifecycle**:
  - Day 0-30: S3 Standard
  - Day 31-180: S3 Standard-IA
  - Day 181+: Glacier Flexible Retrieval
- **CDN**: CloudFront distribution for fast delivery
- **Access**: Pre-signed URLs with 24-hour expiration

#### Logs Bucket

- **Name**: `luma-video-ai-logs-prod`
- **Purpose**: Store ALB logs, application logs, S3 access logs
- **Lifecycle**:
  - Day 0-30: S3 Standard
  - Day 31-365: S3 Standard-IA
  - Day 366+: Glacier Deep Archive
- **Access**: Restricted to logging service and audit team

### Content Delivery Network (CDN)

- **Service**: AWS CloudFront
- **Origin**: S3 output videos bucket
- **Edge Locations**: Global (100+ locations)
- **Caching**: 24-hour TTL for video files
- **Security**: Signed URLs required for access

## Security Architecture

### Identity and Access Management (IAM)

#### Service Roles

**EC2 Instance Role** (Backend API):
```json
{
  "Permissions": [
    "s3:PutObject (input/output buckets)",
    "s3:GetObject (input/output buckets)",
    "sqs:SendMessage (job queue)",
    "sqs:ReceiveMessage (job queue)",
    "secretsmanager:GetSecretValue (DB credentials)",
    "kms:Decrypt (for encrypted secrets)"
  ]
}
```

**EC2 Instance Role** (Video Workers):
```json
{
  "Permissions": [
    "s3:GetObject (input bucket)",
    "s3:PutObject (output bucket)",
    "sqs:ReceiveMessage (job queue)",
    "sqs:DeleteMessage (job queue)",
    "secretsmanager:GetSecretValue (API keys)"
  ]
}
```

### Encryption Strategy

#### Data at Rest

- **RDS**: AES-256 encryption enabled via AWS KMS
- **S3**: Server-side encryption (SSE-S3) for all buckets
- **EBS**: All volumes encrypted with AWS-managed keys
- **Secrets**: AWS Secrets Manager with automatic rotation

#### Data in Transit

- **External**: TLS 1.3 for all HTTPS connections (ALB)
- **Internal**: TLS 1.2 between services (API ↔ RDS, API ↔ Redis)
- **S3**: HTTPS required for all S3 API calls

### API Security

#### Authentication

- API key-based authentication (HTTP header: `X-API-Key`)
- Keys stored as bcrypt hashes in database
- Key rotation enforced every 90 days

#### Rate Limiting

- **Global**: 1,000 requests/minute per IP address
- **Per API Key**: Tiered limits (Starter: 100/min, Pro: 1,000/min, Enterprise: Custom)
- Implementation: AWS WAF + Redis counters

#### Input Validation

- File size limits: 5 GB per upload
- Allowed file types: MP4, MOV, AVI, MKV, WebM, FLV, MP3, WAV, M4A
- Malware scanning: ClamAV on upload

## Monitoring and Observability

### Metrics Collection

#### CloudWatch Metrics

**Infrastructure**:
- EC2 CPU, memory, disk utilization
- ALB request count, latency, error rates
- RDS CPU, connections, IOPS
- S3 bucket size, request count

**Application**:
- API endpoint response times
- Video processing job duration
- Queue depth and message age
- Cache hit/miss rates

#### Prometheus Metrics

**Custom Business Metrics**:
- Videos processed per hour
- Average processing time by video length
- API endpoint usage by client
- Cost per video processed

### Logging Strategy

#### Application Logs

- **Format**: JSON structured logs
- **Destination**: CloudWatch Logs → S3 (after 30 days)
- **Retention**: 30 days in CloudWatch, 1 year in S3
- **Log Levels**: ERROR, WARN, INFO, DEBUG

#### Access Logs

- **ALB Logs**: Stored in S3 logs bucket
- **S3 Access Logs**: Enabled for audit purposes
- **VPC Flow Logs**: Enabled for network traffic analysis

### Alerting

#### Critical Alerts (PagerDuty)

- API error rate > 5% for 5 minutes
- RDS CPU > 90% for 10 minutes
- Any EC2 instance unreachable for 5 minutes
- S3 upload failures > 10 in 1 minute

#### Warning Alerts (Email/Slack)

- API latency p95 > 2 seconds
- Video processing queue depth > 500
- RDS storage < 20% free space
- Cost anomaly detected (> 20% increase)

## Scalability and High Availability

### High Availability Design

- **Multi-AZ Deployment**: All services span 3 availability zones
- **Auto-Healing**: EC2 instances automatically replaced if health checks fail
- **Database Failover**: RDS Multi-AZ with automatic failover (< 60 seconds)
- **Load Balancing**: ALB distributes traffic across healthy instances only

### Scalability Targets

| Metric                    | Current Capacity | Target (6 months) | Scaling Strategy          |
|---------------------------|------------------|-------------------|---------------------------|
| Concurrent API requests   | 1,000/sec        | 10,000/sec        | Horizontal (add instances)|
| Videos processing/hour    | 500              | 5,000             | Horizontal (add workers)  |
| Storage capacity          | 10 TB            | 100 TB            | S3 auto-scaling           |
| Database connections      | 500              | 2,000             | Connection pooling + replicas |

### Performance Optimization

- **CDN**: CloudFront reduces video delivery latency to < 100ms globally
- **Caching**: Redis reduces database load by 70%
- **Database Indexing**: Query response times < 50ms for 95th percentile
- **Async Processing**: Job queue prevents API timeouts for long-running tasks

## Disaster Recovery

### Backup Strategy

#### Database Backups

- **Automated Snapshots**: Daily at 03:00 UTC
- **Retention**: 30 days
- **Cross-Region**: Weekly snapshots replicated to us-west-2
- **Point-in-Time Recovery**: Enabled (up to 30 days)

#### Application Backups

- **Docker Images**: Stored in ECR with replication to us-west-2
- **Configuration**: Terraform state in S3 with versioning enabled
- **Secrets**: AWS Secrets Manager with cross-region replication

### Recovery Procedures

#### RTO and RPO

- **Recovery Time Objective (RTO)**: 4 hours
- **Recovery Point Objective (RPO)**: 1 hour

#### Disaster Scenarios

**Scenario 1: Single EC2 Instance Failure**
- Detection: Health check fails within 30 seconds
- Action: Auto Scaling Group launches replacement instance
- Recovery Time: 5 minutes

**Scenario 2: Availability Zone Failure**
- Detection: All instances in AZ fail health checks
- Action: Traffic automatically routed to healthy AZs
- Recovery Time: < 1 minute (automatic)

**Scenario 3: RDS Database Failure**
- Detection: Database connection failures
- Action: Multi-AZ automatic failover to standby
- Recovery Time: < 60 seconds (automatic)

**Scenario 4: Region-Wide Failure**
- Detection: Manual monitoring or automated region health checks
- Action: Restore from cross-region backups to us-west-2
- Recovery Time: 4 hours (manual process)

## Architecture Decision Records

### ADR-001: Monolithic vs Microservices

**Decision**: Start with modular monolith, migrate to microservices as needed

**Rationale**:
- Simpler deployment and debugging
- Lower operational overhead
- Easier to refactor into services later
- Team size (< 10 developers) doesn't justify microservices complexity

**Status**: Accepted

### ADR-002: EC2 vs ECS/EKS

**Decision**: Use EC2 with Docker Compose for initial deployment

**Rationale**:
- Lower cost than EKS ($0.10/hour per cluster)
- Team has EC2 experience
- Sufficient for current scale (< 1,000 req/sec)
- Can migrate to EKS when scale demands it

**Status**: Accepted

### ADR-003: PostgreSQL vs DynamoDB

**Decision**: Use PostgreSQL (RDS) for primary database

**Rationale**:
- Complex relational queries (jobs, segments, relationships)
- ACID compliance required for billing data
- Team expertise with SQL
- Read replicas for analytics

**Status**: Accepted

### ADR-004: Self-Hosted vs Managed Services

**Decision**: Prefer AWS managed services (RDS, ElastiCache, S3)

**Rationale**:
- Reduced operational burden
- Built-in high availability and backups
- Better security patching
- Cost-effective at current scale

**Status**: Accepted

### ADR-005: Multi-Region vs Single-Region

**Decision**: Single region (us-east-1) with cross-region backups

**Rationale**:
- 99.9% SLA achievable with multi-AZ
- Lower cost and complexity
- Cross-region replication for disaster recovery
- Can expand to multi-region when customer demand justifies

**Status**: Accepted

## Cost Estimation

### Monthly Infrastructure Costs (Production)

| Service              | Configuration                | Monthly Cost |
|---------------------|------------------------------|--------------|
| EC2 (Backend)       | 4x c5.xlarge (reserved)      | $420         |
| EC2 (Workers)       | 4x c5.2xlarge (on-demand)    | $600         |
| EC2 (Frontend)      | 2x t3.medium (reserved)      | $60          |
| RDS PostgreSQL      | db.r5.xlarge (Multi-AZ)      | $450         |
| ElastiCache Redis   | cache.r5.large               | $150         |
| S3 Storage          | 50 TB                        | $1,150       |
| Data Transfer       | 20 TB/month                  | $1,800       |
| ALB                 | 1 ALB + LCU                  | $30          |
| CloudFront          | 10 TB/month                  | $850         |
| **Total**           |                              | **$5,510**   |

### Cost Optimization Opportunities

- Use Spot Instances for non-critical workers (save 70%)
- S3 Intelligent-Tiering (automatic cost savings)
- Reserved Instance commitments (save 30-40%)
- Compress video outputs (reduce storage and transfer costs)

## Future Enhancements

### Short-Term (3-6 months)

- Implement blue-green deployments
- Add read replicas for analytics workloads
- Implement AWS WAF custom rules
- Set up automated disaster recovery drills

### Long-Term (6-12 months)

- Migrate to Kubernetes (EKS) for better container orchestration
- Implement multi-region active-active deployment
- Add GPU instances for faster AI processing
- Implement serverless video processing (AWS Lambda + MediaConvert)

## References

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [PostgreSQL High Availability](https://www.postgresql.org/docs/current/high-availability.html)
