#!/bin/bash

# Define the paths to your sub-projects and their corresponding artifactIds
declare -a SUB_PROJECTS=(
    "/path/to/project1"
    "/path/to/project2"
    "/path/to/project3"
    "/path/to/project4"
    "/path/to/project5"
    "/path/to/project6"
    "/path/to/project7"
)

# Define the artifactIds corresponding to the sub-projects
declare -a ARTIFACT_IDS=(
    "project1-artifact"
    "project2-artifact"
    "project3-artifact"
    "project4-artifact"
    "project5-artifact"
    "project6-artifact"
    "project7-artifact"
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

# Function to create a new branch
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

# Function to update project versions and dependencies
update_versions() {
    for i in "${!SUB_PROJECTS[@]}"; do
        PROJECT=${SUB_PROJECTS[$i]}
        ARTIFACT_ID=${ARTIFACT_IDS[$i]}

        echo "Processing project: $PROJECT with artifactId: $ARTIFACT_ID"
        cd "$PROJECT" || continue

        # Find the current version from pom.xml matching the artifactId
        CURRENT_VERSION=$(grep -A1 "<artifactId>$ARTIFACT_ID</artifactId>" "pom.xml" | grep "<version>" | sed -E 's|.*<version>([^<]+)</version>.*|\1|')
        if [[ -z "$CURRENT_VERSION" ]]; then
            echo "Unable to find the current version for artifactId $ARTIFACT_ID in project $PROJECT. Skipping."
            continue
        fi

        echo "Current version for $ARTIFACT_ID: $CURRENT_VERSION"

        # Increment the version
        PREFIX=$(echo "$CURRENT_VERSION" | cut -d. -f1)
        VERSION_NUMBERS=$(echo "$CURRENT_VERSION" | cut -d. -f2-)
        NEW_VERSION="$PREFIX.$(echo "$VERSION_NUMBERS" | awk -F. '{print $1 "." $2 "." $3+1}')"

        # Update the version in the pom.xml
        sed -i '' -E "s|<artifactId>$ARTIFACT_ID</artifactId>.*<version>$CURRENT_VERSION</version>|<artifactId>$ARTIFACT_ID</artifactId><version>$NEW_VERSION</version>|g" "pom.xml"
        echo "Updated $ARTIFACT_ID version to $NEW_VERSION in $PROJECT."

        # Update dependencies in downstream projects
        for j in $(seq $((i + 1)) ${#SUB_PROJECTS[@]}); do
            DOWNSTREAM_PROJECT=${SUB_PROJECTS[$j]}
            echo "Updating dependency $ARTIFACT_ID to version $NEW_VERSION in $DOWNSTREAM_PROJECT..."
            cd "$DOWNSTREAM_PROJECT" || continue
            sed -i '' -E "s|<artifactId>$ARTIFACT_ID</artifactId>.*<version>[^<]+</version>|<artifactId>$ARTIFACT_ID</artifactId><version>$NEW_VERSION</version>|g" "pom.xml"
        done
    done
}

# NEW FUNCTION: Commit all changes after conflict resolution
commit_after_merge_conflict() {
    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $PROJECT"
        cd "$PROJECT" || { echo "Failed to access $PROJECT. Skipping."; continue; }

        # Commit manually resolved conflicts, if present
        if [[ -n $(git status --porcelain) ]]; then
            git add .
            echo "Enter a commit message for resolved conflicts in $PROJECT: "
            read -r COMMIT_MESSAGE
            if [[ -n "$COMMIT_MESSAGE" ]]; then
                git commit -m "$COMMIT_MESSAGE"
                echo "Added commit for resolved conflicts in $PROJECT."
            else
                echo "Commit message cannot be empty. Skipping $PROJECT."
            fi
        else
            echo "No changes to commit in $PROJECT."
        fi
    done
}

# NEW FUNCTION: Show git status for all projects
status_all_projects() {
    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Git status for project: $PROJECT"
        cd "$PROJECT" || { echo "Failed to access $PROJECT. Skipping."; continue; }
        is_git_repository || continue
        git status
        echo ""
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
    echo "7) Commit all changes after manually resolving conflicts"
    echo "8) Show git status across all projects"

    echo "Enter your choice (1/2/3/4/5/6/7/8): "
    read -r CHOICE

    case $CHOICE in
        1) pull_and_rebase ;;
        2) create_branch ;;
        3) commit_all_changes ;;
        4) push_all_changes ;;
        5) merge_branches ;;
        6) update_versions ;;
        7) commit_after_merge_conflict ;;
        8) status_all_projects ;;
        *) echo "Invalid choice. Exiting."; exit 1 ;;
    esac
}

# Run the main workflow
main_workflow
