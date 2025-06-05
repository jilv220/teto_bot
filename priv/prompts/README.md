# Prompt Versioning System

This directory contains versioned system prompts for the Teto Bot. The versioning system allows you to maintain multiple versions of your system prompt and easily switch between them.

## File Naming Convention

Prompt files must follow the semantic versioning format:

- `v{major}.{minor}.{patch}.md`
- Examples: `v1.0.0.md`, `v1.2.3.md`, `v2.0.0.md`

## Available Commands

### List Available Versions

```bash
mix update_prompt --list
```

Shows all available prompt versions, with the latest marked.

### Update System Prompt

```bash
# Use the latest version
mix update_prompt

# Use a specific version
mix update_prompt --version 1.2.3
```

Updates the system prompt in Redis from the specified version.

### Create New Version

```bash
# Copy from latest version
mix new_prompt_version 1.2.0

# Copy from specific version
mix new_prompt_version 1.2.0 --from 1.1.0

# Create blank template
mix new_prompt_version 1.2.0 --blank
```

## Workflow

1. **Create a new version**: `mix new_prompt_version 1.1.0`
2. **Edit the new version**: Modify `priv/prompts/v1.1.0.md`
3. **Update the system**: `mix update_prompt --version 1.1.0`
4. **Test your changes**: The bot will now use the new prompt
5. **Make it default**: Since versions are sorted semantically, v1.1.0 becomes the new latest

## Version Sorting

Versions are sorted using semantic versioning rules:

- Latest version appears first in listings
- `mix update_prompt` without arguments uses the latest version
- Higher major.minor.patch numbers are considered newer

## Best Practices

- Use semantic versioning appropriately:
  - **Major** (2.0.0): Breaking changes to prompt structure
  - **Minor** (1.1.0): New features or significant additions
  - **Patch** (1.0.1): Small fixes or tweaks
- Always test new versions before deploying to production
- Keep meaningful commit messages when versioning prompts
- Consider backing up important versions
