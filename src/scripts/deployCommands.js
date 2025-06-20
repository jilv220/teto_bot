import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { REST, Routes } from 'discord.js';
import { Effect } from 'effect';
import { appConfig } from '../services/config.js';

const { botToken, clientId, devGuildId } = await Effect.runPromise(appConfig)

const commands = [];
// Grab all the command files from the commands directory
const commandsPath = join(__dirname, '../commands');
console.log(commandsPath)
const commandFiles = readdirSync(commandsPath).filter(file => file.endsWith('.js') || file.endsWith('.ts'));

// Grab the SlashCommandBuilder#toJSON() output of each command's data for deployment
for (const file of commandFiles) {
    const filePath = join(commandsPath, file);
    const command = await import(filePath);

    if ('data' in command && 'execute' in command) {
        commands.push(command.data.toJSON());
    } else {
        console.log(`[WARNING] The command at ${filePath} is missing a required "data" or "execute" property.`);
    }
}

// Construct and prepare an instance of the REST module
const rest = new REST().setToken(botToken);

// and deploy your commands!
(async () => {
    try {
        console.log(`Started refreshing ${commands.length} application (/) commands.`);

        const isProduction = process.env.NODE_ENV === "production" || false
        const applicationCommands = isProduction ?
            Routes.applicationCommands(clientId) : Routes.applicationGuildCommands(clientId, devGuildId)

        // The put method is used to fully refresh all commands in the guild with the current set
        const data = await rest.put(
            applicationCommands,
            { body: commands },
        );

        console.log(`Successfully reloaded ${data.length} application (/) commands.`);
    } catch (error) {
        // And of course, make sure you catch and log any errors!
        console.error(error);
    }
})();