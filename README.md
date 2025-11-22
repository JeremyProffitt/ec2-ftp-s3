# EC2 FTP to S3 Automated Deployment

Automated deployment of an EC2 instance with FTP server that uploads files to S3, with CloudWatch logging integration.

## Overview

This project deploys:
- EC2 instance in a dedicated VPC
- FTP server (vsftpd) on port 29720
- Automated file transfer from FTP to S3 (cron job)
- CloudWatch logging for FTP activity
- Security group allowing only FTP port access

## Architecture

```
User --> FTP (Port 29720) --> EC2 Instance --> S3 Bucket (incoming/)
                                    |
                                    v
                            CloudWatch Logs
```

## Prerequisites

1. AWS Account with appropriate permissions
2. S3 bucket for CloudFormation templates
3. S3 bucket for FTP file uploads
4. GitHub repository with the following secrets and variables configured

## GitHub Configuration

### Required Secrets

Set these in your GitHub repository settings (Settings > Secrets and variables > Actions):

- `AWS_ACCESS_KEY_ID` - AWS access key with permissions to create EC2, VPC, IAM, CloudFormation
- `AWS_SECRET_ACCESS_KEY` - AWS secret access key
- `FTP_PASSWORD` - Password for the FTP user

### Required Variables

Set these in your GitHub repository settings (Settings > Secrets and variables > Actions > Variables):

- `FTP_USER` - Username for FTP access
- `S3_BUCKET` - S3 bucket name where files will be uploaded
- `INSTANCE_TYPE` - EC2 instance type (e.g., t3.micro, t3.small)
- `CLOUDFORMATION_S3_BUCKET` - S3 bucket for CloudFormation template storage

## Files

- `cloudformation-template.yaml` - Infrastructure as Code template
- `.github/workflows/deploy-ftp-server.yml` - GitHub Actions workflow
- `test-ftp-upload.sh` - Manual FTP testing script

## Deployment

### Automatic Deployment

Push to the `main` branch or manually trigger the workflow:

```bash
git add .
git commit -m "Deploy FTP server"
git push origin main
```

The GitHub Action will:
1. Upload CloudFormation template to S3
2. Deploy the stack (VPC, EC2, Security Groups, IAM)
3. Wait for EC2 instance to be active (max 15 minutes)
4. Wait for FTP server to be ready (max 15 minutes)
5. Upload a test file to verify functionality

### Manual Testing

After deployment, you can test the FTP server:

```bash
chmod +x test-ftp-upload.sh
./test-ftp-upload.sh <PUBLIC_IP> <FTP_USER> <FTP_PASSWORD>
```

Or use any FTP client:

```bash
ftp -p 29720 <PUBLIC_IP>
# Login with your FTP_USER and FTP_PASSWORD
# cd upload
# put yourfile.txt
```

## How It Works

### FTP Server Setup

1. EC2 instance is launched with Amazon Linux 2023
2. UserData script installs and configures vsftpd
3. FTP user is created with credentials from GitHub secrets
4. FTP server listens on port 29720
5. Passive ports 21000-21100 are configured for data transfer

### File Transfer to S3

1. Cron job runs every 2 minutes (`/usr/local/bin/ftp-to-s3.sh`)
2. Script scans `/home/<FTP_USER>/ftp/upload` directory
3. Files older than 1 minute are uploaded to S3
4. Successful uploads result in local file deletion
5. All activity is logged to `/var/log/ftp-to-s3.log`

### CloudWatch Logging

Two log streams are created:
- `vsftpd-{instance_id}` - FTP server access logs
- `ftp-to-s3-{instance_id}` - File transfer logs

View logs:
```bash
aws logs tail /aws/ec2/ftp-server --follow
```

## Security

- Only port 29720 (FTP) and passive ports 21000-21100 are open to the internet
- No SSH access from external networks
- EC2 instance uses IAM role for S3 access (no hardcoded credentials)
- FTP users are chrooted to their home directories
- VPC provides network isolation

## Infrastructure Details

### VPC Configuration
- CIDR: 10.0.0.0/16
- Public Subnet: 10.0.1.0/24
- Internet Gateway for outbound access

### EC2 Configuration
- OS: Amazon Linux 2023
- Storage: 10GB gp3 EBS volume
- IAM Role with S3 and CloudWatch permissions

### S3 Integration
- Files are uploaded to: `s3://<S3_BUCKET>/incoming/`
- Retention policy: Managed by S3 bucket lifecycle rules

## Monitoring

### Check EC2 Instance Status

```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=FTP-Server" --query "Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]"
```

### Check CloudWatch Logs

```bash
aws logs tail /aws/ec2/ftp-server --since 1h
```

### Verify S3 Files

```bash
aws s3 ls s3://<S3_BUCKET>/incoming/
```

## Troubleshooting

### FTP Connection Issues

1. Verify security group allows port 29720
2. Check if instance is running: `aws ec2 describe-instances`
3. Check vsftpd status on instance (requires SSH access via Session Manager)
4. Review CloudWatch logs for errors

### Files Not Appearing in S3

1. Check cron job logs: `/var/log/ftp-to-s3.log`
2. Verify IAM role has S3 permissions
3. Ensure files are in the `upload` directory
4. Wait at least 2 minutes for cron job to run

### Deployment Timeout

The workflow has built-in timeouts:
- 15 minutes for EC2 to become active
- 15 minutes for FTP server to be ready
- 35 minutes total workflow timeout

If timeout occurs:
1. Check CloudFormation stack status
2. Review EC2 instance logs
3. Verify all GitHub secrets/variables are set correctly

## Cleanup

To delete all resources:

```bash
aws cloudformation delete-stack --stack-name ftp-server-stack
```

Wait for stack deletion to complete:

```bash
aws cloudformation wait stack-delete-complete --stack-name ftp-server-stack
```

## Cost Estimation

Approximate monthly costs (us-east-1):
- EC2 t3.micro: ~$7.50
- EBS 10GB gp3: ~$0.80
- CloudWatch Logs (5GB): ~$2.50
- Data Transfer: Variable
- **Total: ~$11/month** (excluding data transfer)

## License

MIT License

## Support

For issues and questions, please open an issue in the GitHub repository.
