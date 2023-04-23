#!/bin/bash

function log {
  echo "$(date '+%F %T.%6N') | $*"
}

function cleanup {
  log "Cleaning up subprocesses with SIGINT"
  # Specifically send SIGINT to Ruby as it's a granchild process
  pkill -2 ruby
  # Send SIGINT to all direct descendants (steamcmd, 7daystodie_server)
  pkill -2 $$
  log "Waiting for subprocesses to exit"
  wait
  log "Graceful exit succeeded!"
  exit 0
}
trap cleanup INT TERM

function fail {
  log "ERROR: $*"
  exit 1
}

function install_rbenv {
  pushd ~/.rbenv || fail "Failed to pushd to ~/.rbenv"
    git config --global --add safe.directory '*'
    git init
    git remote add origin https://github.com/rbenv/rbenv.git
    git fetch
    # Force checkout (emulate clone)
    git checkout -f origin/master
    # Get ruby-build plug-in so we can install desired Ruby version
    mkdir -p ~/.rbenv/plugins
    git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
    src/configure
    make -C src
  popd || fail "Failed to popd"
}

if [ -n "$SEVENDAYSTODIE_BOT_TOKEN" ]; then
  pushd 7daystodie-bot || fail "Failed to pushd to 7daystodie-bot"
    if ! command -v rbenv; then
      ### rbenv with ruby-build plugin
      log "Installing rbenv and ruby-build to mounted volume for 7DaysToDie Bot"
      # Can't clone since the directory already exists due to the mount
      install_rbenv
      command -v rbenv || fail "ERROR: Failed to install rbenv"
    else
      log "rbenv detected in mounted volume; skipping install"
    fi
    ### ruby and gems (cached in rbenv volume)
    log "Installing Ruby and required gems for 7DaysToDie Bot"
    rbenv install --skip-existing --verbose
    rbenv exec gem install bundler
    ### Start a thread that will relaunch the bot if it fails sporadically or is restarted via command to apply updates
    while true; do
      rbenv exec bundle install
      log "Starting 7DaysToDie Bot"
      ~/.rbenv/bin/rbenv exec bundle exec ruby 7daystodie-bot.rb
      export BOT_LAST_EXIT_CODE=$?
      log "7DaysToDie Bot Stopped"
      if [[ $BOT_LAST_EXIT_CODE -eq 43 ]]; then
        break # Contner is stopping; bail out
      elif [[ $BOT_LAST_EXIT_CODE -ne 42 ]]; then
        log "Restarting in 5 seconds"
        sleep 5
      fi
    done & # Send this to a background thread so we can proceed to start the server
  popd || fail "Failed to popd"
else
  log "SEVENDAYSTODIE_BOT_TOKEN unset; skipping bot startup"
fi

install_dir=/home/7daystodie/7daystodie
mkdir -p "$install_dir"
cd "$install_dir" || fail "Failed to cd to install dir: $install_dir"

LOG_FILE="7DaysToDieServer_Data/output_log_$(date +%Y-%m-%d__%H-%M-%S).log"
tail -F "$LOG_FILE" &

while true; do
  log "Downloading 7DaysToDie server to $install_dir"
  steamcmd +force_install_dir "$install_dir" +login anonymous +app_update 294420 +quit &
  wait $!

  log "Copying 64-bit steamclient.so"
  mkdir -p /home/7daystodie/.steam/sdk64/
  cp steamclient.so /home/7daystodie/.steam/sdk64/steamclient.so

  if [ ! -f 7DaysToDieServer_Data/serverconfig.xml ]; then
    log "Copying default serverconfig.xml to 7DaysToDieServer_Data/serverconfig.xml"
    cp serverconfig.xml 7DaysToDieServer_Data/serverconfig.xml
  fi

  log "Starting 7DaysToDie server with config file 7DaysToDieServer_Data/serverconfig.xml and log file $LOG_FILE"
  ./7DaysToDieServer.x86_64 -logfile "$LOG_FILE" -quit -batchmode -nographics -dedicated -configfile=7DaysToDieServer_Data/serverconfig.xml & # We need this in the background in order for signals (SIGINT) to arrive
  wait $!

  log "7DaysToDie server stopped. Checking for updates in 5 seconds."
  sleep 5
done
