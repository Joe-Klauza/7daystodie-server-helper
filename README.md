# 7DaysToDie Server Helper
7DaysToDie Server Helper makes running your own 7DaysToDie server simple. It comes with an optional Discord bot to help administer the server remotely.

# Prerequisites
- [Docker](https://docs.docker.com/get-docker/) (or [Podman](https://podman.io/getting-started/installation))
- [Docker Compose](https://docs.docker.com/compose/install/) (or [Podman Compose](https://github.com/containers/podman-compose))

# Setup
1. Clone or download this repository
1. Copy `docker-compose.yml` to `docker-compose.override.yml` and modify its contents to suit your needs
1. In a shell where docker-compose is on the `PATH`, build the container:
    - ```bash
      docker-compose build
      ```

# Starting the server
The server is run via `docker-compose`. Several volumes store SteamCMD, `rbenv`, server files, and world files to reduce time needed to restart the container (or run multiple containers). The Discord bot code is also mounted in a volume to allow updates without server downtime.
1. Run/restart the container (detached)
    - ```bash
      docker-compose up -d --force-recreate
      ```
1. Stop/rm the container
    - ```bash
      docker-compose down
      ```

# Setting up the optional 7DaysToDie Discord bot
1. Create a new Application for your Discord account [here](https://discord.com/developers/applications)
1. Create a Bot for your application and copy its secret token, pasting it in the `docker-compose.override.yaml`:
    - ```yaml
      SEVENDAYSTODIE_BOT_TOKEN: YOUR_BOT_TOKEN
      ```
1. Copy the `Client ID` for your application and use it in this URL in your browser to add your bot to your server (replace `YOUR_BOT_CLIENT_ID_HERE`):
    - ```
      https://discord.com/oauth2/authorize?client_id=YOUR_BOT_CLIENT_ID_HERE&scope=bot
      ```
1. Enable Developer Mode in your Discord user settings in `User Settings -> App Settings -> Appearance -> Advanced -> Developer Mode`. This allows you to right-click channels and roles to copy their IDs for the next steps.
1. Create or designate an existing channel for the bot's admin announcements/auditing. Copy its ID into `docker-compose.override.yaml`:
    - ```yaml
      SEVENDAYSTODIE_BOT_ADMIN_CHANNEL_ID: 000000000000000000
      ```
1. Create or designate an existing channel for the bot's public announcements. Copy its ID into `docker-compose.override.yaml`:
    - ```yaml
      SEVENDAYSTODIE_BOT_CHANNEL_ID: 000000000000000000
      ```
1. Create or designate an existing role for sensitive commands (`!restart`, `!restart_bot`). Copy its ID into `docker-compose.override.yaml`:
    - ```yaml
      SEVENDAYSTODIE_BOT_ADMIN_ROLE_ID: 000000000000000000
      ```
1. Create or designate an existing role for even more sensitive commands (currently unused). Copy its ID into `docker-compose.override.yaml`:
    - ```yaml
      SEVENDAYSTODIE_BOT_OWNER_ROLE_ID: 000000000000000000
      ```
1. Once the container starts, your bot should show as online and be available for commands.

# 7DaysToDie Discord bot commands
- `/7daystodie info`
  - Print server info including name, current player count, type, OS, and version
  - Example:
    ```
    Name: Test
    Map: Navezgane
    Current players: 0
    Type: Dedicated
    OS: Linux
    Password: true
    Version: 00.20.07
    ```
- `/7daystodie players`
  - Print active players. Player names are currently not reported by the server.
  - Example:
    ```
    • Unknown - 00:00:28
    ```
- `/7daystodie rules`
  - Print server rules/settings.
  - Example:
    ```
    Airdropfrequency: 72
    Airdropmarker: False
    Architecture64: True
    Bedrolldeadzonesize: 25
    Bedrollexpirytime: 45
    [...]
    ```
- `/7daystodie rcon [command]`
  - Send an RCON command to the server's telnet connection, returning the response with any server logs removed for security.
- `/7daystodie restart`
  - Restart the 7DaysToDie server gracefully (via `SIGINT`). Status messages are printed to the designated channel as the server restarts. Server updates are applied during this process.
- `/7daystodie restart_bot`
  - Restart the Discord bot to apply new source code changes without 7DaysToDie server downtime
- `/7daystodie status`
  - Query whether the server is running (i.e. process still exists via `pgrep`)
