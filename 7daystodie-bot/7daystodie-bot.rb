#!/usr/bin/env ruby
# encoding: UTF-8

require 'discordrb'
require 'pry'
require_relative 'lib/logger'
require_relative 'lib/self-updater'
require_relative 'lib/server-query'
require_relative 'lib/telnet-client'

$logger = Logging.logger

Dir.chdir __dir__

bot_token = ENV['SEVENDAYSTODIE_BOT_TOKEN'] || abort('SEVENDAYSTODIE_BOT_TOKEN is undefined')
$sevendays_channel_id = (ENV['SEVENDAYSTODIE_BOT_CHANNEL_ID'] || abort('SEVENDAYSTODIE_BOT_CHANNEL_ID is undefined')).to_i
$sevendays_admin_channel_id = (ENV['SEVENDAYSTODIE_BOT_ADMIN_CHANNEL_ID'] || abort('SEVENDAYSTODIE_BOT_ADMIN_CHANNEL_ID is undefined')).to_i
$admin_role_id = (ENV['SEVENDAYSTODIE_BOT_ADMIN_ROLE_ID'] || abort('SEVENDAYSTODIE_BOT_ADMIN_ROLE_ID is undefined')).to_i
$owner_role_id = (ENV['SEVENDAYSTODIE_BOT_OWNER_ROLE_ID'] || abort('SEVENDAYSTODIE_BOT_OWNER_ROLE_ID is undefined')).to_i
$telnet = client = TelnetClient.new('localhost', 8081)

players = []
info = {}
rules = {}

NETCAT_QUERY_PORT='nc -z localhost 26900'
PGREP='pgrep -f 7DaysToDieServer.x86_64'
PKILL_INT='pkill -INT -f 7DaysToDieServer.x86_64'

def send_to_channel(message)
    $bot.channel($sevendays_channel_id).send(message)
end

def send_to_admin_channel(message)
    $bot.channel($sevendays_admin_channel_id).send(message)
end

def respond_in_channel(event, message)
    $bot.channel($sevendays_channel_id).send(message)
    event.channel.send_message(content: message) unless event.channel.id == $sevendays_channel_id
end

def log_command_event(event)
    $logger.info("#{event.user.name}##{event.user.discriminator} (#{event.user.id}) triggered command #{event.command_name} -> #{event.subcommand} #{' ' + event.options.to_s unless event.options.empty?}")
    send_to_admin_channel("<@#{event.user.id}> (`#{event.user.name}##{event.user.discriminator}`) triggered command `/#{event.command_name} #{event.subcommand}#{' ' + event.options.map { |k,v| "#{k}: #{v}" }.join(' ') unless event.options.empty?}`")
end

def system_no_out(command)
    system(command, :out => File::NULL)
end

def wait_command_success(command, max: 180)
    # E.g. wait for server process to exist
    waited = 0
    until system_no_out(command) || waited > max
        sleep 1
    end
    waited < max
end

def wait_command_failure(command)
    # E.g. wait for server process to no longer exist
    waited = 0
    max = 120
    until !system_no_out(command) || waited > max
        sleep 1
    end
    waited < max
end

def wait_server_up(max: 180) = wait_command_success(NETCAT_QUERY_PORT, max: max)
def wait_server_down = wait_command_failure(PGREP)
def interrupt_server = system_no_out(PKILL_INT)

def user_is_admin?(user)
    unless user.respond_to?(:roles)
        user = $bot.channel($sevendays_channel_id).server.users.select { |u| u.id == user.id }.first
        return false unless user.roles
    end
    if user.roles.include?($bot.channel($sevendays_channel_id).server.roles.find { |r| r.id == $admin_role_id })
        return true
    end
    false
end

def command(cmd, subcmd, ephemeral: true)
    $bot.application_command(cmd).subcommand(subcmd) do |event|
        event.defer(ephemeral: ephemeral)
        log_command_event(event)
        yield event
    rescue => e
        $logger.error(e)
        event.send_message(content: "Error (#{e.class}): Contact the maintainer.")
    end
end

def admin_command(cmd, subcmd, ephemeral: true)
    $bot.application_command(cmd).subcommand(subcmd) do |event|
        event.defer(ephemeral: ephemeral)
        log_command_event(event)
        unless user_is_admin?(event.user)
            send_to_admin_channel(":warning: Non-admin user <@#{event.user.id}> (`#{event.user.name}##{event.user.discriminator}`) was denied trying to trigger admin command `#{event.command_name} -> #{event.subcommand}`")
            next event.send_message(content: 'You are not an admin! :newspaper2:')
        end
        yield event
    rescue => e
        $logger.error(e)
        event.send_message(content: "Error (#{e.class}): Contact the maintainer.")
    end
end

def split_message(message, limit: 1900)
    messages = []
    while message && message.length >= limit
      messages << message[0..(limit - 1)]
      message = message[limit..-1]
    end
    messages << message unless message.nil? || message.empty?
    if messages.first.include?('```') && messages.length > 1
      messages.first << "\n```"
      messages[1..-2].each { |m| m.prepend("```\n") << "\n```" } if messages.length > 2
      messages.last.prepend  "```\n"
    end
    messages
  end

$bot = Discordrb::Commands::CommandBot.new(token: bot_token, prefix: ENV['SEVENDAYSTODIE_BOT_COMMAND_PREFIX'] || '!', intents: [:server_messages, :server_members])

$bot.register_application_command(:'7daystodie', '7DaysToDie Bot commands') do |cmd|
    cmd.subcommand(:info, 'Print server information')
    cmd.subcommand(:players, 'Print server players')
    cmd.subcommand(:rules, 'Print server rules (settings)')
    cmd.subcommand(:status, 'Check if server is online')
    cmd.subcommand(:rcon, 'Send RCON command (Admin only)') do |subcmd|
        subcmd.string('command', 'RCON command to send', required: true)
    end
    cmd.subcommand(:restart_bot, 'Restart the bot (apply changes from update) (Admin only)')
    cmd.subcommand(:restart, 'Restart the server (and apply updates) (Admin only)')
    # cmd.subcommand(:update_bot, 'Update 7DaysToDie to the latest available version on GitHub. (Admin only)')
end

command(:'7daystodie', :info) do |event|
    next event.send_message(content: 'No server info is currently known.') if info.empty?
    response = ['Server info:', '```']
    info.each do |k, v|
        response.push("#{k.to_s.capitalize.gsub('_', ' ').sub(/^Os$/, 'OS')}: #{v.to_s}")
    end
    response.push('```')
    event.send_message(content: response.join("\n"))
end

command(:'7daystodie', :players) do |event|
    next event.send_message(content: 'No server info is currently known.') if info.empty?
    next event.send_message(content: 'No players are online.') if info.empty?
    current = info[:current_players] ? " (#{info[:current_players]})" : ''
    response = ["Server players#{current}:", '```']
    players.each do |p|
        name = p[:name].to_s.strip.empty? ? "Unknown" : p[:name].to_s.strip
        response.push("  • #{name} - #{p[:duration].to_s}")
    end
    response.push('```')
    event.send_message(content: response.join("\n"))
end

command(:'7daystodie', :rules) do |event|
    next event.send_message(content: 'No server rules are currently known.') if rules.empty?
    response = ['Server rules:', '```']
    rules.each do |k, v|
        response.push("#{k}: #{v}")
    end
    response.push('```')
    split_message(response.join("\n")).each do |m|
        event.send_message(content: m, ephemeral: true)
    end
end

command(:'7daystodie', :status) do |event|
    message = system_no_out(PGREP) ? "Server is online!" : "Server is offline!"
    event.send_message(content: message)
end

admin_command(:'7daystodie', :rcon) do |event|
    command = event.options['command']
    event.edit_response(content: "Sending `#{command}`...")
    response = $telnet.send(command).strip
    if response.empty?
        send_to_admin_channel("No response.")
        event.channel.send_message("No response.")
    else
        response = "```\n#{response}\n```"
        event.edit_response(content: "Receiving response!")
        split_message(response).each do |m|
            send_to_admin_channel(m)
            event.send_message(content: m, ephemeral: true)
        end
    end
    event.edit_response(content: "Done with command: `#{command}`")
end

admin_command(:'7daystodie', :restart) do |event|
    send_to_channel("<@#{event.user.id}> is restarting the server...")
    outcome = "Server #{interrupt_server ?
        'interrupt successfully sent. Waiting for server to gracefully exit...' :
        '`pkill` command failed! Is the server running?'}"
    respond_in_channel(event, outcome)

    outcome = "Server #{wait_server_down() ?
        'stopped successfully. Any pending updates will apply and the server will restart. This channel will receive a notification when the server is online.' :
        'Failed to detect server stopping. Is it stuck?'}"
    respond_in_channel(event, outcome)

    outcome = wait_server_up() ? "Server is back up!" : "Failed to detect server within the time limit."
    respond_in_channel(event, outcome)
    event.send_message(content: "Server restart complete!")
end

admin_command(:'7daystodie', :restart_bot) do |event|
    send_to_admin_channel("<@#{event.user.id}> is restarting me...")
    event.send_message(content: "Exiting!")
    exit 42
end

begin
    Thread.new do
        # Allow server to start
        ip = '127.0.0.1'
        port = 26900
        $logger.info('Server monitor waiting for server to start')
        wait_server_up(max: 1200)
        $logger.info('Server is up; starting server monitoring')
        while true
            begin
                info = ServerQuery::a2s_info(ip, port) || info
                players = ServerQuery::a2s_player(ip, port) || players
                rules = ServerQuery::a2s_rules(ip, port) || rules
                $bot.update_status(nil, ": #{info[:current_players] || '?'}", nil)
                sleep 10
            rescue => e
                $logger.warn(e)
            end
        end
    end
    $logger.info('Starting 7DaysToDie Bot now')
    $bot.run(true) # Daemonize (thread)
    $bot.online
    $logger.info('7DaysToDie Bot started')
    at_exit do
        $logger.info('Stopping 7DaysToDie Bot')
        $bot.invisible
        $bot.stop
        $logger.info('7DaysToDie Bot stopped')
    end
    if ENV['BOT_LAST_EXIT_CODE'] == '42'
        send_to_admin_channel("I'm back! :wave:")
    end
    sleep
rescue SignalException => e
    $logger.debug(e)
    exit 43
rescue => e
    $logger.error(e)
end
