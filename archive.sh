#!/bin/sh

# Submit URLs to the WayBack Machine (https://web.archive.org/)
#
# *Archive.org Wayback Machine API doco:
# https://docs.google.com/document/d/1Nsv52MvSjbLb2PCpHlat0gkzw0EvtSgpKHu4mk0MnrA/edit
#
# Usage:
#
#   bash archive.sh myUrlsList.txt
#
# myUrlsList.txt contents (cannot have non-Mac carriage returns):
#
#   https://some-site.com/some/path/,
#   https://some-site.com/another/path/,

# TODO: Ideally, make this crawl the target website and submit the URLs it finds that
# have a 200 HTTP code response.

# TODO: Add reporter log to capture which URLs worked/failed

# TODO: Refactor to handle Wayback's API properly:

# To not duplicate URLs:
# 1. Run a check to see if the URL has been archived within the last X days. If not:
# 2. Submit the URL to the WayBack Machine
# 3. Check the job queue length
# 4. If the queue length is 5, pause for 10 seconds and check again
# 5. Repeat for next URLs

# Import Wayback account key and secret from the .env file
if [[ -f ".env" ]]; then
    source .env
    if [[ ! -n "$KEY" || ! -n "$SECRET" ]]; then
        echo '[ERROR] - KEY or SECRET is empty or missing from the .env file!'
        exitHandler 1
    fi
else
    echo "[ERROR] - '.env' file not found. Create one by copying the '.env.example' file and following the instructions within."
    exitHandler 2
fi

SITE='http://web.archive.org/save/'
INPUT_FILE=$1
COUNT=0

function fetch() {
    local URL=$1
    RESPONSE=$(curl -X POST --no-progress-meter -H "Accept: application/json" -H "Authorization: LOW $KEY:$SECRET" -d"url=$URL&capture_outlinks=1&capture_screenshot=1&skip_first_archive=1&js_behavior_timeout=5" https://web.archive.org/save)
    EXIT_CODE=$? responseHandler "$URL" "$RESPONSE"
}

function exitHandler() {
    local EXIT_CODE=$1
    echo -e "[INFO] - Quitting, exit code $EXIT_CODE"
    exit $EXIT_CODE
}

function responseHandler() {
    local URL=$1
    local RESPONSE=$2
    MESSAGE=$(echo "$RESPONSE" | jq -r '.message')
    MESSAGE_CODE=$(echo "$RESPONSE" | jq -r '.status_ext')
    JOB_ID=$(echo "$RESPONSE" | jq -r '.job_id')
    
    # Quit if Wayback returns a non-zero exit code in curl
    if [[ $EXIT_CODE -ne 0 ]]; then
        echo -e "[ERROR] - Exit code $EXIT_CODE, quitting..."
        exitHandler 3
    fi
    
    # See 'Error codes' in the doco for the full list of Wayback error responses:
    # https://docs.google.com/document/d/1Nsv52MvSjbLb2PCpHlat0gkzw0EvtSgpKHu4mk0MnrA/edit
    # echo "$RESPONSE"
    
    # If the archiving job has been created successfully...
    if [[ -n "$JOB_ID" && "$MESSAGE" == 'null' ]]; then
        echo -e "[SUCCESS] - Archiving task created for $URL"
    # Wait and run it again to avoid Wayback killing our connection,
    elif [[ $MESSAGE_CODE == "error:user-session-limit" ]]; then
        echo -e "[INFO] - Rate limiter reached, retrying this URL in 30s..."
        sleep 30
        fetch $URL
    elif [[ $MESSAGE_CODE == "error:too-many-daily-captures" ]]; then
        echo -e "[INFO] - This URL has already been indexed 5 times today, skippping..."
    elif [[ $MESSAGE =~ "You can make new capture of this URL after 1 hour" ]]; then
        echo "[INFO] - Already captured in the last hour, skipping..."
    else
        # Errors that merit quitting
        if [[ $MESSAGE_CODE =~ "error:" ]]; then
            # If Wayback returns a zero code but with an error message, quit
            echo -e "[ERROR] - $RESPONSE, quitting..."
            exitHandler 4
        elif [[ $RESPONSE =~ "Connection refused" ]]; then
            echo -e "[ERROR] - $RESPONSE"
            exitHandler 5
        fi
    fi
    # Pause for a few seconds to avoid Wayback's rate-limiter
    sleep 4
}

# Quit if no file is provided
if [[ $# -eq 0 ]] ; then
    echo -e "[ERROR] - No file provided, quitting..."
    echo -e "Usage:\n\n bash archive.sh myUrlsList.txt"
    exitHandler 2
    elif [[ ! -f $1 ]]; then
    echo -e "[ERROR] - File '$1' does not exist, quitting..."
else
    echo -e "\n[INFO] - Submitting URLs to the Wayback Machine!\n"
    while read LINE; do
        # Increment the counter
        COUNT=$((COUNT+1))
        
        echo -e "[INFO] - Item $COUNT: "$(echo "$LINE")
        fetch $LINE
    done < $INPUT_FILE
    echo -e "\n[INFO] - URLs submitted to Archive.org Wayback Machine. Quitting..."
fi
exitHandler 0
