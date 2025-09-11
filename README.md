# Oh My Replicated

This repository aggregates [custom plugins](https://github.com/ohmyzsh/ohmyzsh/#custom-plugins-and-themes) for [Oh My Zsh](https://ohmyz.sh/) maintained by engineers at Replicated. These plugins provide command-line utilities for managing cloud resources efficiently.

The repository focuses on plugins that are customized for Replicated's specific workflows and are unlikely to be of wider use by the community. If a plugin becomes mature and generic enough for general use, it should be contributed back upstream instead of being maintained here.

## Plugin Standards

Each plugin follows these conventions:

- **Naming**: Prefaced with `replicated-` to avoid conflicts with other plugins
- **Focus**: Single-purpose plugins that can be independently enabled
- **Cloud-Custodian Compliance**: All resources created include required labels:
  - `owner` - User identifier for resource ownership
  - `expires-on` - Resource expiration date (YYYY-MM-DD format)
  - `managed-by=oh-my-replicated` - Management tool identifier

## Installation

### Manual Installation with Oh My Zsh

Copy (or symlink) the desired plugin to your Oh My Zsh custom plugins folder and enable it in your `~/.zshrc`:

```bash
# Copy plugin to custom folder
cp replicated-gcommands ~/.oh-my-zsh/custom/plugins/
cp replicated-awscommands ~/.oh-my-zsh/custom/plugins/
```

```zsh
# Enable plugins in ~/.zshrc
plugins=(
    replicated-gcommands
    replicated-awscommands
)
```

### Installation with Antigen

Install with the [`antigen`](https://github.com/zsh-users/antigen) plugin manager:

```bash
antigen bundle replicatedhq/oh-my-replicated@main
antigen apply
```

## AWS Commands Plugin

The `replicated-awscommands` plugin provides utilities for managing AWS EC2 instances with standardized configurations and cloud-custodian compliant labeling.

### AWS Prerequisites

- AWS CLI installed and configured ([installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- On macOS: `brew install awscli`

### AWS Configuration

Set these environment variables in your shell configuration:

```zsh
# Required: Your email username for resource ownership
AWSUSER='chriss'

# Optional: Prefix for instance names (recommended: use email username)
AWSPREFIX='chriss'
```

### AWS Available Commands

#### Instance Management

- `awslist` - List EC2 instances owned by you
- `awscreate [-d duration] <AMI_ID> <INSTANCE_TYPE> <INSTANCE_NAMES...>` - Create EC2 instances with cloud-custodian compliant labels
- `awsstart <INSTANCE_NAME_PREFIX>` - Start stopped instances
- `awsstop <INSTANCE_NAME_PREFIX>` - Stop running instances
- `awsdelete <INSTANCE_NAME_PREFIX>` - Terminate instances

#### AWS Network and Access

- `awsssh <INSTANCE_NAME>` - SSH to instance (tries common usernames: ubuntu, ec2-user, centos, fedora, admin)
- `awsssh-forward <INSTANCE_NAME>` - SSH with port forwarding (ports 8800, 8888)

#### AWS Storage Management

- `awsvolume <VOLUME_NAME> <SIZE_GB>` - Create EBS volume with proper labeling
- `awsattach <INSTANCE_NAME> <VOLUME_NAME>` - Attach volume to instance

#### AWS Utilities

- `awstag <INSTANCE_NAME> <KEY=VALUE>...` - Add tags to instance
- `awsamis [SEARCH_TERM]` - Search for AMIs (defaults to 'ubuntu')
- `awsenv` - Show current AWS profile and region

### Example Usage

```bash
# Search for Ubuntu AMIs
$ awsamis ubuntu
AWS Profile: default
AWS Region: us-west-2
Searching for AMIs containing: ubuntu
-----------------------------------------------------------
|                     DescribeImages                    |
+------------------+-----------------------------+-------+
|  ami-0abcdef123   |  ubuntu/images/hvm-ssd/... | 2023-10-15T... |
|  ami-0def456789   |  ubuntu/images/hvm-ssd/... | 2023-10-20T... |
+------------------+-----------------------------+-------+

# Create an EC2 instance (automatically includes cloud-custodian labels)
$ awscreate ami-0abcdef123 t3.medium test-server
AWS Profile: default
AWS Region: us-west-2
Creating instance: chriss-test-server
Labels applied: owner=chriss, expires-on=2025-09-18, managed-by=oh-my-replicated

# List your instances
$ awslist
AWS Profile: default
AWS Region: us-west-2
-----------------------------------------------------------
|                   DescribeInstances                   |
+---------------+------------------+---------+----------+
|  i-0123456789 | chriss-test-server| running | t3.medium|
+---------------+------------------+---------+----------+

# SSH to instance (tries multiple common usernames)
$ awsssh test-server
Trying to connect to chriss-test-server...
Connected successfully as ubuntu@54.123.45.67
```

## GCP Commands Plugin

The `replicated-gcommands` plugin provides utilities for managing Google Cloud Platform compute instances with standardized configurations and cloud-custodian compliant labeling.

### GCP Prerequisites

- Google Cloud SDK installed and configured ([installation guide](https://cloud.google.com/sdk/docs/install))
- On macOS: `brew install --cask google-cloud-sdk`
- Configure gcloud: `gcloud auth login` and `gcloud config set project PROJECT_ID`

### GCP Configuration

Set these environment variables in your shell configuration:

```zsh
# Required: Your email username for resource ownership
GUSER='chriss'

# Optional: Prefix for instance names (recommended: use email username)
GPREFIX='chriss'

# If installed via Homebrew, add gcloud to your PATH and enable completion
source "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"
source "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc"
```

### GCP Available Commands

#### GCP Instance Management

- `gcreate <IMAGE> <INSTANCE_NAMES...>` - Create GCP instances with cloud-custodian compliant labels
- `glist` - List instances owned by you
- `gstart <INSTANCE_NAME_PREFIX>` - Start stopped instances
- `gstop <INSTANCE_NAME_PREFIX>` - Stop running instances
- `gdelete <INSTANCE_NAME_PREFIX>` - Delete instances and associated disks

#### GCP Network Management

- `gssh <INSTANCE_NAME>` - SSH to instance with auto-retry
- `gssh-forward <INSTANCE_NAME>` - SSH with port forwarding (ports 8800, 8888)
- `gonline <INSTANCE_NAME>` - Add external IP access to instances
- `gairgap <INSTANCE_NAME>` - Remove external IP access (air-gap instances)

#### GCP Storage Management

- `gdisk <DISK_NAME> <SIZE_GB>` - Create persistent disks
- `gattach <INSTANCE_NAME> <DISK_NAME>` - Attach disks to instances

#### GCP Utilities

- `gtag <INSTANCE_NAME> <TAG>` - Add network tags to instances
- `genv` - Display current gcloud configuration

### Environment Management

The plugin respects gcloud [configurations](https://cloud.google.com/sdk/docs/configurations) and will not override your current configuration. It displays the active configuration context for all operations.

### Example Usage

```bash
# Check current gcloud configuration
$ genv
Configuration: default
Project: my-project
Zone: us-central1-c

# Create a GCP instance (automatically includes cloud-custodian labels)
$ gcreate ubuntu-2204-lts test-server
Configuration: default
Creating instance: chriss-test-server
Labels applied: owner=chriss, expires-on=2025-09-18, managed-by=oh-my-replicated

NAME                ZONE           MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP   STATUS
chriss-test-server  us-central1-c  n1-standard-4               10.128.0.93  34.72.173.60  RUNNING

# List your instances
$ glist
Configuration: default
NAME                ZONE           MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP   STATUS
chriss-test-server  us-central1-c  n1-standard-4               10.128.0.93  34.72.173.60  RUNNING

# SSH to instance
$ gssh test-server
Connecting to chriss-test-server...
Welcome to Ubuntu 22.04.3 LTS
```

## Testing

The repository includes a comprehensive test suite covering both plugins. Run tests to validate functionality:

```bash
# Run all tests
./tests/run_all_tests.sh

# Test specific plugin
./tests/run_all_tests.sh gcommands
./tests/run_all_tests.sh awscommands

# Run shell validation
./tests/run_shellcheck.sh
```

## Contributing

When adding new functionality:

1. Follow the established patterns for error handling and user feedback
2. Ensure cloud-custodian compliance by including required labels/tags
3. Add comprehensive tests for new functions
4. Run the full test suite before submitting changes
5. Validate shell script quality with ShellCheck

See the [test documentation](tests/README.md) for details on the testing framework.
