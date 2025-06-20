# Prompt Versioning System

This directory contains versioned system prompts for the Teto Bot. The versioning system allows you to maintain multiple versions of your system prompt and easily switch between them.

## File Naming Convention

Prompt files must follow the semantic versioning format:

- `v{major}.{minor}.{patch}.md`
- Examples: `v1.0.0.md`, `v1.2.3.md`, `v2.0.0.md`

## Available Commands

### List Available Versions

```bash
bun run src/scripts/listPromptVersions.ts
```

Shows all available prompt versions, with the latest marked.

### Update System Prompt

```bash
# Use the latest version
bun run src/scripts/updatePrompt.ts

# Use a specific version
bun run src/scripts/updatePrompt.ts --version 1.2.3
```

Updates the system prompt in Redis from the specified version.

### Create New Version

```bash
# Copy from latest version
bun run src/scripts/newPromptVersion.ts 1.2.0

# Copy from specific version
bun run src/scripts/newPromptVersion.ts 1.2.0 --from 1.1.0

# Create blank template
bun run src/scripts/newPromptVersion.ts 1.2.0 --blank
```

## Workflow

1. **Create a new version**: `bun run src/scripts/newPromptVersion.ts 1.1.0`
2. **Edit the new version**: Modify `src/priv/prompts/v1.1.0.md`
3. **Update the system**: `bun run src/scripts/updatePrompt.ts --version 1.1.0`
4. **Test your changes**: The bot will now use the new prompt
5. **Make it default**: Since versions are sorted semantically, v1.1.0 becomes the new latest

## Version Sorting

Versions are sorted using semantic versioning rules:

- Latest version appears first in listings
- `bun run src/scripts/updatePrompt.ts` without arguments uses the latest version
- Higher major.minor.patch numbers are considered newer

## Best Practices

- Use semantic versioning appropriately:
  - **Major** (2.0.0): Breaking changes to prompt structure
  - **Minor** (1.1.0): New features or significant additions
  - **Patch** (1.0.1): Small fixes or tweaks
- Always test new versions before deploying to production
- Keep meaningful commit messages when versioning prompts
- Consider backing up important versions

## Command Reference

### List Versions

```bash
# List all versions
bun run src/scripts/listPromptVersions.ts

# Show help
bun run src/scripts/listPromptVersions.ts --help
```

### Update System Prompt

```bash
# Use latest version
bun run src/scripts/updatePrompt.ts

# Use specific version
bun run src/scripts/updatePrompt.ts --version 1.2.3

# Show help
bun run src/scripts/updatePrompt.ts --help
```

### Create New Version

```bash
# Copy from latest
bun run src/scripts/newPromptVersion.ts 1.2.0

# Copy from specific version
bun run src/scripts/newPromptVersion.ts 1.2.0 --from 1.1.0

# Create blank template
bun run src/scripts/newPromptVersion.ts 1.2.0 --blank

# Show help
bun run src/scripts/newPromptVersion.ts --help
```

## Directory Structure

```
src/priv/prompts/
├── README.md          # This file
├── v1.0.0.md         # Version 1.0.0
├── v1.1.0.md         # Version 1.1.0
└── v2.0.0.md         # Version 2.0.0
```

## Example Prompt File Structure

Each prompt file should contain:

```markdown
# System Prompt

Your system prompt content here...

## Guidelines

- Be clear and specific about the AI's role
- Include behavioral guidelines
- Consider the context of use

## Version Notes

- Created on: 2024-01-01T00:00:00.000Z
- Purpose: Initial version with basic personality
- Changes: Added more context about user intimacy levels
```

## Integration

The system integrates with:

- **Redis**: Stores the active system prompt
- **LangChain**: Uses the prompt for AI conversations
- **Discord Bot**: Applied to all bot interactions

## Troubleshooting

### No versions found

If you see "No prompt versions found", create your first version:

```bash
bun run src/scripts/newPromptVersion.ts 1.0.0 --blank
```

### Version already exists

If a version already exists, either:

- Use a different version number
- Delete the existing file if you want to recreate it

### API errors

If the update fails:

- Check your API connection
- Verify the prompt content is valid
- Ensure the bot has proper permissions

## Development

The versioning system is built with:

- **TypeScript**: For type safety
- **Bun**: Runtime and package manager
- **Semantic Versioning**: For version management
- **File System**: For prompt storage

Key files:

- `src/utils/promptVersioning.ts`: Core utilities
- `src/scripts/listPromptVersions.ts`: List command
- `src/scripts/updatePrompt.ts`: Update command
- `src/scripts/newPromptVersion.ts`: Create command
