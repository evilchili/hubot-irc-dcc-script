hubot-irc-dcc-script
====================

A first pass at a script for the hubot-irc adapter that accepts 
DCC SEND commands and (optionally) shares the uploaded files 
via HTTP.

### Required Environment Variables:
  *HUBOT_DCC_IP*        - the IP on which we'll listen for passive DCC requests
  
  *HUBOT_DCC_SHARE_DIR* - path to directory where uploads should be stored
  
  *HUBOT_DCC_SHARE_URL* - URL that points to the upload subdirectory

### Commands:
  hubot recent - List the 5 most recent files.

### Status:
  This code is EARLY EARLY EARLY and I do not necessarily recommend its use.
  
### Credits:

  Inspired by @pepijndevos's work at:
  
  https://gist.github.com/pepijndevos/5495692
