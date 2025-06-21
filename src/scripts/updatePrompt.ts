#!/usr/bin/env bun

import { discordOpsApi, systemPromptApi } from '../services'
import {
  PromptVersionError,
  getLatestVersion,
  getVersion,
  readPromptVersion,
} from '../utils/promptVersioning'

interface ScriptOptions {
  version?: string
  help?: boolean
}

function parseArgs(): ScriptOptions {
  const args = process.argv.slice(2)
  const options: ScriptOptions = {}

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg === '--version' || arg === '-v') {
      if (i + 1 < args.length) {
        options.version = args[i + 1]
        i++ // Skip the next argument as it's the version value
      } else {
        throw new Error('--version requires a version number (e.g., 1.2.3)')
      }
    } else if (arg === '--help' || arg === '-h') {
      options.help = true
    }
  }

  return options
}

function showHelp() {
  console.log(`
Usage: bun run src/scripts/updatePrompt.ts [options]

Update the system prompt in Redis from a versioned prompt file.

Options:
  --version, -v <version>  Use a specific version (e.g., 1.2.3)
  --help, -h              Show this help message

Examples:
  # Use the latest version
  bun run src/scripts/updatePrompt.ts

  # Use a specific version
  bun run src/scripts/updatePrompt.ts --version 1.2.3

  # Show help
  bun run src/scripts/updatePrompt.ts --help
`)
}

async function updatePrompt(versionString?: string) {
  try {
    let version:
      | Awaited<ReturnType<typeof getVersion>>
      | Awaited<ReturnType<typeof getLatestVersion>>

    if (versionString) {
      console.log(`Using specified version: ${versionString}`)
      version = await getVersion(versionString)
    } else {
      console.log('Using latest version...')
      version = await getLatestVersion()

      if (!version) {
        console.error('No prompt versions found in src/priv/prompts/')
        console.log('\nTo create your first version, run:')
        console.log('  bun run src/scripts/newPromptVersion.ts 1.0.0')
        process.exit(1)
      }
    }

    console.log(`Reading prompt from v${version.version}...`)
    const promptContent = await readPromptVersion(version)

    if (!promptContent.trim()) {
      console.error(`Warning: Prompt version ${version.version} is empty`)
      process.exit(1)
    }

    console.log('Updating system prompt in Redis...')
    console.log(
      `Prompt preview (first 200 chars): ${promptContent.slice(0, 200)}...`
    )

    const response = await systemPromptApi.setSystemPrompt(promptContent)

    // Check if response is successful (not an error)
    if ('success' in response && response.success) {
      console.log(`✓ Successfully updated system prompt to v${version.version}`)
      console.log(`  Message: ${response.message}`)

      // Show some stats
      const wordCount = promptContent.split(/\s+/).length
      const charCount = promptContent.length
      console.log('\nPrompt Statistics:')
      console.log(`  Version: v${version.version}`)
      console.log(`  Characters: ${charCount}`)
      console.log(`  Words: ${wordCount}`)
      console.log(`  File: ${version.filePath}`)
    }
  } catch (error) {
    if (error instanceof PromptVersionError) {
      console.error(`Error: ${error.message}`)
      process.exit(1)
    }

    console.error('Failed to update system prompt:', error)
    process.exit(1)
  }
}

async function main() {
  const options = parseArgs()

  if (options.help) {
    showHelp()
    return
  }

  await updatePrompt(options.version)
}

// Run the script if called directly
if (import.meta.main) {
  main().catch((error) => {
    console.error('Unexpected error:', error)
    process.exit(1)
  })
}

export { updatePrompt }
