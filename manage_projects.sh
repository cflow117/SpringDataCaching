#!/bin/bash

# Define the paths to your sub-projects
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

# Function for handling merge_branch option
merge_branches() {
    echo "Enter the branch you want to merge from: "
    read -r SOURCE_BRANCH

    echo "Enter the branch you want to merge into: "
    read -r TARGET_BRANCH

    if [[ -z "$SOURCE_BRANCH" || -z "$TARGET_BRANCH" ]]; then
        echo "Both source and target branches must be specified. Exiting."
        return 1
    fi

    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $PROJECT"
        cd "$PROJECT" || { echo "Failed to access $PROJECT. Skipping."; continue; }

        # Check if the directory is a valid Git repository
        is_git_repository || continue

        # Checkout the target branch
        echo "Switching to target branch: $TARGET_BRANCH"
        git checkout "$TARGET_BRANCH" || { echo "Failed to switch to $TARGET_BRANCH in $(pwd). Skipping."; continue; }

        # Pull the latest changes for the target branch
        echo "Pulling latest changes on target branch: $TARGET_BRANCH"
        git pull || { echo "Failed to pull on $TARGET_BRANCH. Skipping."; continue; }

        # Merge the source branch into the target branch
        echo "Merging branch $SOURCE_BRANCH into $TARGET_BRANCH..."
        git merge --no-edit "$SOURCE_BRANCH"

        # Check if the merge resulted in conflicts
        if [[ $? -ne 0 ]]; then
            echo "Conflicts detected in $(pwd)."
            echo "Conflicts left unresolved. Please resolve manually later."
            
            # Optionally log unresolved conflicts details
            LOG_FILE="/tmp/merge_conflicts.log"
            echo "Conflicts in project: $PROJECT" >> "$LOG_FILE"
            git status --porcelain | grep "^UU" >> "$LOG_FILE"

            # Skip the project without committing
            continue
        fi

        echo "Merge completed successfully for $PROJECT."
    done
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

# Function to commit changes across all projects
commit_all_changes() {
    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $PROJECT"
        cd "$PROJECT" || { echo "Failed to access $PROJECT. Skipping."; continue; }

        # Check if the directory is a valid Git repository
        is_git_repository || continue

        # Check for uncommitted changes
        if [[ -n $(git status --porcelain) ]]; then
            echo "Uncommitted changes found in $(pwd)."
            git add .
            echo "Enter a commit message for $(pwd): "
            read -r COMMIT_MESSAGE
            if [[ -z "$COMMIT_MESSAGE" ]]; then
                echo "Commit message cannot be empty. Skipping commit."
                continue
            fi
            git commit -m "$COMMIT_MESSAGE"
        else
            echo "No uncommitted changes in $(pwd)."
        fi
    done
}

# Function to push changes for PR creation
push_all_changes() {
    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $PROJECT"
        cd "$PROJECT" || { echo "Failed to access $PROJECT. Skipping."; continue; }

        # Check if the directory is a valid Git repository
        is_git_repository || continue

        echo "Pushing changes..."
        git push || { echo "Failed to push changes for $PROJECT. Skipping."; continue; }
    done
}

# Dummy function to create a new branch after pulling
create_branch() {
    echo "Enter the new branch name: "
    read -r NEW_BRANCH

    if [[ -z "$NEW_BRANCH" ]]; then
        echo "Branch name cannot be empty. Exiting."
        return 1
    fi

    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $PROJECT"
        cd "$PROJECT" || { echo "Failed to access $PROJECT. Skipping."; continue; }

        # Check if the directory is a valid Git repository
        is_git_repository || continue

        echo "Fetching updates..."
        git fetch

        echo "Creating new branch: $NEW_BRANCH"
        git checkout -b "$NEW_BRANCH"
    done
}

# Function to update versions and dependencies across projects
update_versions() {
    declare -A updated_versions

    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $PROJECT"
        cd "$PROJECT" || continue

        # Retrieve the current version from pom.xml
        local CURRENT_VERSION=$(grep -m 1 "<version>" "$PROJECT/pom.xml" | sed -E 's|.*<version>([a-zA-Z]+\.[0-9]+\.[0-9]+\.[0-9]+)</version>.*|\1|')

        if [[ -z "$CURRENT_VERSION" ]]; then
            echo "Unable to find the current version for $PROJECT. Skipping."
            continue
        fi

        echo "Current version for project $(basename "$PROJECT"): $CURRENT_VERSION"

        # Increment the version (e.g., qa.1.1.20 -> qa.1.1.21)
        local PREFIX=$(echo "$CURRENT_VERSION" | cut -d. -f1)
        local VERSION_NUMBERS=$(echo "$CURRENT_VERSION" | cut -d. -f2-)
        local NEW_VERSION="$PREFIX.$(echo "$VERSION_NUMBERS" | awk -F. '{print $1 "." $2 "." $3+1}')"

        # Update the pom.xml version
        sed -i '' -E "s|<version>$CURRENT_VERSION</version>|<version>$NEW_VERSION</version>|g" "$PROJECT/pom.xml"

        echo "Updated version to $NEW_VERSION in $PROJECT."

        # Save the new version to be used for dependency updates
        updated_versions["$PROJECT"]="$NEW_VERSION"
    done

    # Update dependencies in all `pom.xml` files
    for PROJECT in "${SUB_PROJECTS[@]}"; do
        cd "$PROJECT" || continue
        for DEP_PROJECT in "${!updated_versions[@]}"; do
            local DEP_VERSION=${updated_versions["$DEP_PROJECT"]}
            local ARTIFACT_NAME=$(basename "$DEP_PROJECT")
            sed -i '' -E "s|(<artifactId>$ARTIFACT_NAME</artifactId>.*<version>)[^<]+(<\/version>)|\1$DEP_VERSION\2|g" "$PROJECT/pom.xml"
        done
    done

    echo "Versions and dependencies updated successfully."
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
