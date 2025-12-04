#!/bin/bash

set -e

APP_PROPERTIES_FILE="application.properties"
APP_YML_FILE="application.yml"
DOCKERFILE="Dockerfile"
K8S_YAML_FOLDER="kubernetes"
K8S_YAML_PATTERN="$K8S_YAML_FOLDER/*.yml $K8S_YAML_FOLDER/*.yaml"
ENV_FILES_ROOT="./box"
VALID_ENVIRONMENTS=("dev" "qa" "stage" "prod")
BOX_LOGIN_REQUIRED=false
BOX_UPLOAD_ENABLED=true
GIT_APPEND_SUMMARY_ENABLED=true
PROMPT_USER_ON_CHANGES=false
DEFAULT_ENVIRONMENT="dev"

declare -A BOX_PATHS=(
    [dev]="$ENV_FILES_ROOT/dev/"
    [qa]="$ENV_FILES_ROOT/qa/"
    [stage]="$ENV_FILES_ROOT/stage/"
    [prod]="$ENV_FILES_ROOT/prod/"
)

log_error() {
    echo "[ERROR]: $1" >&2
}

log_warning() {
    echo "[WARNING]: $1" >&2
}

log_info() {
    echo "[INFO]: $1"
}

detect_changes() {
    local file_pattern="$1"
    git diff --cached --name-only | grep -E "$file_pattern" || true
}

extract_properties() {
    local file="$1"
    declare -A properties

    if [ ! -f "$file" ]; then
        return
    fi

    while IFS= read -r line; do
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            properties["$key"]="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^([A-Za-z0-9_]+): ]]; then
            key="${BASH_REMATCH[1]}"
            properties["$key"]="null"
        fi
    done < "$file"

    echo "${!properties[@]}"
}

sync_box_environment_file() {
    local box_folder="$1"
    local environment="$2"

    log_info "Synchronizing environment file for $environment..."
    local box_env_file="${box_folder}/env-${environment}.txt"

    if [ "$BOX_LOGIN_REQUIRED" = true ]; then
        open "your-box-sso-login-link" || log_error "Unable to open Box SSO login link."
        read -p "Press Enter once login is complete." || return 1
    fi

    if [ -f "$box_env_file" ]; then
        local existing_keys=($(extract_properties "$box_env_file"))
        declare -A existing_keys_map

        for key in "${existing_keys[@]}"; do
            existing_keys_map["$key"]=true
        done

        local_properties_keys=($(extract_properties "$APP_PROPERTIES_FILE"))
        local_yaml_keys=($(extract_properties "$APP_YML_FILE"))

        for key in "${local_properties_keys[@]}" "${local_yaml_keys[@]}"; do
            if [ -z "${existing_keys_map["$key"]}" ]; then
                echo "$key=new_value" >> "$box_env_file"
                existing_keys_map["$key"]=true
            fi
        done

        log_info "Environment file $box_env_file updated successfully."
    else
        log_warning "Environment file $box_env_file not found. Skipping sync."
    fi
}

append_summary_to_git_commit() {
    local summary="$1"
    if [ "$GIT_APPEND_SUMMARY_ENABLED" = true ]; then
        git commit --amend -m "$summary" || log_error "Failed to amend summary to the latest git commit."
        log_info "Amended summary to the latest git commit."
    fi
}

prompt_user() {
    local feature_name="$1"
    if [ "$PROMPT_USER_ON_CHANGES" = true ]; then
        read -p "Proceed with changes for $feature_name? (y/n): " confirmation
        if [[ "$confirmation" != "y" ]]; then
            log_info "User declined changes for $feature_name. Aborting."
            exit 1
        fi
    fi
}

log_info "Running pre-push script..."

dockerfile_changes=$(detect_changes "$DOCKERFILE")
if [ -n "$dockerfile_changes" ]; then
    log_info "Detected changes in $DOCKERFILE: $dockerfile_changes"
    prompt_user "Dockerfile"
fi

k8s_yaml_changes=$(detect_changes "$K8S_YAML_PATTERN")
if [ -n "$k8s_yaml_changes" ]; then
    log_info "Detected changes in Kubernetes YAML files:"
    for file in $k8s_yaml_changes; do
        echo "  - $file"
    done
    prompt_user "Kubernetes YAML"
fi

app_properties_keys=($(extract_properties "$APP_PROPERTIES_FILE"))
app_yml_keys=($(extract_properties "$APP_YML_FILE"))

log_info "Extracted keys from $APP_PROPERTIES_FILE: ${app_properties_keys[*]}"
log_info "Extracted keys from $APP_YML_FILE: ${app_yml_keys[*]}"

branch_name=$(git rev-parse --abbrev-ref HEAD)
if [[ " ${VALID_ENVIRONMENTS[*]} " =~ " $branch_name " ]]; then
    environment="$branch_name"
else
    environment="$DEFAULT_ENVIRONMENT"
fi
log_info "Target environment: $environment"

if [ "$BOX_UPLOAD_ENABLED" = true ]; then
    box_folder="${BOX_PATHS[$environment]}"
    if [ -n "$box_folder" ]; then
        sync_box_environment_file "$box_folder" "$environment" || log_warning "Box sync failed. Proceeding without it."
    fi
fi

summary="Summary of Changes:
- Dockerfile changes: $dockerfile_changes
- Kubernetes YAML changes: $k8s_yaml_changes
- Extracted keys from application.properties: ${app_properties_keys[*]}
- Extracted keys from application.yml: ${app_yml_keys[*]}"

log_info "Summary of changes:"
echo "$summary"
append_summary_to_git_commit "$summary"

log_info "Pre-push validation complete."
exit 0