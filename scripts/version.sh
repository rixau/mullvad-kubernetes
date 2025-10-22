#!/bin/bash

# Version bump script for Mullvad Kubernetes
# Usage: ./scripts/version.sh [chart|app] [patch|minor|major]
# Examples:
#   ./scripts/version.sh app patch    # Bump app version (creates new Docker image)
#   ./scripts/version.sh chart patch  # Bump chart version (for Helm template changes)
#
# Note: Both proxy and dashboard charts are version-locked and updated together

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Chart paths
PROXY_CHART="charts/proxy/Chart.yaml"
PROXY_VALUES="charts/proxy/values.yaml"
DASHBOARD_CHART="charts/dashboard/Chart.yaml"

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're on main branch
if [[ $(git branch --show-current) != "main" ]]; then
    print_error "Must be on main branch to version"
    exit 1
fi     

# Check if working directory is clean
if [[ -n $(git status --porcelain) ]]; then
    print_error "Working directory is not clean. Please commit or stash changes first."
    exit 1
fi

# Check arguments
if [ $# -ne 2 ]; then
    print_error "Usage: $0 [chart|app] [patch|minor|major]"
    print_error "Examples:"
    print_error "  $0 app patch    # Bump app version (creates new Docker image)"
    print_error "  $0 chart patch  # Bump chart version (for Helm template changes)"
    exit 1
fi

TARGET_TYPE=$1
VERSION_TYPE=$2

if [[ ! "$TARGET_TYPE" =~ ^(chart|app)$ ]]; then
    print_error "Invalid target type. Use: chart or app"
    exit 1
fi

if [[ ! "$VERSION_TYPE" =~ ^(patch|minor|major)$ ]]; then
    print_error "Invalid version type. Use: patch, minor, or major"
    exit 1
fi

print_status "Bumping $TARGET_TYPE $VERSION_TYPE version..."

# Get current version based on target type (from proxy chart)
if [[ "$TARGET_TYPE" == "app" ]]; then
    CURRENT_VERSION=$(grep '^appVersion:' $PROXY_CHART | sed 's/appVersion: "//' | sed 's/"//')
    print_status "Current app version: $CURRENT_VERSION"
else
    CURRENT_VERSION=$(grep '^version:' $PROXY_CHART | sed 's/version: //')
    print_status "Current chart version: $CURRENT_VERSION"
fi

# Parse version components
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR="${VERSION_PARTS[0]}"
MINOR="${VERSION_PARTS[1]}"
PATCH="${VERSION_PARTS[2]}"

# Calculate new version based on type
case $VERSION_TYPE in
    patch)
        NEW_PATCH=$((PATCH + 1))
        NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
        ;;
    minor)
        NEW_MINOR=$((MINOR + 1))
        NEW_VERSION="$MAJOR.$NEW_MINOR.0"
        ;;
    major)
        NEW_MAJOR=$((MAJOR + 1))
        NEW_VERSION="$NEW_MAJOR.0.0"
        ;;
esac

print_status "New version: $NEW_VERSION"

# Update files based on target type
if [[ "$TARGET_TYPE" == "app" ]]; then
    # Update appVersion in both Chart.yaml files (leave chart version unchanged)
    sed -i "s/^appVersion: .*/appVersion: \"$NEW_VERSION\"/" $PROXY_CHART
    sed -i "s/^appVersion: .*/appVersion: \"$NEW_VERSION\"/" $DASHBOARD_CHART
    
    # Update values.yaml with new image tag
    sed -i "s/^  tag: .*/  tag: \"$NEW_VERSION\"/" $PROXY_VALUES
    
    print_status "Updated proxy chart appVersion to $NEW_VERSION"
    print_status "Updated dashboard chart appVersion to $NEW_VERSION"
    print_status "Updated image tag in proxy values.yaml to $NEW_VERSION"
    print_warning "Chart versions unchanged - use './scripts/version.sh chart patch' to update chart versions"
    
    FILES_TO_COMMIT="$PROXY_CHART $DASHBOARD_CHART $PROXY_VALUES"
    COMMIT_MESSAGE="chore: bump app version to v$NEW_VERSION

- Updated appVersion in both proxy and dashboard charts
- Updated image tag in proxy values.yaml
- Charts remain version-locked
- Docker image will be built and pushed by CI/CD"
else
    # Update chart version in both Chart.yaml files (leave appVersion unchanged)
    sed -i "s/^version: .*/version: $NEW_VERSION/" $PROXY_CHART
    sed -i "s/^version: .*/version: $NEW_VERSION/" $DASHBOARD_CHART
    
    print_status "Updated proxy chart version to $NEW_VERSION"
    print_status "Updated dashboard chart version to $NEW_VERSION"
    print_status "App version unchanged (still $(grep '^appVersion:' $PROXY_CHART | sed 's/appVersion: "//' | sed 's/"//')))"
    
    FILES_TO_COMMIT="$PROXY_CHART $DASHBOARD_CHART"
    COMMIT_MESSAGE="chore: bump chart version to $NEW_VERSION

- Updated chart version for both proxy and dashboard charts
- Charts remain version-locked at $NEW_VERSION
- App version unchanged (no new Docker image needed)"
fi

# Commit changes
git add $FILES_TO_COMMIT
git commit -m "$COMMIT_MESSAGE"

# Create and push tag with different formats for chart vs app
if [[ "$TARGET_TYPE" == "app" ]]; then
    TAG_NAME="v$NEW_VERSION"
    git tag $TAG_NAME
    print_status "Created app version tag $TAG_NAME"
else
    TAG_NAME="chart-v$NEW_VERSION"
    git tag $TAG_NAME
    print_status "Created chart version tag $TAG_NAME"
fi

# Push changes and tag
git push origin main
git push origin $TAG_NAME

print_status "Pushed changes and tag to remote"

print_status "Version bump complete! 🎉"

if [[ "$TARGET_TYPE" == "app" ]]; then
    print_status "GitHub Actions will now build and publish ghcr.io/rixau/mullvad-kubernetes:$NEW_VERSION"
    print_status "Tagged as: $TAG_NAME"
    print_status "Both proxy and dashboard charts updated with new appVersion"
    print_warning "Remember to update Flux HelmRelease if needed (chart version may need updating too)"
else
    print_status "Chart versions updated - ready for Flux deployment"
    print_status "Tagged as: $TAG_NAME"
    print_status "Both proxy and dashboard charts are version-locked at $NEW_VERSION"
    print_status "No new Docker image will be built (app version unchanged)"
fi

