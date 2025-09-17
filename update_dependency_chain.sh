#!/bin/bash

# Define the paths to the `pom.xml` files for the 7 projects
declare -A PROJECT_PATHS
PROJECT_PATHS=(
    ["project1"]="/path/to/project1/pom.xml"
    ["project2"]="/path/to/project2/pom.xml"
    ["project3"]="/path/to/project3/pom.xml"
    ["project4"]="/path/to/project4/pom.xml"
    ["project5"]="/path/to/project5/pom.xml"
    ["project6"]="/path/to/project6/pom.xml"
    ["project7"]="/path/to/project7/pom.xml"
)

# Define the dependency chains
# Declare project dependencies in the order of their dependency chain
declare -A DEPENDENCIES
DEPENDENCIES=(
    ["project1"]="project2 project3"
    ["project2"]="project4"
    ["project4"]="project5"
    ["project5"]="project6"
    ["project6"]="project7"
    ["project3"]="project6"
)

# Initialize an array to store version changes
declare -A VERSION_CHANGES

# Helper function to extract the current version from a pom.xml
get_version() {
    local pom_file="$1"
    grep -m 1 "<version>" "$pom_file" | sed -E 's/.*<version>(.*)<\/version>.*/\1/'
}

# Helper function to update the version in a pom.xml
update_version() {
    local pom_file="$1"
    local new_version="$2"
    sed -i.bak -E "s/(<version>)[^<]+(<\/version>)/\1$new_version\2/" "$pom_file" && rm -f "${pom_file}.bak"
    echo "Updated version in $pom_file to $new_version."
}

# Helper function to update the dependency version in a pom.xml
update_dependency_version() {
    local pom_file="$1"
    local dependency_artifact="$2"
    local new_dependency_version="$3"
    sed -i.bak -E "/<artifactId>$dependency_artifact<\/artifactId>/{N;s/(<version>)[^<]+(<\/version>)/\1$new_dependency_version\2/}" "$pom_file" && rm -f "${pom_file}.bak"
    echo "Updated $dependency_artifact in $pom_file to version $new_dependency_version."
}

# Function to bump up the version of a single project
bump_version() {
    local project="$1"
    local pom_file="${PROJECT_PATHS[$project]}"

    # Get the current version
    local current_version
    current_version=$(get_version "$pom_file")

    # Increment the version (assume version format is `dev.x.y.z`)
    local new_version
    new_version=$(echo "$current_version" | awk -F. -v OFS=. '{ $NF++; print }')

    # Update the version in the project's pom.xml
    update_version "$pom_file" "$new_version"

    # Record the version change
    VERSION_CHANGES["$project"]="Updated from $current_version to $new_version"

    # Return the new version
    echo "$new_version"
}

# Function to resolve dependencies and bump versions across the whole dependency chain
resolve_and_bump_versions() {
    local project="$1"

    # Check if this project has already been processed
    if [[ " ${PROCESSED_PROJECTS[@]} " == *" $project "* ]]; then
        return
    fi

    # Mark this project as processed
    PROCESSED_PROJECTS+=("$project")

    # Get the dependent projects
    local dependents="${DEPENDENCIES[$project]}"

    # Recursively process dependencies first
    if [[ -n "$dependents" ]]; then
        for dep in $dependents; do
            resolve_and_bump_versions "$dep"
        done
    fi

    # Now bump the version of this project
    local pom_file="${PROJECT_PATHS[$project]}"
    if [[ ! -f "$pom_file" ]]; then
        echo "Error: pom.xml file not found for $project!"
        exit 1
    fi

    local new_version
    new_version=$(bump_version "$project")

    # Update this project's version in the dependent projects
    if [[ -n "$dependents" ]]; then
        for dep in $dependents; do
            local dep_pom="${PROJECT_PATHS[$dep]}"
            if [[ -f "$dep_pom" ]]; then
                update_dependency_version "$dep_pom" "$project" "$new_version"
            else
                echo "Warning: Dependency pom.xml file not found for $dep!"
            fi
        done
    fi
}

# Main function to run the entire version bumping process
main() {
    echo "Starting version bumping process..."

    # Let the user configure the branch being worked on
    echo "Enter the branch you are working on (e.g., dev, qa, stage, prod): "
    read -r BRANCH
    if [[ -z "$BRANCH" ]]; then
        echo "Error: Branch cannot be empty. Exiting."
        exit 1
    fi

    # Switch to the specified branch for all projects
    for project in "${!PROJECT_PATHS[@]}"; do
        local project_path
        project_path=$(dirname "${PROJECT_PATHS[$project]}")
        echo "Switching to branch $BRANCH for project: $project"
        cd "$project_path" || { echo "Error: Failed to access $project_path. Exiting."; exit 1; }
        git checkout "$BRANCH" || { echo "Error: Failed to checkout branch $BRANCH for $project. Exiting."; exit 1; }
        git pull || { echo "Error: Failed to pull latest changes for $project. Exiting."; exit 1; }
    done

    # Process each project's dependency chain and bump versions
    PROCESSED_PROJECTS=()
    for project in "${!DEPENDENCIES[@]}"; do
        resolve_and_bump_versions "$project"
    done

    # Commit the changes across all projects
    for project in "${!PROJECT_PATHS[@]}"; do
        local project_path
        project_path=$(dirname "${PROJECT_PATHS[$project]}")
        cd "$project_path" || continue
        if [[ -n $(git status --porcelain) ]]; then
            echo "Committing changes for project: $project"
            git add pom.xml
            git commit -m "Bumped version across dependency chain from script"
            git push origin "$BRANCH" || { echo "Error: Failed to push changes for $project. Exiting."; exit 1; }
        else
            echo "No changes to commit for project: $project"
        fi
    done

    # Summarize version changes
    echo "Version bumping process completed successfully!"
    echo "------------------------------------------"
    echo "Summary of version changes made:"
    for project in "${!VERSION_CHANGES[@]}"; do
        echo "- $project: ${VERSION_CHANGES[$project]}"
    done
    echo "------------------------------------------"
}

# Execute the main function
main


#   chmod +x update_dependency_chain.sh
#   ./update_dependency_chain.sh
