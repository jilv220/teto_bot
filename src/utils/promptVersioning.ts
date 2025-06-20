import { readFile, readdir, writeFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'

export interface PromptVersion {
  version: string
  major: number
  minor: number
  patch: number
  filePath: string
  exists: boolean
}

export class PromptVersionError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'PromptVersionError'
  }
}

const PROMPTS_DIR = resolve(process.cwd(), 'src', 'priv', 'prompts')
const VERSION_REGEX = /^v(\d+)\.(\d+)\.(\d+)\.md$/

/**
 * Parse a semantic version string into components
 */
export function parseVersion(versionString: string): {
  major: number
  minor: number
  patch: number
} {
  const match = versionString.match(/^(\d+)\.(\d+)\.(\d+)$/)
  if (!match) {
    throw new PromptVersionError(
      `Invalid version format: ${versionString}. Expected format: major.minor.patch (e.g., 1.2.3)`
    )
  }

  return {
    major: Number.parseInt(match[1], 10),
    minor: Number.parseInt(match[2], 10),
    patch: Number.parseInt(match[3], 10),
  }
}

/**
 * Compare two semantic versions
 * Returns: -1 if a < b, 0 if a === b, 1 if a > b
 */
export function compareVersions(a: PromptVersion, b: PromptVersion): number {
  if (a.major !== b.major) return a.major - b.major
  if (a.minor !== b.minor) return a.minor - b.minor
  return a.patch - b.patch
}

/**
 * Get all available prompt versions from the prompts directory
 */
export async function getAvailableVersions(): Promise<PromptVersion[]> {
  try {
    const files = await readdir(PROMPTS_DIR)
    const versions: PromptVersion[] = []

    for (const file of files) {
      const match = file.match(VERSION_REGEX)
      if (match) {
        const major = Number.parseInt(match[1], 10)
        const minor = Number.parseInt(match[2], 10)
        const patch = Number.parseInt(match[3], 10)
        const version = `${major}.${minor}.${patch}`

        versions.push({
          version,
          major,
          minor,
          patch,
          filePath: join(PROMPTS_DIR, file),
          exists: true,
        })
      }
    }

    // Sort by semantic version (latest first)
    return versions.sort((a, b) => compareVersions(b, a))
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      return []
    }
    throw new PromptVersionError(`Failed to read prompts directory: ${error}`)
  }
}

/**
 * Get the latest available prompt version
 */
export async function getLatestVersion(): Promise<PromptVersion | null> {
  const versions = await getAvailableVersions()
  return versions.length > 0 ? versions[0] : null
}

/**
 * Get a specific prompt version
 */
export async function getVersion(
  versionString: string
): Promise<PromptVersion> {
  const { major, minor, patch } = parseVersion(versionString)
  const filename = `v${major}.${minor}.${patch}.md`
  const filePath = join(PROMPTS_DIR, filename)

  return {
    version: versionString,
    major,
    minor,
    patch,
    filePath,
    exists: true, // We'll validate existence when reading
  }
}

/**
 * Read prompt content from a version file
 */
export async function readPromptVersion(
  version: PromptVersion
): Promise<string> {
  try {
    return await readFile(version.filePath, 'utf-8')
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      throw new PromptVersionError(
        `Prompt version ${version.version} does not exist`
      )
    }
    throw new PromptVersionError(
      `Failed to read prompt version ${version.version}: ${error}`
    )
  }
}

/**
 * Write prompt content to a version file
 */
export async function writePromptVersion(
  version: PromptVersion,
  content: string
): Promise<void> {
  try {
    await writeFile(version.filePath, content, 'utf-8')
  } catch (error) {
    throw new PromptVersionError(
      `Failed to write prompt version ${version.version}: ${error}`
    )
  }
}

/**
 * Create the default blank template for a new prompt version
 */
export function createBlankTemplate(): string {
  return `# System Prompt

Write your system prompt here. This prompt will be used to guide the AI's behavior and responses.

## Guidelines

- Be clear and specific about the AI's role and capabilities
- Include any important behavioral guidelines
- Consider the context in which this prompt will be used

## Version Notes

- Created on: ${new Date().toISOString()}
- Purpose: [Describe the purpose of this version]

---

[Your prompt content goes here]
`
}

/**
 * Get the filename for a prompt version
 */
export function getVersionFilename(versionString: string): string {
  const { major, minor, patch } = parseVersion(versionString)
  return `v${major}.${minor}.${patch}.md`
}

/**
 * Get the full file path for a prompt version
 */
export function getVersionFilePath(versionString: string): string {
  const filename = getVersionFilename(versionString)
  return join(PROMPTS_DIR, filename)
}
