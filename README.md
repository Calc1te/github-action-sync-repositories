# GitHub Action: Sync Repositories

A GitHub Action to seamlessly push and sync files from one repository to another.

This action is a fork of [cpina/github-action-push-to-another-repository](https://github.com/cpina/github-action-push-to-another-repository), enhanced with two new features:

1. **Multiple Directory Mapping**
2. **File Filtering (Glob Matching)**

> **Note:** For all base functionalities (including general examples, FAQ, and troubleshooting), please refer to the [original extensive documentation](https://cpina.github.io/push-to-another-repository-docs/).

---

## New Features

### 1. Multiple Directory Support

For scenarios where need to sync more than one folder, you can now specify multiple source and target directories simultaneously.

**How to use:** Separate the directory paths with a space.

```yaml
    - name: Push to another repo
      uses: Calc1te/github-action-sync-repositories@main
      env:
        SSH_DEPLOY_KEY: ${{ secrets.SSH_DEPLOY_KEY }}
        API_TOKEN_GITHUB: ${{ secrets.API_TOKEN_GITHUB }}
      with:
        # Separate multiple directories with a space
        source-directory: 'Application src docs' 
        # If omitted, target-directory will default to the exact same paths as source-directory
        target-directory: 'Application src docs'
```

### 2. Glob Matching (File Filtering)

You can selectively control exactly which files or directories to sync by providing an include-patterns-file.

Default Behavior: When this file is used, all files are excluded by default. Only the patterns you explicitly define will be synced.

File Location: The pattern file must be present in your repository's workspace (e.g., in the root folder). Do not put it inside the .github/workflows/ directory.

Example Workflow:

```yaml
- name: Sync to another repository
      uses: Calc1te/github-action-sync-repositories@main
      env:
        SSH_DEPLOY_KEY: ${{ secrets.SSH_DEPLOY_KEY }}
      with:
        destination-github-username: 'target-user'
        destination-repository-name: 'target-repo'
        # Point to your include patterns file here
        include-patterns-file: 'sync_patterns'
```

#### Syntax for sync_patterns

The configuration file uses rsync filter syntax. Here are the most common and useful examples to get you started:

```bash
# Match a specific file
+ config.json

# Match all .c files in the root directory
+ *.c

# Match ONLY the direct children of a directory (1 level deep)
+ path/to/somewhere/*

# Match ALL files and folders recursively inside a specific directory
+ path/to/somewhere/***
```

## sample action.yml

```yml
name: Sync
jobs:
  sync:
    runs-on: ubuntu-latest
    container: pandoc/latex

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Push to another repo
        uses: Calc1te/github-action-push-to-another-repository@main
        env:
          SSH_DEPLOY_KEY: ${{ secrets.SSH_DEPLOY_KEY }}
          API_TOKEN_GITHUB: ${{ secrets.API_TOKEN_GITHUB }}
        with:
          include-patterns-file: 'sync_files'
          destination-github-username: 'John_Doe'
          destination-repository-name: 'repository_1'
          user-email: johnDoe@example.com
          target-branch: main
```
