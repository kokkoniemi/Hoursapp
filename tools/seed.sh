#!/usr/bin/env bash
# Populate ~/.hourapp/ with sample data for visual testing.
# Wipes existing files. Run before launching Hoursapp to see a populated UI.
set -euo pipefail

DIR="$HOME/.hourapp"
mkdir -p "$DIR"
TODAY="$(date +%Y-%m-%d)"
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$DIR/clients.csv" <<EOF
client,project
Farringdon Inc,New Company Website
Rotherhithe Design,Product Launch
Spitalfields Communications,Mobile App
Spitalfields Communications,Summer Marketing Campaign
EOF

cat > "$DIR/tasks.csv" <<EOF
task
Meetings
Project Management
Design
EOF

# 0:48 = 2880s, 1:15 = 4500s, 2:21 = 8460s, 0:42 = 2520s, 0:02 = 120s (running)
cat > "$DIR/entries.csv" <<EOF
id,date,client,project,task,seconds,notes,started_at,stopped_at
e1,$TODAY,Farringdon Inc,New Company Website,Meetings,2880,,,
e2,$TODAY,Rotherhithe Design,Product Launch,Project Management,4500,,,
e3,$TODAY,Spitalfields Communications,Mobile App,Design,8460,,,
e4,$TODAY,Spitalfields Communications,Mobile App,Project Management,2520,,,
e5,$TODAY,Spitalfields Communications,Summer Marketing Campaign,Meetings,120,,$NOW_UTC,
EOF

echo "Seeded $DIR with sample entries for $TODAY."
