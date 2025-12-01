#!/bin/bash

# Define the paths to your 7 sub-projects
declare -a SUB_PROJECTS=(
    "/path/to/project1"
    "/path/to/project2"
    "/path/to/project3"
    "/path/to/project4"
    "/path/to/project5"
    "/path/to/project6"
    "/path/to/project7"
)

# Function to check if the directory is a valid Git repository
is_git_repository() {
    if [[ ! -d ".git" ]]; then
        echo "Directory $(pwd) is not a valid Git repository. Skipping."
        return 1
    fi
}

# Function to increment the version (e.g., dev.1.1.20 -> dev.1.1.21)
increment_version() {
    local current_version=$1
    # Split into prefix and version number; increment the patch version
    local prefix=$(echo "$current_version" | cut -d. -f1)  # e.g., 'dev'
    local version_numbers=$(echo "$current_version" | cut -d. -f2-)  # e.g., '1.1.20'
    local new_version=$(echo "$version_numbers" | awk -F. '{print $1 "." $2 "." $3+1}')
    echo "$prefix.$new_version"
}

# Function to resolve conflicts and choose the correct version
resolve_version_conflict() {
    local dependency_name=$1
    echo "Conflict detected in $dependency_name. Please choose the environment for resolution:"
    echo "1) Development (dev)"
    echo "2) Quality Assurance (qa)"
    echo "3) Staging (stage)"
    echo "4) Production (prod)"
    echo "Enter your choice (1/2/3/4): "
    read -r ENV_CHOICE

    case $ENV_CHOICE in
        1) echo "dev";;
        2) echo "qa";;
        3) echo "stage";;
        4) echo "prod";;
        *) echo "Invalid choice. Defaulting to 'dev'."; echo "dev";;
    esac
}

# Function to update the project's version in its pom.xml
update_pom_version() {
    local project_path=$1
    local current_env=$2

    # Retrieve the current version
    local current_version=$(grep -m 1 "<version>" "$project_path/pom.xml" | sed -E 's|.*<version>([a-zA-Z]+\.[0-9]+\.[0-9]+\.[0-9]+)</version>.*|\1|')
    if [[ -z "$current_version" ]]; then
        echo "Unable to find the current version in $project_path."
        return
    fi

    # Determine whether to increment or resolve conflicts
    if [[ -n $(grep "<<<<<<<" "$project_path/pom.xml") ]]; then
        echo "Merge conflict detected in $project_path/pom.xml."
        local resolved_env=$(resolve_version_conflict "$(basename "$project_path")")
        local prefix=$(echo "$current_version" | cut -d. -f1)
        local resolved_version="$resolved_env.$(echo "$current_version" | cut -d. -f2-)"
        echo "Resolved version: $resolved_version"
        sed -i '' -E "s|<version>.*</version>|<version>$resolved_version</version>|g" "$project_path/pom.xml"
    else
        # Increment logically
        local new_version=$(increment_version "$current_version")
        echo "Updating version in $project_path/pom.xml to $new_version"
        sed -i '' -E "s|<version>.*</version>|<version>$new_version</version>|g" "$project_path/pom.xml"
    fi

    echo "Version update completed for $project_path."
}

# Function to update dependencies in pom.xml
update_dependency_versions() {
    local project_path=$1
    declare -n updated_versions=$2  # Associative array {project_path -> version}

    for dependency_project in "${!updated_versions[@]}"; do
        local dependency_version=${updated_versions[$dependency_project]}
        local dependency_project_name=$(basename "$dependency_project")
        # Only update dependencies that are part of configured SUB_PROJECTS
        if [[ " ${SUB_PROJECTS[*]} " == *"$dependency_project"* ]]; then
            echo "Updating dependency $dependency_project_name to version $dependency_version in $project_path"
            sed -i '' -E "s|(<artifactId>$dependency_project_name</artifactId>.*<version>)[^<]+(<\/version>)|\1$dependency_version\2|g" "$project_path/pom.xml"
        fi
    done
}

# Option 6: Update versions and dependencies
update_versions() {
    declare -A updated_versions  # Associative array {project_path -> version}

    # Update all project versions
    for project in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $project"
        update_pom_version "$project" # Update version and resolve conflicts if any
        local current_version=$(grep -m 1 "<version>" "$project/pom.xml" | sed -E 's|.*<version>(.*)</version>.*|\1|')
        updated_versions["$project"]="$current_version"
    done

    echo "Starting dependency updates in all projects..."

    # Update dependencies across all projects
    for project in "${SUB_PROJECTS[@]}"; do
        update_dependency_versions "$project" updated_versions
    done

    echo "Dependency and version updates completed successfully."
}

# Function for pull and rebase
pull_and_rebase() {
    echo "Enter the branch you want to pull/rebase and switch to: "
    read -r TARGET_BRANCH

    if [[ -z "$TARGET_BRANCH" ]]; then
        echo "Branch name cannot be empty. Exiting."
        return 1
    fi

    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $PROJECT"
        cd "$PROJECT" || { echo "Failed to access $PROJECT. Skipping."; continue; }

        # Check if the directory is a valid Git repository
        is_git_repository || continue

        echo "Switching to branch: $TARGET_BRANCH"
        git checkout "$TARGET_BRANCH"
        echo "Pulling the latest changes..."
        git pull --rebase
    done
}

# Main workflow to offer user choices
main_workflow() {
    echo "What would you like to do? Choose an option:"
    echo "1) Check branch status, pull, and rebase across all projects"
    echo "2) Create a new branch across all projects after pulling"
    echo "3) Commit all changes across projects"
    echo "4) Commit all changes and push branches across projects for PR creation"
    echo "5) Merge one branch into another across all projects"
    echo "6) Update versions and dependencies across all projects"
    echo "Enter your choice (1/2/3/4/5/6): "
    read -r CHOICE

    case $CHOICE in
        1) pull_and_rebase ;;
        2) create_branch ;;
        3) commit_all_changes ;;
        4) push_all_changes ;;
        5) merge_branches ;;
        6) update_versions ;;
        *) echo "Invalid choice. Exiting."; exit 1 ;;
    esac
}

# Run the main workflow
main_workflow
