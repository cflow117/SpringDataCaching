#!/bin/bash

   # Define the hooks directory
   HOOKS_DIR="./hooks"
   GIT_HOOKS_DIR=".git/hooks"

   echo "[INFO] Installing Git pre-push hook..."
   if [ -f "$HOOKS_DIR/pre-push" ]; then
       cp "$HOOKS_DIR/pre-push" "$GIT_HOOKS_DIR/pre-push"
       chmod +x "$GIT_HOOKS_DIR/pre-push"
       echo "[INFO] Git pre-push hook installed successfully."
   else
       echo "[ERROR] pre-push hook not found in $HOOKS_DIR."
   fi