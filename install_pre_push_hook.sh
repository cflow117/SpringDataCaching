#!/bin/bash

install_pre_push_hook() {
    local HOOK_NAME="pre-push"
    local GIT_HOOKS_DIR=".git/hooks"
    local CURRENT_SCRIPT_PATH="$0"
    local TARGET_HOOK_PATH="$GIT_HOOKS_DIR/$HOOK_NAME"

    echo "[INFO] Checking if Git pre-push hook is already installed..."
    if [ -f "$TARGET_HOOK_PATH" ] && cmp -s "$CURRENT_SCRIPT_PATH" "$TARGET_HOOK_PATH"; then
        echo "[INFO] Pre-push hook is already installed."
        return 0
    fi

    echo "[INFO] Installing Git pre-push hook..."
    mkdir -p "$GIT_HOOKS_DIR"
    cp "$CURRENT_SCRIPT_PATH" "$TARGET_HOOK_PATH"
    chmod +x "$TARGET_HOOK_PATH"
    echo "[INFO] Git pre-push hook installed successfully at $TARGET_HOOK_PATH."
}

main() {
    echo "[INFO] Running pre-push hook validations..."
    if git diff --cached --name-only | grep -q "Dockerfile"; then
        echo "[INFO] Dockerfile changes detected."
    fi

    changes=$(git diff --cached --name-only)
    echo "[INFO] Changes staged for commit:"
    echo "$changes"

    if [ -n "$changes" ]; then
        echo "[INFO] Amending commit with changes summary..."
        summary="Summary of Changes:\n$changes"
        git commit --amend -m "$summary" || echo "[ERROR] Failed to amend git commit."
    fi

    echo "[INFO] Pre-push hook completed successfully."
}

if [ "$1" != "NO_INSTALL" ]; then
    install_pre_push_hook
fi

main

exit 0