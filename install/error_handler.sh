#!/bin/bash

# 오류 처리 및 자동 백로그 등록 함수
# 다른 스크립트에서 source로 불러서 사용

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_ISSUE_SCRIPT="$SCRIPT_DIR/create_issue_and_backlog.sh"

# 오류 발생시 자동으로 이슈 생성
handle_error() {
    local exit_code=$?
    local command="$1"
    local error_msg="$2"
    
    if [[ $exit_code -ne 0 ]]; then
        echo "❌ Error detected: $command failed with exit code $exit_code"
        
        # 이슈 제목과 내용 생성
        local title="Deployment Error: $command Failed"
        local body="## Error Summary
Command: \`$command\`
Exit Code: $exit_code
Error Message: $error_msg

## Context
- Timestamp: $(date)
- Working Directory: $(pwd)
- User: $(whoami)

## Steps to Reproduce
1. Run command: \`$command\`
2. Error occurs

## Expected Behavior
Command should execute successfully

## Actual Behavior
Command failed with exit code $exit_code

🤖 Auto-generated from error handler

Co-Authored-By: Claude <noreply@anthropic.com>"

        # 이슈 생성 및 백로그 등록
        if [[ -x "$CREATE_ISSUE_SCRIPT" ]]; then
            "$CREATE_ISSUE_SCRIPT" "$title" "$body" "bug,auto-generated"
        else
            echo "❌ Issue creation script not found or not executable"
        fi
    fi
}

# 스크립트에서 오류 발생시 자동 처리
set -E
trap 'handle_error "$BASH_COMMAND" "Script failed at line $LINENO"' ERR