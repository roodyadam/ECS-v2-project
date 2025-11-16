# Bootstrap Stack

This stack creates the foundational infrastructure that persists across environment destroys:

- **GitHub OIDC Provider** (optional, if it doesn't already exist)
- **GitHub Deploy Role** (for CI/CD authentication)

## Purpose

These resources are separated from the main application infrastructure so that:
1. CI/CD pipelines continue to work even after `terraform destroy` in the dev environment
2. No manual steps needed after the first bootstrap deployment
3. Clean separation of concerns

## First-Time Setup

1. **Deploy the bootstrap stack:**
   ```bash
   cd infra/global/bootstrap
   terraform init
   terraform apply
   ```

2. **Get the role ARN and add it to GitHub Secrets:**
   ```bash
   terraform output github_deploy_role_arn
   ```
   - Go to GitHub repo → Settings → Secrets and variables → Actions
   - Add secret: `AWS_ROLE_ARN` = (the ARN from above)

3. **Deploy the dev environment:**
   ```bash
   cd ../../envs/dev
   terraform init
   terraform apply
   ```

## After First Setup

- The bootstrap stack should **never be destroyed**
- The dev environment can be destroyed/recreated freely
- CI/CD will always work because the role persists

## Updating Bootstrap

If you need to update the bootstrap stack (e.g., change GitHub repo):

```bash
cd infra/global/bootstrap
terraform apply
# Update GitHub secret if role ARN changed
```

## Important Notes

- The bootstrap stack uses a separate Terraform state file: `global/bootstrap/terraform.tfstate`
- The role name is: `{project_name}-github-deploy-role`
- The dev environment references this role via a data source (no direct dependency)

