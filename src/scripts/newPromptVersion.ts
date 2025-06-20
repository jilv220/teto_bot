#!/usr/bin/env bun

import { mkdir } from 'node:fs/promises'
import {
  PromptVersionError,
  createBlankTemplate,
  getAvailableVersions,
  getLatestVersion,
  getVersion,
  readPromptVersion,
  writePromptVersion,
} from '../utils/promptVersioning'

interface ScriptOptions {
  version: string
  from?: string
  blank?: boolean
  help?: boolean
}

function parseArgs(): ScriptOptions {
  const args = process.argv.slice(2)
  const options: Partial<ScriptOptions> = {}

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg === '--from' || arg === '-f') {
      if (i + 1 < args.length) {
        options.from = args[i + 1]
        i++ // Skip the next argument as it's the from version value
      } else {
        throw new Error('--from requires a version number (e.g., 1.2.3)')
      }
    } else if (arg === '--blank' || arg === '-b') {
      options.blank = true
    } else if (arg === '--help' || arg === '-h') {
      options.help = true
    } else if (!options.version && !arg.startsWith('-')) {
      // First non-flag argument is the version
      options.version = arg
    }
  }

  if (!options.version && !options.help) {
    throw new Error('Version number is required (e.g., 1.2.0)')
  }

  return options as ScriptOptions
}

function showHelp() {
  console.log(`
Usage: bun run src/scripts/newPromptVersion.ts <version> [options]

Create a new prompt version file with semantic versioning.

Arguments:
  <version>              Version number in format major.minor.patch (e.g., 1.2.0)

Options:
  --from, -f <version>   Copy from a specific version instead of latest
  --blank, -b            Create a blank template instead of copying
  --help, -h             Show this help message

Examples:
  # Copy from latest version
  bun run src/scripts/newPromptVersion.ts 1.2.0

  # Copy from specific version
  bun run src/scripts/newPromptVersion.ts 1.2.0 --from 1.1.0

  # Create blank template
  bun run src/scripts/newPromptVersion.ts 1.2.0 --blank

  # Show help
  bun run src/scripts/newPromptVersion.ts --help
`)
}

async function createNewVersion(
  targetVersion: string,
  fromVersion?: string,
  blank?: boolean
) {
  try {
    // Ensure prompts directory exists
    const version = await getVersion(targetVersion)
    await mkdir(new URL('../../priv/prompts/', import.meta.url), {
      recursive: true,
    })

    // Check if target version already exists
    const existingVersions = await getAvailableVersions()
    const versionExists = existingVersions.some(
      (v) => v.version === targetVersion
    )

    if (versionExists) {
      console.error(`Error: Version ${targetVersion} already exists`)
      console.log('\nExisting versions:')
      for (const v of existingVersions.slice(0, 5)) {
        console.log(`  v${v.version}`)
      }
      process.exit(1)
    }

    let content: string

    if (blank) {
      console.log(`Creating blank template for v${targetVersion}...`)
      content = createBlankTemplate()
    } else {
      let sourceVersion:
        | Awaited<ReturnType<typeof getVersion>>
        | Awaited<ReturnType<typeof getLatestVersion>>

      if (fromVersion) {
        console.log(`Copying from specified version: ${fromVersion}`)
        sourceVersion = await getVersion(fromVersion)
      } else {
        console.log('Copying from latest version...')
        sourceVersion = await getLatestVersion()

        if (!sourceVersion) {
          console.log('No existing versions found, creating blank template...')
          content = createBlankTemplate()
        }
      }

      if (sourceVersion) {
        console.log(`Reading source version v${sourceVersion.version}...`)
        content = await readPromptVersion(sourceVersion)

        // Add version comment at the top
        const versionHeader = `<!-- Copied from v${sourceVersion.version} on ${new Date().toISOString()} -->\n\n`
        content = versionHeader + content
      } else {
        content = createBlankTemplate()
      }
    }

    console.log(`Writing new version to ${version.filePath}...`)
    await writePromptVersion(version, content)

    console.log(`✓ Successfully created prompt version v${targetVersion}`)
    console.log(`  File: ${version.filePath}`)
    console.log(`  Size: ${content.length} characters`)

    // Show some guidance
    console.log('\nNext steps:')
    console.log(`1. Edit the prompt: ${version.filePath}`)
    console.log(
      `2. Update the system: bun run src/scripts/updatePrompt.ts --version ${targetVersion}`
    )
    console.log('3. Test your changes')

    // Show current versions
    const updatedVersions = await getAvailableVersions()
    console.log('\nAvailable versions:')
    for (const v of updatedVersions.slice(0, 3)) {
      const marker = v.version === targetVersion ? ' (NEW)' : ''
      console.log(`  v${v.version}${marker}`)
    }
  } catch (error) {
    if (error instanceof PromptVersionError) {
      console.error(`Error: ${error.message}`)
      process.exit(1)
    }

    console.error('Failed to create new prompt version:', error)
    process.exit(1)
  }
}

async function main() {
  try {
    const options = parseArgs()

    if (options.help) {
      showHelp()
      return
    }

    await createNewVersion(options.version, options.from, options.blank)
  } catch (error) {
    if (error instanceof Error) {
      console.error('Error:', error.message)
      console.log('\nUse --help for usage information')
      process.exit(1)
    }
    throw error
  }
}

// Run the script if called directly
if (import.meta.main) {
  main().catch((error) => {
    console.error('Unexpected error:', error)
    process.exit(1)
  })
}

export { createNewVersion }
