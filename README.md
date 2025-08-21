# ChatGPT Log Buildkite Plugin

Automatically analyzes failed Buildkite job logs using OpenAI's ChatGPT and provides intelligent suggestions for fixing issues through build annotations.

## Example

Add the following to your `pipeline.yml`:

```yaml
steps:
  - label: ":hammer: Build"
    command: make build
    plugins:
      - AthreyaRay/chatgpt-logs#v1.0.0: ~

  - label: ":test_tube: Test"
    command: npm test
    plugins:
      - AthreyaRay/chatgpt-logs#v1.0.0: ~
```

## How it works

When a job fails, this plugin:

1. **Smart Log Filtering**: Extracts error patterns and context from logs (not just tail)
2. **Security Sanitization**: Removes sensitive information before sending to OpenAI
3. **Intelligent Caching**: Avoids duplicate API calls for identical failures (1-hour TTL)
4. **OpenAI Analysis**: Sends filtered logs to GPT-4o-mini for intelligent analysis
5. **Structured Annotations**: Creates build annotations with Root Cause, Fix, and Prevention tips
6. **Cleanup**: Removes temporary files and manages cache storage

## Requirements

### System Dependencies
- `curl` - for making API requests to OpenAI
- `jq` - for JSON processing

### Buildkite Agent Configuration
Your Buildkite agent **must** be started with the `--enable-job-log-tmpfile` flag:

```bash
buildkite-agent start --enable-job-log-tmpfile
```

Or in your agent configuration file:
```
enable-job-log-tmpfile=true
```

Without this flag, the plugin cannot access job logs and will fail.

### API Key
OpenAI API key stored in Buildkite secrets as `open_ai_key`

## Configuration

The plugin works with sensible defaults, but can be customized:

```yaml
steps:
  - label: ":test_tube: Test with custom config"
    command: npm test
    plugins:
      - AthreyaRay/chatgpt-logs#v1.0.0:
          model: "gpt-4o"           # Default: "gpt-4o-mini" (cheaper)
          max_tokens: 2000          # Default: 1500
          max_log_lines: 800        # Default: 600  
          timeout: 45               # Default: 30 seconds
```

### Configuration Options

- **`model`** (string): OpenAI model to use. Default: `gpt-4o-mini` (cost-effective)
- **`max_tokens`** (number): Maximum tokens for ChatGPT response. Default: `1500`
- **`max_log_lines`** (number): Maximum log lines to analyze. Default: `600`
- **`timeout`** (number): API request timeout in seconds. Default: `30`

### API Key Setup

**Option 1 - Buildkite Secrets (Recommended):**

Using Buildkite web interface:
1. Go to your organization settings
2. Navigate to "Secrets" 
3. Create a secret named `open_ai_key`
4. Set the value to your OpenAI API key (starts with `sk-`)

Using buildkite-agent CLI:
```bash
buildkite-agent secret set "open_ai_key" "sk-your-api-key-here"
```

**Option 2 - Environment Variable:**
```yaml
steps:
  - label: ":test_tube: Test"
    command: npm test
    env:
      OPENAI_API_KEY: "sk-your-api-key-here"
    plugins:
      - AthreyaRay/chatgpt-logs#v1.0.0: ~
```

## Installation

### System Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install curl jq
```

**CentOS/RHEL:**
```bash
sudo yum install curl jq
```

**macOS:**
```bash
brew install curl jq
```

**Alpine Linux (Docker):**
```bash
apk add --no-cache curl jq
```

### Agent Configuration

Ensure your Buildkite agents are configured with job log access:

**Systemd service:**
```bash
sudo systemctl edit buildkite-agent
```

Add:
```ini
[Service]
ExecStart=
ExecStart=/usr/bin/buildkite-agent start --enable-job-log-tmpfile
```

**Docker:**
```bash
docker run buildkite/agent:latest buildkite-agent start --enable-job-log-tmpfile
```

**Manual start:**
```bash
buildkite-agent start --enable-job-log-tmpfile --token="your-agent-token"
```

## Security Considerations

⚠️ **Important Privacy Notice:**
- This plugin sends the last 600 lines of your job logs to OpenAI's servers
- Ensure your logs don't contain sensitive information like passwords, API keys, or proprietary data
- Consider using log filtering or sanitization in your build scripts
- Review OpenAI's [data usage policies](https://openai.com/policies/usage-policies)

## Cost Implications

Each analysis makes an API call to OpenAI:
- Uses GPT-4o-mini by default (much cheaper than GPT-4o)
- Processes up to 600 lines of log content (configurable)
- Costs approximately $0.001-0.01 per analysis with gpt-4o-mini
- Includes smart caching to avoid duplicate API calls (1-hour TTL)
- Only triggers on failed jobs to minimize usage

Monitor your usage at [OpenAI Usage Dashboard](https://platform.openai.com/usage)

## Troubleshooting

### Common Issues

**Plugin not running:**
- Verify the agent has `--enable-job-log-tmpfile` enabled
- Check that the job actually failed (plugin only runs on failures)

**"No such file or directory" for job log:**
```bash
# Check agent configuration
buildkite-agent --help | grep job-log
```

**"Failed to parse ChatGPT suggestion":**
- Verify OpenAI API key is valid and has credits
- Check the secret name is exactly `open_ai_key`
- Ensure API key has access to GPT-4o model

**Missing dependencies:**
```bash
# Check if curl and jq are installed
which curl jq
```

**API Rate Limits:**
- Check your OpenAI plan limits
- Consider upgrading for higher rate limits
- Monitor API usage frequency

### Debug Mode

Enable verbose logging:
```yaml
steps:
  - label: ":bug: Debug Test"  
    command: |
      set -x  # Enable bash debugging
      npm test
    plugins:
      - AthreyaRay/chatgpt-logs#v1.0.0: ~
```

### Manual Testing

Test components individually:
```bash
# Test OpenAI API access
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"gpt-4o","messages":[{"role":"user","content":"test"}],"max_tokens":5}' \
     https://api.openai.com/v1/chat/completions

# Test secret access
buildkite-agent secret get "open_ai_key"

# Check agent job log support  
ls -la $BUILDKITE_JOB_LOG_TMPFILE
```

## Developing

### Running Tests

This plugin uses [Bats (Bash Automated Testing System)](https://github.com/bats-core/bats-core) for testing.

**Run all tests with Docker (recommended):**
```bash
docker-compose run --rm tests
```

**Run tests locally (requires Bats installation):**
```bash
# Install Bats test helpers
git clone https://github.com/bats-core/bats-support tests/test_helper/bats-support
git clone https://github.com/bats-core/bats-assert tests/test_helper/bats-assert

# Run tests
bats tests/
```

**Install Bats locally:**
```bash
# macOS
brew install bats-core

# Ubuntu/Debian  
sudo apt-get install bats

# Or install from source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### Test Structure

Our tests cover:
- ✅ **Success case**: Plugin skips analysis when job succeeds (exit status 0)
- ✅ **Failure case**: Plugin runs analysis when job fails (exit status != 0)  
- ✅ **Error handling**: Missing log files, API key failures, network errors
- ✅ **Cleanup**: Temporary files are properly removed
- ✅ **Mocking**: External dependencies (curl, buildkite-agent, jq) are mocked

### Manual Testing

To test the plugin manually:
```bash
# Set up test environment
export BUILDKITE_JOB_EXIT_STATUS="1"
export BUILDKITE_JOB_LOG_TMPFILE="/tmp/test.log"  
echo "Sample failed build output" > /tmp/test.log

# Run the plugin
./hooks/pre-exit
```

## Contributing

1. Fork the repo
2. Make the changes  
3. Run the tests
4. Commit and push your changes
5. Send a pull request

## License

MIT (see [LICENSE](LICENSE))