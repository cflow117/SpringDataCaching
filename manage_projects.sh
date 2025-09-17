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

# Function to check for uncommitted changes
check_uncommitted_changes() {
    if [[ -n $(git status --porcelain) ]]; then
        # There are uncommitted changes
        echo "Uncommitted changes found in $(pwd). Preparing to commit them..."
        git add .
        echo "Enter a commit message for changes in $(pwd): "
        read -r commit_message
        if [[ -z "$commit_message" ]]; then
            echo "Commit message cannot be empty. Skipping commit."
            return 1
        fi
        git commit -m "$commit_message" || { echo "Failed to commit changes in $(pwd). Aborting."; return 1; }
        echo "Committed changes in $(pwd)."
    else
        echo "No uncommitted changes in $(pwd)."
    fi
}

# Function to handle failures during a Git command
handle_git_failure() {
    echo "Error encountered in $(pwd). Aborting processing for this project."
    return 1
}

# Function to verify if a Git repository is valid
is_git_repository() {
    if [[ ! -d ".git" ]]; then
        echo "Directory $(pwd) is not a valid Git repository. Skipping."
        return 1
    fi
}

# Main workflow
main_workflow() {
    echo "What would you like to do? Choose an option:"
    echo "1) Check branch status, pull, and rebase across all projects"
    echo "2) Create a new branch across all projects after pulling"
    echo "3) Commit all changes across projects"
    echo "4) Commit all changes and push branches across projects for PR creation"
    echo "Enter your choice (1/2/3/4): "
    read -r CHOICE

    case $CHOICE in
        1) pull_and_rebase ;;
        2) create_branch ;;
        3) commit_all_changes ;;
        4) push_all_changes ;;
        *) echo "Invalid choice. Exiting."; exit 1 ;;
    esac
}

# Option 1: Pull and rebase across all projects
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

        CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            echo "Failed to retrieve the current branch for $(pwd). Skipping."
            continue
        fi
        echo "Current branch: $CURRENT_BRANCH"

        # Check for uncommitted changes
        check_uncommitted_changes || continue

        # Check if the branch exists locally
        if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
            echo "Switching to branch: $TARGET_BRANCH"
            git checkout "$TARGET_BRANCH" || { handle_git_failure; continue; }
            echo "Pulling latest changes from origin/$TARGET_BRANCH..."
            git pull --rebase || { handle_git_failure; continue; }
        else
            echo "Branch $TARGET_BRANCH does not exist locally."
            echo "Enter the base branch from which to create $TARGET_BRANCH: "
            read -r BASE_BRANCH
            if [[ -z "$BASE_BRANCH" ]]; then
                echo "Base branch cannot be empty. Skipping."
                continue
            fi
            echo "Creating and switching to branch $TARGET_BRANCH from $BASE_BRANCH..."
            git checkout "$BASE_BRANCH" || { handle_git_failure; continue; }
            git pull || { handle_git_failure; continue; }
            git checkout -b "$TARGET_BRANCH" || { handle_git_failure; continue; }
        fi

        echo "Processed $PROJECT"
    done
}

# Option 2: Create a new branch across all projects
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

        echo "Enter the base branch to create $NEW_BRANCH from in project $PROJECT: "
        read -r BASE_BRANCH

        if [[ -z "$BASE_BRANCH" ]]; then
            echo "Base branch cannot be empty. Skipping."
            continue
        fi

        echo "Pulling latest changes from $BASE_BRANCH..."
        git checkout "$BASE_BRANCH" || { handle_git_failure; continue; }
        git pull || { handle_git_failure; continue; }

        echo "Creating and switching to new branch: $NEW_BRANCH..."
        git checkout -b "$NEW_BRANCH" || { handle_git_failure; continue; }

        echo "Branch $NEW_BRANCH has been created in $PROJECT."
    done
}

# Option 3: Commit all changes across projects
commit_all_changes() {
    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $PROJECT"
        cd "$PROJECT" || { echo "Failed to access $PROJECT. Skipping."; continue; }

        # Check if the directory is a valid Git repository
        is_git_repository || continue

        check_uncommitted_changes || continue
    done
}

# Option 4: Commit and push all changes across projects
push_all_changes() {
    for PROJECT in "${SUB_PROJECTS[@]}"; do
        echo "Processing project: $PROJECT"
        cd "$PROJECT" || { echo "Failed to access $PROJECT. Skipping."; continue; }

        # Check if the directory is a valid Git repository
        is_git_repository || continue

        check_uncommitted_changes || continue

        CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            echo "Failed to retrieve current branch in $(pwd). Skipping."
            continue
        fi

        echo "Pushing changes in branch $CURRENT_BRANCH to origin..."
        git push -u origin "$CURRENT_BRANCH" || { echo "Failed to push changes for $(pwd). Skipping."; continue; }

        echo "Changes pushed successfully for $PROJECT."
    done
}

# Run the main workflow
main_workflow

#   chmod +x manage_projects.sh
#   ./manage_projects.sh
