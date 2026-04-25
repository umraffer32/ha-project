# CLAUDE.md

## Project Overview

Terraform + Ansible lab that provisions a private AWS VPC and manages EC2 instances exclusively via AWS Systems Manager (SSM) — no SSH, no open ports, no bastion. Ansible connects over SSM using a dynamic inventory (`aws_ec2` plugin).

**Region:** `us-west-2`

## Architecture

```
Internet → IGW → Public Subnet (10.0.100.0/24) → NAT Instance (Debian 13, t2.micro)
                                                          ↕ (forwards traffic)
                                    Private Subnet (10.0.1.0/24) → SSM Hosts (Ubuntu 24.04, t2.micro × N)

Management: local machine → AWS SSM Session Manager → instances (no port 22)
Ansible:    SSM proxy connection via community.aws.aws_ssm → dynamic inventory groups
```

- NAT instance has `source_dest_check = false` and bootstraps iptables MASQUERADE via `user_data`
- Private instances have zero inbound security group rules — outbound only through NAT
- IMDSv2 enforced (`http_tokens = "required"`) on the NAT instance
- Both instance types use the `SSM-EC2` IAM instance profile (must exist in AWS before apply)

## Key Files

| File | Purpose |
|---|---|
| `compute.tf` | EC2 instances (NAT + ssm_hosts), IAM profiles, user_data bootstrap |
| `network.tf` | VPC, public/private subnets, IGW, route tables |
| `security.tf` | Security groups (NAT allows inbound from private SG; private has egress only) |
| `data.tf` | AMI lookups — Debian 13 (NAT), Ubuntu 24.04 (hosts), Amazon Linux 2023 (unused) |
| `variables.tf` | `ssm_host_count` — number of private hosts to deploy |
| `terraform.tfvars` | Variable overrides (not committed; gitignored) |
| `outputs.tf` | Prints `aws ssm start-session` commands for all instances after apply |
| `deploy.sh` | Full automated deploy: `terraform apply` → Ansible NAT config → Ansible host update |
| `wipe.sh` | `terraform destroy --auto-approve` |
| `ansible/ansible.cfg` | SSM proxy config; vault password from `~/.vault_pass.txt` |
| `ansible/aws_ec2.yml` | Dynamic inventory — groups hosts by `Role` tag (`ssm_hosts`, `ssm_nat`) |
| `ansible/plays/` | Playbooks: update, reboot, NAT config, Tailscale install, SSM check |

## Common Commands

```bash
# Deploy everything
./deploy.sh

# Manual Terraform
terraform init
terraform plan
terraform apply

# Connect to an instance (IDs printed by terraform output)
aws ssm start-session --target <instance-id>

# Verify inventory grouping
ansible-inventory -i ansible/aws_ec2.yml --graph

# Test SSM connectivity via Ansible
ansible -i ansible/aws_ec2.yml ssm_hosts -m ping

# Run a playbook
ansible-playbook ansible/plays/update.yml -l ssm_hosts

# Teardown
./wipe.sh
```

## Important Constraints

- **IAM profile `SSM-EC2` must exist in AWS** before `terraform apply` — it's referenced by name, not created here.
- **S3 bucket for SSM file transfer must be in `us-west-2`** — region mismatch breaks Ansible SSM connections.
- **Ansible Vault password** must exist at `~/.vault_pass.txt` for playbooks that use encrypted vars.
- `boto3` and `botocore` Python packages required locally for the dynamic inventory plugin.
- AWS SSM Session Manager plugin must be installed locally for `aws ssm start-session` and the Ansible SSM connection plugin.
- `hostvars_prefix: aws_` is set in `aws_ec2.yml` to avoid collision with Ansible's reserved `tags` variable — do not remove it.
- Tag `Role=ssm-hosts` on private instances is what puts them in the `ssm_hosts` inventory group, which is required for `group_vars` to apply.

## Scaling

Change host count without touching resource definitions:

```hcl
# terraform.tfvars
ssm_host_count = 5
```

## Secrets

Sensitive values (e.g., Tailscale auth key) live in `ansible/group_vars/ssm_hosts/vault.yml`, encrypted with Ansible Vault. Edit with:

```bash
ansible-vault edit ansible/group_vars/ssm_hosts/vault.yml
```
