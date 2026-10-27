# CI/CD Pipeline Demo (deployed on Microsoft Azure)

A small Node.js (Express) service with a complete CI/CD pipeline built on GitHub Actions.
Every push to `main` is tested, packaged as a Docker image, pushed to GitHub Container
Registry (GHCR), deployed to an **Azure Linux VM** over SSH, health-checked, and
**automatically rolled back** if the new version fails.

## Pipeline

```
push to main
   |
   v
[1] Lint & Test (ESLint + Jest)        <- also runs on every pull request
   |
   v
[2] Build Docker image -> push to GHCR (tags: <commit-sha> and latest)
   |
   v
[3] Deploy to Azure VM over SSH
      - pull image on the VM
      - replace the running container
      - wait for Docker health status
      - unhealthy? -> roll back to the previous image and fail the run
   |
   v
[4] Verify live version == deployed commit (optional)   +   Discord alert on failure (optional)
```

**Tech stack:** Node.js, Express, Jest, ESLint, Docker, GitHub Actions, GHCR, SSH, Bash,
Microsoft Azure (Virtual Machine, Network Security Group, Azure CLI).

## Project structure

```
.github/workflows/ci-cd.yml   the pipeline
deploy/deploy.sh              runs on the VM: deploy, health check, rollback
src/app.js, src/server.js     the application
tests/app.test.js             unit/API tests
Dockerfile                    multi-stage build, non-root user, HEALTHCHECK
```

## Run locally

```bash
npm install
npm run lint
npm test
npm start            # http://localhost:3000  (/health, /api/info)
```

## One-time setup

### A. SSH key (run on your Windows machine in Git Bash)

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ./deploy_key -N ""
```

This creates `deploy_key` (private, goes into GitHub) and `deploy_key.pub` (public, goes on
the VM). Never commit the private key, and delete the local copy once it is in GitHub.

### B. Create the Azure VM

You need an Azure account (a free account works) and the Azure CLI
(`winget install Microsoft.AzureCLI`, then reopen Git Bash).

```bash
az login

# Resource group = one folder for everything, so you can delete it all at once later
az group create --name rg-cicd-demo --location centralindia

# Ubuntu VM. The public key from step A is installed for the user "deploy".
az vm create \
  --resource-group rg-cicd-demo \
  --name vm-cicd-demo \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username deploy \
  --ssh-key-values ./deploy_key.pub \
  --public-ip-sku Standard

# Open the app port (SSH port 22 is already open)
az vm open-port --resource-group rg-cicd-demo --name vm-cicd-demo --port 8080 --priority 1010
```

The output of `az vm create` contains `publicIpAddress` - this is your `SSH_HOST`.
(Get it again anytime with
`az vm show -d -g rg-cicd-demo -n vm-cicd-demo --query publicIps -o tsv`.)

> If `Standard_B1s` is not available in your region/subscription, run
> `az vm list-skus --location centralindia --size Standard_B --output table`
> and pick another small size, or change the region.
> Prefer the portal? Create an Ubuntu 22.04 VM with SSH public key authentication,
> username `deploy`, paste the content of `deploy_key.pub`, and add an inbound
> port rule for TCP 8080 in the VM's Networking tab.

### C. Install Docker on the VM

```bash
ssh -i ./deploy_key deploy@YOUR_VM_IP

# inside the VM:
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker deploy
exit
```

Log in again (so the group change applies) and test - this must work without `sudo`:

```bash
ssh -i ./deploy_key deploy@YOUR_VM_IP "docker ps"
```

### D. GitHub repository

1. Create a new repository and push this project to the `main` branch:
   ```bash
   git init -b main
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/YOUR_USER/cicd-pipeline.git
   git push -u origin main
   ```
2. **Settings -> Actions -> General -> Workflow permissions** -> select
   *Read and write permissions* (needed to push the image to GHCR).
3. **Settings -> Secrets and variables -> Actions -> Secrets** -> add:

   | Secret | Value |
   |---|---|
   | `SSH_HOST` | the VM's public IP |
   | `SSH_USER` | `deploy` |
   | `SSH_PRIVATE_KEY` | full content of `deploy_key` (including the BEGIN/END lines) |
   | `SSH_PORT` | optional, default `22` |
   | `DISCORD_WEBHOOK_URL` | optional, for failure alerts |

4. **Variables** tab (optional):

   | Variable | Value |
   |---|---|
   | `APP_PORT` | host port, default `8080` |
   | `HEALTH_URL` | `http://YOUR_VM_IP:8080/health` to verify the live version |

5. Push a commit (or run the workflow manually from the **Actions** tab). Then open
   `http://YOUR_VM_IP:8080` - the page shows the deployed commit SHA.

## Demonstrate the automatic rollback

1. Make sure a good version is deployed.
2. Break the app on purpose, e.g. add `process.exit(1);` as the first line of `src/server.js`
   (tests still pass because they import `app.js`).
3. Push. The deploy job starts the new container, sees it is not healthy, restores the
   previous image, and fails the run. The site stays online on the old version.
4. Revert the change and push again.

## Azure cost control (important)

- Stop paying for compute when you are not using the VM:
  `az vm deallocate -g rg-cicd-demo -n vm-cicd-demo` (start again with `az vm start ...`).
- Check that the public IP is **Static** (the command above creates a Standard SKU IP, which is
  static). If the IP ever changes, update the `SSH_HOST` secret.
- Set a budget alert in **Azure Portal -> Cost Management + Billing -> Budgets**.
- When the project is done, delete everything in one command:
  `az group delete --name rg-cicd-demo --yes --no-wait`

## Notes

- `deploy.sh` is streamed over SSH, so nothing but Docker has to exist on the VM. The same
  pipeline works on any Linux server (Azure VM, AWS EC2, a VPS).
- The GHCR login on the VM uses the short-lived `GITHUB_TOKEN` of the workflow run -
  no personal access token is stored anywhere.
- The swap takes a few seconds of downtime. Zero-downtime (blue/green behind Nginx) would be
  a good next improvement.
- Old images stay on the VM for rollback. Clean up occasionally with
  `docker image prune -a` (only removes images not used by a container).
- Possible next step: replace GHCR with Azure Container Registry (ACR).

## Troubleshooting

| Problem | Fix |
|---|---|
| `denied: permission_denied` pushing the image | Enable *Read and write permissions* (step D2) |
| `pull access denied` on the VM | Package must be linked to this repo; keep the `source` label in the workflow and don't rename the repo mid-way |
| `Permission denied (publickey)` | Wrong key in `SSH_PRIVATE_KEY`, or the VM was created with a different public key |
| `permission denied ... docker.sock` | Run `sudo usermod -aG docker deploy`, then log in again |
| Deploy OK but site not reachable | The NSG rule for 8080 is missing - run the `az vm open-port` command or add the rule in the portal |
| SSH times out | Wrong IP (it may have changed), or the VM is deallocated - start it with `az vm start` |
| `port is already allocated` | Set a different `APP_PORT` variable |
