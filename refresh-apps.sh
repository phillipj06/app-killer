#!/bin/bash
# refresh-apps.sh — Cache app names from /Applications to /tmp/apps.txt
ls -1 /Applications/ /System/Applications/ 2>/dev/null | sed -n 's/\.app$//p' | sort -u > /tmp/apps.txt
