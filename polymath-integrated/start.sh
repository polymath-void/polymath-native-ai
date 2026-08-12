#!/data/data/com.termux/files/usr/bin/bash
# Rebuild the agent silently so cargo logs don't mess up the screen
# cargo build --release -q (Disabled due to Termux linker issues)

clear

# Print animated colored Polymath header
echo -e "\e[1;36m"
echo "  ____       _                       _   _    "
sleep 0.1
echo " |  _ \ ___ | |_   _ _ __ ___   __ _| |_| |__ "
sleep 0.1
echo " | |_) / _ \| | | | | '_ \` _ \ / _\` | __| '_ \\"
sleep 0.1
echo " |  __/ (_) | | |_| | | | | | | (_| | |_| | | "
sleep 0.1
echo " |_|   \___/|_|\__, |_| |_| |_|\__,_|\__|_| |_"
sleep 0.1
echo "               |___/                          "
echo -e "\e[0m"
sleep 0.5

# Launch the agent
$(dirname "$0")/target/release/polymath-void-agent
