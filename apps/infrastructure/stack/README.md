# CloudWatch Agent

The stack runs one CloudWatch Agent on every Swarm node. It collects only the
application log files mounted from the host and does not require access to the
Docker socket, `/proc`, or `/sys`.

Before the first deployment, create the `cloudwatch_credentials_base64` field
in 1Password. It must contain a single-line Base64 encoding of an AWS shared
credentials file with the `AmazonCloudWatchAgent` profile:

```ini
[AmazonCloudWatchAgent]
aws_access_key_id = ...
aws_secret_access_key = ...
```

On macOS, prepare the value without putting the credentials in the shell
command line:

```bash
base64 < ~/.aws/cloudwatch-credentials | tr -d '\\n' | pbcopy
```

The generated `setup_secrets.sh` decodes that value and creates the external
Swarm secret named `cloudwatch_credentials`.

Then deploy it from the cluster package after loading
`apps/common/setup/setup_directories.sh`:

```bash
infrastructure/management/start.sh
```

The AWS identity needs permission to create/write the `app` log group and its
streams (`logs:CreateLogGroup`, `logs:CreateLogStream`,
`logs:DescribeLogStreams`, `logs:PutLogEvents`, and `logs:PutRetentionPolicy`).
