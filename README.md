# **Jenkins Multi-Node Infrastructure on AWS**

Terraform and Ansible automation that provisions a complete Jenkins distributed build environment on AWS — a master controller and two specialised build agent nodes (Java and Python) — with all software pre-installed and ready to accept workloads.

---

## Project at a Glance

| | |
|---|---|
| **Tools Used** | Terraform >= 1.0, Ansible, AWS EC2, Jenkins, Java 17, Maven, Python 3, Amazon Linux 2023 |
| **Platform** | AWS (us-east-1, configurable) |
| **Languages** | HCL (Terraform), YAML (Ansible) |
| **What It Does** | Provisions three EC2 instances (one Jenkins master, one Java build node, one Python build node) inside a dedicated VPC, bootstraps each with the correct toolchain via Ansible, and outputs the SSH scan commands needed to register the nodes with the master |

---

## The Problem This Project Solves

A single Jenkins server running all build jobs is a scaling and reliability bottleneck. When a long-running Java build monopolises the executor, Python tests queue up waiting. When the server restarts for a plugin update, every job stops. Distributed builds solve this by separating concerns: the master handles scheduling, job configuration, and the UI, while agent nodes handle the actual compilation and testing.

Standing up that distributed environment manually is tedious. The master needs Jenkins, Java, and SSH configuration. Each node needs the right language runtime, a dedicated OS user that Jenkins can SSH into, and the correct tools for its workload. Doing this across three servers by hand means three opportunities for configuration drift and no record of what was actually installed.

This project automates the entire environment as code. A single `terraform apply` creates the VPC, provisions all three EC2 instances simultaneously, copies the appropriate Ansible playbook to each, and bootstraps them in parallel. The Java node gets Maven 3.9.11 and a `java-node` OS user. The Python node gets Python 3, pip, and a `python-node` OS user. The master gets Jenkins installed from the official signed repository, started, and configured with wheel group privileges. Terraform outputs the exact `ssh-keyscan` commands needed to register the agent nodes' private IPs in the master's known_hosts file — the final manual step before the cluster is operational.

---

## Architecture

```
Local Machine (Terraform + SSH key)
        |
        | terraform apply (parallel provisioning)
        |
        +-------------------+-------------------+
        |                   |                   |
        v                   v                   v
+---------------+   +------------------+   +-------------------+
| Jenkins Master|   | Java Agent Node  |   | Python Agent Node |
|  t3.micro     |   |  t3.micro        |   |  t3.micro         |
|  50 GB gp3    |   |  50 GB gp3       |   |  50 GB gp3        |
|               |   |                  |   |                   |
| Jenkins       |   | Java 17          |   | Python 3          |
| Java 17       |   | Maven 3.9.11     |   | pip               |
| wheel group   |   | user: java-node  |   | user: python-node |
+---------------+   +------------------+   +-------------------+
        |                   |                   |
        +-------------------+-------------------+
                            |
                  All inside: AWS VPC 10.0.0.0/16
                  Public Subnet: 10.0.1.0/24
                  Internet Gateway: attached
                  Security Group allows:
                    TCP/22    SSH
                    TCP/80    HTTP
                    TCP/8080  Jenkins UI
                    TCP/1233  Custom
                    TCP/5000  Application
```

**Node registration (post-apply manual step)**

```
# Terraform outputs these commands — run them on the Jenkins master:
ssh-keyscan -H <java_node_private_ip>   >> /var/lib/jenkins/.ssh/known_hosts
ssh-keyscan -H <python_node_private_ip> >> /var/lib/jenkins/.ssh/known_hosts
# Then register each node in Jenkins UI: Manage Jenkins -> Nodes -> New Node
```

---

## Repository Structure

```
jenkins-multi-node-infrastructure/
├── main.tf                           # Root module: provider, vpc/compute module wiring
├── variables.tf                      # Root variable: AWS region (default: us-east-1)
├── outputs.tf                        # Master URL, node IPs, ssh-keyscan commands
├── install_jenkins_master.yaml       # Ansible: Jenkins install, systemd enable, wheel group
├── install_jenkins_node_java.yaml    # Ansible: Java 17, Maven 3.9.11, java-node OS user
├── install_jenkins_node_python.yaml  # Ansible: Python 3, pip, python-node OS user
└── modules/
    ├── vpc/
    │   ├── main.tf                   # VPC, IGW, route table, subnet, security group
    │   ├── variables.tf              # Region variable
    │   └── outputs.tf               # Subnet ID, security group ID, subnet CIDR
    └── compute/
        ├── main.tf                   # Three EC2 instances with provisioners
        ├── variables.tf              # SSH keys, root volume size, subnet/SG references
        └── outputs.tf               # Public IPs, private IPs, instance IDs for all three nodes
```

---

## How It Works

**Terraform — Networking**

The VPC module creates a `10.0.0.0/16` network with DNS support and hostnames enabled. An Internet Gateway provides outbound connectivity. A public route table directs all traffic (`0.0.0.0/0`) through the gateway. A single public subnet (`10.0.1.0/24`) is created in the first available availability zone. A security group allows inbound traffic on ports 22, 80, 8080, 1233, and 5000, and permits all outbound traffic.

**Terraform — Compute**

The compute module resolves the latest Amazon Linux 2023 AMI from AWS Systems Manager Parameter Store, ensuring the build always uses a current, patched base image. Three `t3.micro` instances are launched with 50 GB gp3 root volumes. Each instance gets a public IP and the same SSH key pair for access.

Each instance uses a `file` provisioner to copy its corresponding Ansible playbook from the local machine, followed by a `remote-exec` provisioner that updates the OS, installs Ansible and Java 17, waits 60 seconds for the system to stabilise, and then runs the playbook.

**Ansible — Master**

The master playbook (`install_jenkins_master.yaml`) installs Jenkins from the official signed yum repository, enables and starts the systemd service, waits 30 seconds for Jenkins to initialize, retrieves and prints the initial admin password, and adds the `jenkins` OS user to the `wheel` group for administrative operations.

**Ansible — Java Node**

The Java node playbook (`install_jenkins_node_java.yaml`) creates a dedicated `java-node` OS user with a home directory and wheel group membership. It downloads and extracts Apache Maven 3.9.11 to `/opt`, creates a symlink at `/usr/bin/mvn`, and writes `M2_HOME` to `/etc/profile.d/maven.sh` for global availability.

**Ansible — Python Node**

The Python node playbook (`install_jenkins_node_python.yaml`) creates a `python-node` OS user, installs Python 3 and pip via yum. The node is ready to run Python-based test suites, linting tools, and deployment scripts.

---

## Walkthrough

**Terraform outputs after apply**

```
Jenkins-Master-Public-URL                       = "http://1.2.3.4:8080"
Jenkins-Node-Java-Public-IP                     = "1.2.3.5"
Jenkins-Node-Python-Public-IP                   = "1.2.3.6"
Add-Jenkins-Java-Node-Private-IP-To-Master-KnownHosts    = "ssh-keyscan -H 10.0.1.10 >>/var/lib/jenkins/.ssh/known_hosts"
Add-Jenkins-Python-Node-Private-IP-To-Master-KnownHosts  = "ssh-keyscan -H 10.0.1.11 >>/var/lib/jenkins/.ssh/known_hosts"
```

**Registering agent nodes with the master**

```bash
# SSH into the Jenkins master
ssh -i ~/.ssh/id_ed25519 ec2-user@<master-public-ip>

# Run the ssh-keyscan commands from Terraform output
sudo -u jenkins ssh-keyscan -H <java-node-private-ip> >> /var/lib/jenkins/.ssh/known_hosts
sudo -u jenkins ssh-keyscan -H <python-node-private-ip> >> /var/lib/jenkins/.ssh/known_hosts
```

**Registering a node via the Jenkins UI**

```
Jenkins Dashboard
  -> Manage Jenkins
  -> Nodes
  -> New Node
     Name:         java-node
     Type:         Permanent Agent
     Remote root:  /home/java-node
     Launch:       Launch agents via SSH
     Host:         <java-node-private-ip>
     Credentials:  (SSH key credential for ec2-user)
     Host Key:     Non verifying (known_hosts already populated)
```

---

## How to Reproduce

**Prerequisites**

- AWS CLI configured with EC2, VPC, and SSM read permissions
- Terraform >= 1.0.0 installed locally
- SSH key pair at `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub` (or update defaults in `modules/compute/variables.tf`)

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/jenkins-multi-node-infrastructure.git
cd jenkins-multi-node-infrastructure

# 2. Initialize Terraform
terraform init

# 3. Preview what will be created (3 EC2 instances, 1 VPC, 1 subnet, 1 SG, 1 IGW, 1 key pair)
terraform plan

# 4. Apply — provisions all resources and runs Ansible on each instance in parallel.
#    Expected duration: 6-10 minutes
terraform apply

# 5. Note the outputs:
#    - Open Jenkins-Master-Public-URL in a browser
#    - Use the initial admin password printed during apply
#    - Run the ssh-keyscan commands on the master to trust the agent nodes

# 6. Register the Java and Python nodes in the Jenkins UI (see Walkthrough above)

# 7. Create a pipeline job and assign it to the "java-node" or "python-node" label
#    to route builds to the appropriate executor

# 8. To tear down all resources:
terraform destroy
```

**Adjusting the root volume size**

```bash
terraform apply -var="region=us-east-1"
# Edit modules/compute/variables.tf to change root_volume_size (default: 50 GB)
```

**Verifying node connectivity from the master**

```bash
# On the master, test SSH connectivity to each agent node
sudo -u jenkins ssh -i /var/lib/jenkins/.ssh/id_rsa java-node@<java-node-private-ip>
sudo -u jenkins ssh -i /var/lib/jenkins/.ssh/id_rsa python-node@<python-node-private-ip>
```

---

*Oluwaseyi Michael Falode · Cybersecurity & Cloud Security Engineer · Toronto, ON*
