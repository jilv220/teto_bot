#!/usr/bin/env bun

import {
  PromptVersionError,
  getAvailableVersions,
} from '../utils/promptVersioning'

interface ScriptOptions {
  list?: boolean
  help?: boolean
}

function parseArgs(): ScriptOptions {
  const args = process.argv.slice(2)
  const options: ScriptOptions = {}

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg === '--list' || arg === '-l') {
      options.list = true
    } else if (arg === '--help' || arg === '-h') {
      options.help = true
    }
  }

  return options
}

function showHelp() {
  console.log(`
Usage: bun run src/scripts/listPromptVersions.ts [options]

List all available prompt versions in the prompts directory.

Options:
  --list, -l     List all available versions (default behavior)
  --help, -h     Show this help message

Examples:
  bun run src/scripts/listPromptVersions.ts
  bun run src/scripts/listPromptVersions.ts --list
`)
}

async function listVersions() {
  try {
    const versions = await getAvailableVersions()

    if (versions.length === 0) {
      console.log('No prompt versions found in src/priv/prompts/')
      console.log('\nTo create your first version, run:')
      console.log('  bun run src/scripts/newPromptVersion.ts 1.0.0')
      return
    }

    console.log('\nAvailable Prompt Versions:')
    console.log('='.repeat(50))

    for (let i = 0; i < versions.length; i++) {
      const version = versions[i]
      const isLatest = i === 0
      const marker = isLatest ? ' (LATEST)' : ''
      const status = version.exists ? '✓' : '✗'

      console.log(`${status} v${version.version}${marker}`)
    }

    console.log('='.repeat(50))
    console.log(`Total versions: ${versions.length}`)

    if (versions.length > 0) {
      console.log(`\nLatest version: v${versions[0].version}`)
      console.log('\nTo use a specific version:')
      console.log(
        `  bun run src/scripts/updatePrompt.ts --version ${versions[0].version}`
      )
      console.log('\nTo use the latest version:')
      console.log('  bun run src/scripts/updatePrompt.ts')
    }
  } catch (error) {
    if (error instanceof PromptVersionError) {
      console.error(`Error: ${error.message}`)
      process.exit(1)
    }
    throw error
  }
}

async function main() {
  const options = parseArgs()

  if (options.help) {
    showHelp()
    return
  }

  await listVersions()
}

// Run the script if called directly
if (import.meta.main) {
  main().catch((error) => {
    console.error('Unexpected error:', error)
    process.exit(1)
  })
}

export { listVersions }
