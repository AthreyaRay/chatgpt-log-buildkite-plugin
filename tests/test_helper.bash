#!/bin/bash

# Test helper functions for the ChatGPT Log Buildkite Plugin tests
# This file contains common utilities and setup functions used across multiple test files

# Function to set up a mock OpenAI API server response
# Usage: mock_openai_success "Your suggestion text here"
mock_openai_success() {
  local suggestion="${1:-Default ChatGPT suggestion}"
  
  # Create a mock curl function that returns a valid OpenAI API response
  function curl() {
    cat << EOF
{
  "choices": [
    {
      "message": {
        "content": "${suggestion}"
      }
    }
  ]
}
EOF
  }
  export -f curl
}

# Function to mock a failed OpenAI API call
# Usage: mock_openai_failure
mock_openai_failure() {
  function curl() {
    # Return an error response or empty response
    echo '{"error": {"message": "API key invalid"}}'
    return 1
  }
  export -f curl
}

# Function to mock buildkite-agent commands
# Usage: mock_buildkite_agent_success "sk-your-api-key"
mock_buildkite_agent_success() {
  local api_key="${1:-sk-test-key-12345}"
  
  function buildkite-agent() {
    case "$1" in
      "secret")
        if [[ "$2" == "get" && "$3" == "open_ai_key" ]]; then
          echo "$api_key"
          return 0
        fi
        ;;
      "annotate")
        # Mock annotation - just consume the input
        cat > /dev/null
        echo "Annotation added successfully" >&2
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f buildkite-agent
}

# Function to mock buildkite-agent failure (e.g., missing secret)
mock_buildkite_agent_failure() {
  function buildkite-agent() {
    case "$1" in
      "secret")
        echo "Error: Secret 'open_ai_key' not found" >&2
        return 1
        ;;
      "annotate")
        echo "Error: Failed to create annotation" >&2
        return 1
        ;;
      *)
        return 1
        ;;
    esac
  }
  export -f buildkite-agent
}

# Function to mock jq command for JSON processing
# This is essential since our plugin heavily relies on jq
mock_jq() {
  function jq() {
    case "$1" in
      "-Rs")
        # When escaping content for JSON, add quotes and escape
        sed 's/"/\\"/g' | sed 's/^/"/' | sed 's/$/"/'
        ;;
      "-er")
        # When extracting content from OpenAI response
        if [[ "$2" == '.choices[0].message.content // empty' ]]; then
          # Extract the content from our mock JSON response
          grep -o '"content": *"[^"]*"' | sed 's/"content": *"//' | sed 's/"$//'
        else
          # Default jq behavior for other patterns
          echo "mock-jq-output"
        fi
        ;;
      *)
        # For other jq operations, try to use real jq if available
        if command -v jq >/dev/null 2>&1; then
          command jq "$@"
        else
          # If jq is not available, return a mock response
          echo "mock-jq-response"
        fi
        ;;
    esac
  }
  export -f jq
}

# Function to create a sample log file with realistic content
# Usage: create_sample_log_file "/path/to/log/file" [success|failure]
create_sample_log_file() {
  local log_file="$1"
  local job_type="${2:-failure}"
  
  if [[ "$job_type" == "success" ]]; then
    cat > "$log_file" << 'EOF'
--- Running build command
npm install
added 1250 packages in 45.2s
npm test
> my-project@1.0.0 test
> jest
 PASS  src/utils.test.js
 PASS  src/app.test.js
Test Suites: 2 passed, 2 total
Tests:       15 passed, 15 total
Snapshots:   0 total
Time:        3.852s
Build completed successfully
EOF
  else
    cat > "$log_file" << 'EOF'
--- Running build command
npm install
added 1250 packages in 45.2s
npm test
> my-project@1.0.0 test
> jest
 FAIL  src/app.test.js
  ● App › should render correctly
    TypeError: Cannot read property 'map' of undefined
      at App.render (src/App.js:25:15)
      at Object.<anonymous> (src/app.test.js:10:21)
Test Suites: 1 failed, 1 passed, 2 total
Tests:       1 failed, 14 passed, 15 total
Snapshots:   0 total
Time:        4.123s
npm ERR! Test failed.  See above for more details.
Build failed with exit code 1
EOF
  fi
}

# Function to verify that all required environment variables are set
verify_test_environment() {
  local missing_vars=()
  
  # Check for required environment variables
  [[ -z "$BUILDKITE_JOB_LOG_TMPFILE" ]] && missing_vars+=("BUILDKITE_JOB_LOG_TMPFILE")
  [[ -z "$BUILDKITE_JOB_EXIT_STATUS" ]] && missing_vars+=("BUILDKITE_JOB_EXIT_STATUS")
  
  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "Missing required environment variables: ${missing_vars[*]}" >&2
    return 1
  fi
  
  return 0
}

# Function to mock additional system commands needed by the plugin
mock_system_commands() {
  # Mock timeout command
  function timeout() {
    shift  # Remove timeout duration
    "$@"   # Execute the rest of the command
  }
  export -f timeout
  
  # Mock sha256sum (Linux) and shasum (macOS) for log hashing
  function sha256sum() {
    echo "mockhashabcdef123456789 -"
  }
  export -f sha256sum
  
  function shasum() {
    if [[ "$1" == "-a" && "$2" == "256" ]]; then
      echo "mockhashabcdef123456789 -"
    fi
  }
  export -f shasum
  
  # Mock date command for timestamp calculations
  function date() {
    case "$1" in
      "+%s")
        echo "1704067200"  # Fixed timestamp for testing
        ;;
      *)
        command date "$@" 2>/dev/null || echo "mock-date"
        ;;
    esac
  }
  export -f date
  
  # Mock stat command for file timestamps
  function stat() {
    case "$*" in
      *"-c %Y"*|*"-f %m"*)
        echo "1704063600"  # Fixed older timestamp for cache testing
        ;;
      *)
        echo "mock-stat-output"
        ;;
    esac
  }
  export -f stat
  
  # Mock mkdir and find commands
  function mkdir() {
    if [[ "$1" == "-p" ]]; then
      # Just succeed silently for mkdir -p
      return 0
    fi
    command mkdir "$@" 2>/dev/null || return 0
  }
  export -f mkdir
  
  function find() {
    # Mock find command to not actually search filesystem
    return 0
  }
  export -f find
}

# Function to clean up mock functions after tests
cleanup_mocks() {
  unset -f curl 2>/dev/null || true
  unset -f buildkite-agent 2>/dev/null || true
  unset -f jq 2>/dev/null || true
  unset -f timeout 2>/dev/null || true
  unset -f sha256sum 2>/dev/null || true
  unset -f shasum 2>/dev/null || true
  unset -f date 2>/dev/null || true
  unset -f stat 2>/dev/null || true
  unset -f mkdir 2>/dev/null || true
  unset -f find 2>/dev/null || true
}

# Export all functions so they can be used in test files
export -f mock_openai_success
export -f mock_openai_failure  
export -f mock_buildkite_agent_success
export -f mock_buildkite_agent_failure
export -f mock_jq
export -f mock_system_commands
export -f create_sample_log_file
export -f verify_test_environment
export -f cleanup_mocks