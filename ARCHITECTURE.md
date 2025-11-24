# EC2 FTP to S3 Bridge - Architecture Documentation

## Overview

This system provides an automated FTP server on AWS EC2 that accepts file uploads and automatically transfers them to S3 storage. The infrastructure is fully automated using CloudFormation and GitHub Actions for CI/CD deployment.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         GitHub Actions                           │
│  - Automated deployment pipeline                                │
│  - FTP connectivity testing                                     │
│  - CloudFormation stack management                              │
└────────────────┬────────────────────────────────────────────────┘
                 │ Deploys
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AWS CloudFormation Stack                      │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                     VPC (10.0.0.0/16)                     │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │         Public Subnet (10.0.1.0/24)                 │ │  │
│  │  │                                                       │ │  │
│  │  │  ┌─────────────────────────────────────────────┐   │ │  │
│  │  │  │         EC2 Instance (ARM64)                │   │ │  │
│  │  │  │  - Ubuntu 22.04 LTS                         │   │ │  │
│  │  │  │  - vsftpd FTP Server (Port 29720)          │   │ │  │
│  │  │  │  - Passive Ports: 21000-21100               │   │ │  │
│  │  │  │  - CloudWatch Agent                         │   │ │  │
│  │  │  │  - S3 Sync Script (Cron)                   │   │ │  │
│  │  │  │  - Optional Route53 DNS Management         │   │ │  │
│  │  │  └────────┬────────────────────────────────────┘   │ │  │
│  │  │           │                                          │ │  │
│  │  └───────────┼──────────────────────────────────────────┘ │  │
│  │              │                                            │  │
│  └──────────────┼────────────────────────────────────────────┘  │
│                 │                                                │
│  ┌──────────────▼────────────┐    ┌─────────────────────────┐  │
│  │   Security Group          │    │   IAM Instance Profile   │  │
│  │  - FTP Control: 29720     │    │  - S3 Access            │  │
│  │  - FTP Passive: 21000-    │    │  - CloudWatch Logs      │  │
│  │    21100                  │    │  - Route53 (optional)   │  │
│  └───────────────────────────┘    └─────────────────────────┘  │
│                                                                   │
└───────────────────────────────────────────────────────────────┬─┘
                                                                 │
                 ┌───────────────────────────────────────────────┤
                 │                                               │
                 ▼                                               ▼
    ┌─────────────────────────┐               ┌──────────────────────────┐
    │    Amazon S3 Bucket     │               │  Amazon Route53          │
    │  - Incoming Files       │               │  - Optional DNS A Record │
    │  - /incoming/ prefix    │               │  - Points to EC2 IP     │
    └─────────────────────────┘               └──────────────────────────┘
                 │
                 ▼
    ┌─────────────────────────┐
    │  CloudWatch Logs        │
    │  - UserData execution   │
    │  - vsftpd logs          │
    │  - S3 sync logs         │
    └─────────────────────────┘
```

## Component Details

### 1. GitHub Actions Workflow

**File**: `.github/workflows/deploy-ftp-server.yml`

**Purpose**: Automated CI/CD pipeline for infrastructure deployment and validation.

**Key Steps**:
1. **Stack Management**: Deletes existing stack to force fresh deployment with updated UserData
2. **CloudFormation Deployment**: Deploys infrastructure using parameters from GitHub secrets/variables
3. **Health Validation**: Waits for EC2 instance to be running and passes health checks
4. **FTP Testing**: Validates FTP connectivity using lftp with passive mode
5. **File Upload Test**: Creates and uploads a test file to verify end-to-end functionality
6. **S3 Verification**: Checks that files are transferred to S3 bucket

**Configuration**:
- **Trigger**: Push to main branch or manual workflow dispatch
- **Region**: us-east-2
- **Timeout**: 35 minutes
- **FTP Test Timeout**: 15 minutes

### 2. CloudFormation Template

**File**: `cloudformation-template.yaml`

**Resources Created**:

#### Networking
- **VPC**: 10.0.0.0/16 with DNS support enabled
- **Internet Gateway**: Provides internet connectivity
- **Public Subnet**: 10.0.1.0/24 with auto-assign public IP
- **Route Table**: Routes all traffic (0.0.0.0/0) through IGW

#### Security
- **Security Group**:
  - FTP Control Port: 29720 (TCP)
  - FTP Passive Ports: 21000-21100 (TCP)
  - Egress: All traffic allowed

- **IAM Role & Instance Profile**:
  - S3 permissions: PutObject, GetObject, ListBucket
  - CloudWatch: Logs creation and writing
  - Route53: DNS record management (ListResourceRecordSets, ChangeResourceRecordSets)

#### Compute
- **EC2 Instance**:
  - Type: Configurable (default: t3.micro)
  - AMI: Ubuntu 22.04 LTS ARM64 (via SSM parameter)
  - Storage: 10GB gp3 EBS volume
  - UserData: Automated setup script

#### Logging
- **CloudWatch Log Group**:
  - Name: /aws/ec2/ftp-server
  - Retention: 7 days
  - Streams: userdata, vsftpd, ftp-to-s3

### 3. EC2 Instance Configuration

**Operating System**: Ubuntu 22.04 LTS (ARM64)

**Installed Software**:
- **vsftpd**: FTP server daemon
- **awscli**: AWS command-line tools
- **CloudWatch Agent**: Log streaming to CloudWatch

**UserData Script** (runs on first boot):

1. **System Updates**:
   - Updates package lists and upgrades system packages
   - Sets non-interactive mode for automated installation

2. **Package Installation**:
   - Installs vsftpd, awscli, wget
   - Downloads and installs CloudWatch agent

3. **FTP User Setup**:
   - Creates FTP user with provided credentials
   - Sets up home directory structure: `/home/{user}/ftp/upload`
   - Configures permissions (755)

4. **vsftpd Configuration**:
   - Disables anonymous access
   - Enables local user authentication
   - Configures custom port (29720)
   - Sets up passive mode (ports 21000-21100)
   - Enables chroot jail for security
   - Configures pasv_address to EC2 public IP
   - Creates user allowlist

5. **Route53 DNS Management** (Optional):
   - Retrieves EC2 public IP
   - Checks if DNS record exists
   - Creates or updates A record using UPSERT
   - Waits for DNS propagation
   - TTL: 300 seconds

6. **CloudWatch Configuration**:
   - Sets up log collection for:
     - UserData execution logs
     - vsftpd server logs
     - S3 sync script logs

7. **S3 Sync Setup**:
   - Creates `/usr/local/bin/ftp-to-s3.sh` script
   - Finds files older than 1 minute in FTP directory
   - Uploads to S3 with `/incoming/` prefix
   - Deletes local files after successful upload
   - Logs all operations
   - Configures cron job (runs every 2 minutes)

8. **Service Management**:
   - Starts and enables vsftpd
   - Starts and enables cron
   - Creates ready marker file

### 4. FTP Server Configuration

**vsftpd Settings**:
```
anonymous_enable=NO           # Disable anonymous access
local_enable=YES              # Enable local user login
write_enable=YES              # Allow file uploads
listen_port=29720             # Custom FTP port
pasv_enable=YES               # Enable passive mode
pasv_min_port=21000          # Passive port range start
pasv_max_port=21100          # Passive port range end
chroot_local_user=YES        # Jail users to their home directory
allow_writeable_chroot=YES   # Allow writes in chroot
local_root=/home/$USER/ftp   # FTP root directory
userlist_enable=YES          # Enable user allowlist
userlist_deny=NO             # Allowlist mode (not blocklist)
```

**Directory Structure**:
```
/home/{FTP_USER}/
└── ftp/
    └── upload/        # Files uploaded here are synced to S3
```

### 5. S3 Integration

**Sync Script**: `/usr/local/bin/ftp-to-s3.sh`

**Behavior**:
- Runs every 2 minutes via cron
- Processes files older than 1 minute (prevents incomplete uploads)
- Uses AWS CLI to upload to S3
- Destination: `s3://{BUCKET_NAME}/incoming/{filename}`
- Deletes local files after successful upload
- Logs all operations to `/var/log/ftp-to-s3.log`

**Error Handling**:
- Logs failures without deleting files
- Allows retry on next cron execution

### 6. DNS Management (Optional)

**Route53 Integration**:
- Configured via `DOMAIN_NAME` and `HOSTED_ZONE_ID` parameters
- Automatically creates or updates A record
- Points domain to EC2 public IP
- TTL: 300 seconds (5 minutes)
- Uses UPSERT action for idempotency

**UserData DNS Script**:
1. Retrieves EC2 public IP from metadata service
2. Checks for existing DNS record
3. Creates JSON change batch
4. Applies change using aws route53 API
5. Waits for propagation completion

## Data Flow

### Upload Flow

1. **FTP Client Connection**:
   - Client connects to `{public-ip}:29720`
   - Authenticates with configured credentials
   - Enters chroot jail at `/home/{user}/ftp`

2. **File Upload**:
   - Client uploads file to `upload/` directory
   - File written to `/home/{user}/ftp/upload/{filename}`
   - vsftpd logs transfer to `/var/log/vsftpd.log`

3. **S3 Sync** (every 2 minutes):
   - Cron triggers `/usr/local/bin/ftp-to-s3.sh`
   - Script finds files older than 1 minute
   - Uploads to `s3://{bucket}/incoming/{filename}`
   - Deletes local file on success
   - Logs to `/var/log/ftp-to-s3.log`

4. **Monitoring**:
   - All logs streamed to CloudWatch
   - Log group: `/aws/ec2/ftp-server`
   - Separate streams for each log source

### Deployment Flow

1. **Trigger**: Developer pushes code to main branch

2. **GitHub Actions**:
   - Uploads CloudFormation template to S3
   - Deletes existing stack (forced refresh)
   - Deploys new CloudFormation stack

3. **CloudFormation**:
   - Creates VPC and networking resources
   - Launches EC2 instance
   - Applies security groups and IAM roles

4. **EC2 Initialization**:
   - UserData script executes
   - Installs and configures all services
   - Creates FTP user
   - Sets up S3 sync
   - Optionally configures DNS

5. **Validation**:
   - GitHub Actions waits for instance health
   - Tests FTP connectivity with lftp
   - Uploads test file
   - Verifies S3 transfer

6. **Completion**:
   - Displays deployment summary
   - Provides connection details

## Security Considerations

### Network Security
- EC2 instance in public subnet with minimal ports exposed
- Security group restricts access to FTP ports only
- No SSH access configured (use AWS Systems Manager Session Manager if needed)

### Authentication
- FTP password stored as GitHub secret (not in code)
- User allowlist prevents unauthorized local account access
- Chroot jail prevents directory traversal

### IAM Permissions
- Principle of least privilege
- EC2 role limited to:
  - Specific S3 bucket operations
  - CloudWatch Logs writing
  - Route53 record management (optional)

### Data Protection
- Files deleted from EC2 after successful S3 upload
- CloudWatch logs retained for 7 days
- S3 bucket should have versioning and encryption enabled (configure separately)

## Monitoring and Logging

### CloudWatch Logs

**Log Group**: `/aws/ec2/ftp-server`

**Log Streams**:
1. **userdata-{instance-id}**:
   - UserData script execution
   - System package installation
   - Service configuration
   - Startup errors

2. **vsftpd-{instance-id}**:
   - FTP connections
   - File transfers
   - Authentication attempts
   - Server errors

3. **ftp-to-s3-{instance-id}**:
   - S3 sync operations
   - Upload successes/failures
   - File deletions

### Metrics to Monitor

- **FTP Connections**: Check vsftpd logs for connection frequency
- **S3 Upload Success Rate**: Monitor ftp-to-s3 logs for failures
- **Disk Usage**: EC2 instance has 10GB storage
- **Network Traffic**: Monitor data transfer costs
- **Instance Health**: CloudWatch instance status checks

## Configuration Parameters

### Required Parameters
- **InstanceType**: EC2 instance type (default: t3.micro)
- **S3BucketName**: Target S3 bucket for file uploads
- **FTPUser**: FTP username
- **FTPPassword**: FTP password (sensitive)

### Optional Parameters
- **KeyName**: EC2 key pair name (for SSH access)
- **DomainName**: Route53 domain name to configure
- **HostedZoneId**: Route53 hosted zone ID

### GitHub Secrets Required
- `AWS_ACCESS_KEY_ID`: AWS credentials for deployment
- `AWS_SECRET_ACCESS_KEY`: AWS credentials for deployment
- `FTP_PASSWORD`: Password for FTP user

### GitHub Variables Required
- `CLOUDFORMATION_S3_BUCKET`: Bucket for CloudFormation templates
- `S3_BUCKET`: Target bucket for FTP uploads
- `FTP_USER`: FTP username
- `INSTANCE_TYPE`: EC2 instance type
- `DOMAIN_NAME`: (Optional) Domain name for Route53
- `HOSTED_ZONE_ID`: (Optional) Route53 hosted zone ID

## Deployment

### Initial Setup

1. **Create S3 Buckets**:
   ```bash
   aws s3 mb s3://{cloudformation-bucket}
   aws s3 mb s3://{upload-bucket}
   ```

2. **Configure GitHub Secrets/Variables**:
   - Add all required secrets and variables in repository settings

3. **Push to Main Branch**:
   - Workflow automatically triggers
   - Stack deploys in ~5-7 minutes

### Updates

Any push to main branch triggers:
- Full stack deletion
- Fresh deployment with updated configuration
- Automated testing

## Disaster Recovery

### Backup Strategy
- **S3 Files**: Enable versioning on S3 bucket
- **Configuration**: All infrastructure as code in Git
- **Logs**: CloudWatch logs retained for 7 days

### Recovery Procedure
1. Push code to trigger redeployment
2. CloudFormation recreates all resources
3. UserData reconfigures EC2 instance
4. Files safe in S3 bucket

### RTO/RPO
- **RTO** (Recovery Time Objective): ~5-7 minutes (deployment time)
- **RPO** (Recovery Point Objective): 0 minutes (S3 files persisted)

## Cost Estimation

**Monthly Costs** (us-east-2 region):
- EC2 t3.micro ARM: ~$6.50/month
- EBS 10GB gp3: ~$0.80/month
- S3 storage: Variable (based on usage)
- Data transfer: Variable (based on usage)
- CloudWatch Logs: ~$0.50/month (minimal usage)
- Route53 (optional): ~$0.50/month per hosted zone

**Estimated Total**: ~$8-10/month (excluding data transfer and S3 storage)

## Limitations and Considerations

1. **File Size**: No explicit limits, but consider:
   - Network transfer time
   - 2-minute sync interval
   - 10GB instance storage

2. **Concurrent Connections**: vsftpd default limits apply
   - Can be tuned in vsftpd.conf if needed

3. **Single Instance**: No high availability
   - Consider Auto Scaling Group for production

4. **Data Durability**: Files deleted after S3 upload
   - Ensure S3 bucket has versioning enabled

5. **Security**: Basic authentication only
   - Consider SFTP (SSH) for enhanced security
   - Add VPN or IP whitelisting for production

## Future Enhancements

- [ ] SFTP support for encrypted transfers
- [ ] Multi-AZ deployment for high availability
- [ ] Auto Scaling based on connection count
- [ ] CloudWatch alarms for failures
- [ ] S3 bucket encryption enforcement
- [ ] CloudTrail integration for audit logging
- [ ] Lambda function for real-time S3 processing
- [ ] SNS notifications for upload events
- [ ] Web dashboard for monitoring

## Troubleshooting

### FTP Connection Issues

**Problem**: Cannot connect to FTP server

**Diagnostics**:
```bash
# Check if port is open
nc -zv {public-ip} 29720

# Check vsftpd status in CloudWatch Logs
# Log Group: /aws/ec2/ftp-server
# Stream: vsftpd-{instance-id}
```

**Common Causes**:
- Security group not allowing traffic from your IP
- vsftpd service not running
- Passive mode port range blocked

### File Upload Issues

**Problem**: Files upload but not appearing in S3

**Diagnostics**:
```bash
# Check S3 sync logs in CloudWatch
# Log Group: /aws/ec2/ftp-server
# Stream: ftp-to-s3-{instance-id}

# Verify IAM permissions
# Check that EC2 instance role has S3 PutObject permission
```

**Common Causes**:
- IAM permission issues
- S3 bucket name mismatch
- Cron job not running
- Files too recent (< 1 minute old)

### DNS Issues

**Problem**: Route53 record not created/updated

**Diagnostics**:
```bash
# Check UserData logs in CloudWatch
# Log Group: /aws/ec2/ftp-server
# Stream: userdata-{instance-id}
# Search for "Route53" or "DNS"
```

**Common Causes**:
- DOMAIN_NAME or HOSTED_ZONE_ID not set
- IAM permission issues
- Incorrect hosted zone ID
- Domain name typo

## References

- [vsftpd Configuration Guide](https://security.appspot.com/vsftpd/vsftpd_conf.html)
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS EC2 User Data](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
- [CloudWatch Agent Configuration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html)
- [Route53 API Reference](https://docs.aws.amazon.com/Route53/latest/APIReference/)

## License

This architecture documentation is part of the ec2-ftp-s3 project.

## Maintainers

Generated by Claude Code - Automated Infrastructure Documentation
