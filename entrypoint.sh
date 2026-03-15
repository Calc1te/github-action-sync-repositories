#!/bin/sh -l

set -e  # if a command fails it stops the execution
set -u  # script fails if trying to access to an undefined variable

echo "[+] Action start"
SOURCE_BEFORE_DIRECTORY="${1}"
SOURCE_DIRECTORY="${2}"
DESTINATION_GITHUB_USERNAME="${3}"
DESTINATION_REPOSITORY_NAME="${4}"
GITHUB_SERVER="${5}"
USER_EMAIL="${6}"
USER_NAME="${7}"
DESTINATION_REPOSITORY_USERNAME="${8}"
TARGET_BRANCH="${9}"
COMMIT_MESSAGE="${10}"
TARGET_DIRECTORY="${11}"
CREATE_TARGET_BRANCH_IF_NEEDED="${12}"
INCLUDE_PATTERNS_FILE="${13:-}"

if [ -z "$DESTINATION_REPOSITORY_USERNAME" ]
then
	DESTINATION_REPOSITORY_USERNAME="$DESTINATION_GITHUB_USERNAME"
fi

if [ -z "$USER_NAME" ]
then
	USER_NAME="$DESTINATION_GITHUB_USERNAME"
fi

# Verify that there (potentially) some access to the destination repository
# and set up git (with GIT_CMD variable) and GIT_CMD_REPOSITORY
if [ -n "${SSH_DEPLOY_KEY:=}" ]
then
	echo "[+] Using SSH_DEPLOY_KEY"

	# Inspired by https://github.com/leigholiver/commit-with-deploy-key/blob/main/entrypoint.sh , thanks!
	mkdir --parents "$HOME/.ssh"
	DEPLOY_KEY_FILE="$HOME/.ssh/deploy_key"
	echo "${SSH_DEPLOY_KEY}" > "$DEPLOY_KEY_FILE"
	chmod 600 "$DEPLOY_KEY_FILE"

	SSH_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
	ssh-keyscan -H "$GITHUB_SERVER" > "$SSH_KNOWN_HOSTS_FILE"

	export GIT_SSH_COMMAND="ssh -i "$DEPLOY_KEY_FILE" -o UserKnownHostsFile=$SSH_KNOWN_HOSTS_FILE"

	GIT_CMD_REPOSITORY="git@$GITHUB_SERVER:$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME.git"

elif [ -n "${API_TOKEN_GITHUB:=}" ]
then
	echo "[+] Using API_TOKEN_GITHUB"
	GIT_CMD_REPOSITORY="https://$DESTINATION_REPOSITORY_USERNAME:$API_TOKEN_GITHUB@$GITHUB_SERVER/$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME.git"
else
	echo "::error::API_TOKEN_GITHUB and SSH_DEPLOY_KEY are empty. Please fill one (recommended the SSH_DEPLOY_KEY)"
	exit 1
fi


CLONE_DIR=$(mktemp -d)

echo "[+] Git version"
git --version

echo "[+] Enable git lfs"
git lfs install

echo "[+] Cloning destination git repository $DESTINATION_REPOSITORY_NAME"

# Setup git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

# workaround for https://github.com/cpina/github-action-push-to-another-repository/issues/103
git config --global http.version HTTP/1.1

{
	git clone --single-branch --depth 1 --branch "$TARGET_BRANCH" "$GIT_CMD_REPOSITORY" "$CLONE_DIR"
} || {
    if [ "$CREATE_TARGET_BRANCH_IF_NEEDED" = "true" ]
    then
        # Default branch of the repository is cloned. Later on the required branch
	# will be created
        git clone --single-branch --depth 1 "$GIT_CMD_REPOSITORY" "$CLONE_DIR"
    else
        false
    fi
} || {
	echo "::error::Could not clone the destination repository. Command:"
	echo "::error::git clone --single-branch --branch $TARGET_BRANCH $GIT_CMD_REPOSITORY $CLONE_DIR"
	echo "::error::(Note that if they exist USER_NAME and API_TOKEN is redacted by GitHub)"
	echo "::error::Please verify that the target repository exist AND that it contains the destination branch name, and is accesible by the API_TOKEN_GITHUB OR SSH_DEPLOY_KEY"
	exit 1

}
ls -la "$CLONE_DIR"

echo "[+] Listing Current Directory Location"
ls -al

echo "[+] Listing root Location"
ls -al /

# -------------------------------------------------------------
# Handle multi-repository pushing if multiple target directories
# and destination repositories are provided
# -------------------------------------------------------------

TGT_STR="$TARGET_DIRECTORY "
# Create a string for destination repos just in case we want to split them, but we will mostly just map them
DEST_REPOS_STR="$DESTINATION_REPOSITORY_NAME "

# Create a master clone dir to hold multiple clones if needed
MASTER_CLONE_DIR=$(mktemp -d)

# We will loop over destination repos if space separated, or just use one
for DEST_REPO in $DESTINATION_REPOSITORY_NAME; do
	
	CURRENT_CLONE_DIR="$MASTER_CLONE_DIR/$DEST_REPO"
	mkdir -p "$CURRENT_CLONE_DIR"
	
	echo "[+] Setting up push for $DEST_REPO"
	
	if [ -n "${SSH_DEPLOY_KEY:=}" ]
	then
		CURRENT_GIT_CMD_REPOSITORY="git@$GITHUB_SERVER:$DESTINATION_REPOSITORY_USERNAME/$DEST_REPO.git"
	else
		CURRENT_GIT_CMD_REPOSITORY="https://$DESTINATION_REPOSITORY_USERNAME:$API_TOKEN_GITHUB@$GITHUB_SERVER/$DESTINATION_REPOSITORY_USERNAME/$DEST_REPO.git"
	fi
	
	{
		git clone --single-branch --depth 1 --branch "$TARGET_BRANCH" "$CURRENT_GIT_CMD_REPOSITORY" "$CURRENT_CLONE_DIR"
	} || {
		if [ "$CREATE_TARGET_BRANCH_IF_NEEDED" = "true" ]
		then
			git clone --single-branch --depth 1 "$CURRENT_GIT_CMD_REPOSITORY" "$CURRENT_CLONE_DIR"
		else
			false
		fi
	} || {
		echo "::error::Could not clone the destination repository $DEST_REPO."
		exit 1
	}
	
	# Related to safe directory
	git config --global --add safe.directory "$CURRENT_CLONE_DIR"
	
	# Loop over source directories (we apply ALL source directories to each target repo inside this loop as a one-to-one mapping if space separated)
	TEMP_TGT_STR="$TARGET_DIRECTORY "
	
	for SRC_DIR in $SOURCE_DIRECTORY; do
		if [ -z "$TARGET_DIRECTORY" ]; then
			TGT_DIR="$SRC_DIR"
		else
			TGT_DIR="${TEMP_TGT_STR%% *}"
			TEMP_TGT_STR="${TEMP_TGT_STR#* }"
		fi

		echo "[+] List contents of $SRC_DIR"
		ls -a "$SRC_DIR" || true

		echo "[+] Checking if local $SRC_DIR exist"
		if [ ! -d "$SRC_DIR" ]
		then
			echo "ERROR: $SRC_DIR does not exist"
			exit 1
		fi

		ABSOLUTE_TARGET_DIRECTORY="$CURRENT_CLONE_DIR/$TGT_DIR/"
		
		echo "[+] Creating $ABSOLUTE_TARGET_DIRECTORY if it doesn't exist"
		mkdir -p "$ABSOLUTE_TARGET_DIRECTORY"
		
		echo "[+] Copying contents of source repository folder "$SRC_DIR" to folder "$TGT_DIR" in git repo $DEST_REPO"
		
		if [ -n "$INCLUDE_PATTERNS_FILE" ] && [ -f "$INCLUDE_PATTERNS_FILE" ]; then
			echo "[+] Using include patterns file: $INCLUDE_PATTERNS_FILE"
			rsync -a --prune-empty-dirs --include="*/" --include-from="$INCLUDE_PATTERNS_FILE" --exclude="*" "$SRC_DIR/" "$ABSOLUTE_TARGET_DIRECTORY/"
		else
			cp -ra "$SRC_DIR"/. "$ABSOLUTE_TARGET_DIRECTORY"
		fi
	done

	cd "$CURRENT_CLONE_DIR"

	echo "[+] Files that will be pushed to $DEST_REPO"
	ls -la

	if [ "$CREATE_TARGET_BRANCH_IF_NEEDED" = "true" ]
	then
		echo "[+] Switch to the TARGET_BRANCH"
		git switch -c "$TARGET_BRANCH" || true
	fi

	echo "[+] Adding git commit"
	git add .

	echo "[+] git status:"
	git status

	echo "[+] git diff-index:"
	git diff-index --quiet HEAD || git commit --message "$COMMIT_MESSAGE" --allow-empty-message

	echo "[+] Pushing git commit to $DEST_REPO"
	git push "$CURRENT_GIT_CMD_REPOSITORY" --set-upstream "$TARGET_BRANCH"
	
	cd - > /dev/null
done

echo "[+] All pushes completed successfully"
exit 0

# Detect circular loops by checking if the upstream commit title already has our sync prefix
if [[ "$UPSTREAM_TITLE" == "\[sync\]"* ]]; then
	echo "::warning::The current commit is already a sync commit ('$UPSTREAM_TITLE'). Aborting push to prevent infinite loop."
	exit 0
fi

if [ -z "$UPSTREAM_TITLE" ]; then
	UPSTREAM_TITLE="Update from $GITHUB_REPOSITORY"
fi

if [ "$COMMIT_MESSAGE" = "Update from ORIGIN_COMMIT" ] || [ -z "$COMMIT_MESSAGE" ]; then
	ORIGIN_COMMIT_URL="https://$GITHUB_SERVER/$GITHUB_REPOSITORY/commit/$GITHUB_SHA"
	COMMIT_MESSAGE="[sync] $UPSTREAM_TITLE
	
$UPSTREAM_BODY

Upstream-commit: $ORIGIN_COMMIT_URL"
else
	ORIGIN_COMMIT="https://$GITHUB_SERVER/$GITHUB_REPOSITORY/commit/$GITHUB_SHA"
	COMMIT_MESSAGE="${COMMIT_MESSAGE/ORIGIN_COMMIT/$ORIGIN_COMMIT}"
	COMMIT_MESSAGE="${COMMIT_MESSAGE/\$GITHUB_REF/$GITHUB_REF}"
fi

# Trim any trailing whitespace / empty vars so git commit ignores it correctly
if [ -z "$(echo -n "$COMMIT_MESSAGE" | awk '{$1=$1};1')" ]; then
     COMMIT_MESSAGE="Update from $GITHUB_REPOSITORY"
fi

echo "[+] Commit message is set to: $COMMIT_MESSAGE"
