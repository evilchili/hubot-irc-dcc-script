# Description:
#   DCC SEND and passive DCC SEND module
#
# Required Environment Variables:
#   HUBOT_DCC_IP        
#     - the IP on which we'll listen for passive DCC requests
#   HUBOT_DCC_SHARE_DIR 
#     - path to directory where uploads should be stored
#   HUBOT_DCC_SHARE_URL 
#     - URL that points to the upload subdirectory
#
# Commands:
#   hubot recent - List the 5 most recent files.

net    = require 'net'
fs     = require 'fs'
path   = require 'path'
crypto = require 'crypto'

WEBADDR  = process.env.HUBOT_DCC_SHARE_URL
DIRNAME  = process.env.HUBOT_DCC_SHARE_DIR
HOST_IP  = process.env.HUBOT_DCC_IP

# function mktemp 
#   -- return the absolute path to a temp file
mktemp = ->
    return DIRNAME + '/.DCC_' + crypto.randomBytes(4).readUInt32LE(0)

# function ipToInt
#   -- convert a dotted-quad IP to an integer
#      via http://javascript.about.com/library/blipconvert.htm
ipToInt = (ip) ->
 d = ip.split('.');
 return ((((((+d[0])*256)+(+d[1]))*256)+(+d[2]))*256)+(+d[3])

# function intToIP
#   -- convert an integer back into a dotted-quad
intToIP = (n) ->
  byte1 = n & 255
  byte2 = ((n >> 8) & 255)
  byte3 = ((n >> 16) & 255)
  byte4 = ((n >> 24) & 255)
  return byte4 + "." + byte3 + "." + byte2 + "." + byte1

# function dccError
#   -- send error messages to the console and the remote user
dccError = (msg, req) ->
    console.warn(msg)
    req.bot.say req.user, "DCC Error! file: " + req.filename + " error: " + msg

# function sanitizePath
#   -- remove dangerous characters from filenames
sanitizePath = (name) ->
  name = name.replace(/['"?!`]/ig, '')
  fname = path.resolve(DIRNAME, name)
  fname.indexOf(DIRNAME) == 0 && fname

# function makeStream
#   -- create a writable stream and set up an event
#      handler for completed transfers.
makeStream = (req) ->

  # we upload to a temporary file
  req.tmpfile = mktemp()

  # create the stream to the temp file
  req.stream  = fs.createWriteStream( req.tmpfile )

  # when then the stream buffer emtpies, check to see
  # if we've written all the bytes we're sposeda.
  req.stream.on("drain", ->
    if req.stream.bytesWritten == req.filesize

      # close the filehandle
      req.stream.destroy() 

      # move the tempfile into place and inform the user 
      console.log("Renaming #{req.tmpfile} to #{req.outfile}")
      fs.rename( req.tmpfile, req.outfile, ->
        msg = "Transfer complete."

        # if the share url is defined, include it in the 
        # response to the remote user.
        if WEBADDR
          msg += " Your file is available at: #{WEBADDR}/" + path.basename(req.outfile)

        req.bot.say req.user, msg
      )
  )

# function streamWrite
#  -- write chunks of data to the output stream.
streamWrite = (req, data) ->
  req.stream.write(data)

# function dccPassive
#  -- open a port and begin listening for a passive
#     DCC transfer, at the user's request.
dccPassive = (req) ->

  # create the server
  server = net.createServer()
  server.on("error", (err) -> dccError(err,req))
  server.listen(0)

  # remember the port we're on
  req.port = server.address()['port']

  # create the output stream
  makeStream(req)

  # tell the user we're ready to begin receiving
  host_int = ipToInt(HOST_IP)
  req.bot.ctcp(req.user, "privmsg", "DCC SEND #{req.filename} #{host_int} #{req.port} #{req.filesize} #{req.token}")
   
  # when we receive a connection, bind the data event
  # to the streamWrite function, and set up close/error
  # event handlers.
  server.on "connection", (conn) ->

    # whenever we receive data, call streamWrite 
    # to write it to the tempfile.
    conn.on("data", streamWrite.bind(conn, req))
    conn.on("close", -> server.close())
    conn.on("error", (err) -> dccError(err, req))


# function dccReceive
#   -- active DCC SEND handler
dccReceive = (req) ->

  # create the output stream
  makeStream(req)

  # connect to to the client on the port specified in 
  # the DCC SEND request
  client = new net.Socket()
  client.connect( req.port, req.ip )

  # bind the data event to the streamWrite function
  client.on("data", streamWrite.bind(client, req ))

  # handle errors
  client.on("error", (err) -> dccError(err, req))

# function parsePrivmsg
#   -- parse the raw CTCP message and build an 
#      associative array of request properties.
parsePrivmsg = (from, to, msg) ->
  if msg.lastIndexOf("DCC SEND", 0) == 0
    [_dcc, _send, filename, ip, port, filesize, token] = msg.split(' ')

    return {
            # the client-side filename
            filename : filename,

            # the serer-side output filename
            outfile  : sanitizePath( filename ), 

            # transform the integer IP back into a dotted-quad
            ip       : intToIP(parseInt(ip)),

            # client-side port to connect to (NaN for passive)
            port     : parseInt(port),

            # size of the file, in bytes
            filesize : parseInt(filesize),

            # unique identifier for the passive dcc session
            token    : token || 0,

            # the originating IRC user's nick
            user     : from,

            # should always be the bot name!
            to       : to,

            # the original CTCP message
            text     : msg,
    }

# function getUniqueFilename
#   -- ensure that we do not overwrite an existing file
#      on the server, by appending a digit to the basename
#      of the output file.
getUniqueFilename = (req) ->
    counter=1
    outfile = req.outfile

    # XXX: path.existsSync is only for ancient crufty versions of node; 
    # modern versions should use fs.existsSync
    #
    # if "foo.bar" exists...
    while ( path.existsSync(outfile) )
           parts = req.outfile.split('.')
           ext = parts.pop()

           # ...try "foo_1.bar"...
           outfile = parts.join('.') + "_" + counter + "." + ext

           # ...then foo_2.bar, foo_3.bar... until we hit foo_99.bar...
           counter++
           if counter == 99
               # ...at which point we stop, to avoid looping forever.
               # XXX: This could be handled better.
               req.bot.say "Unable to create unique filename! eep!"
               outfile = null

    # return the pathname that is safe to use.
    return outfile

# function recentFiles
#   -- list the five most recently uploaded files
recentFiles = (msg) ->
  fs.readdir path.resolve(DIRNAME), (err, files) ->
    files.sort (a, b) ->
      at = fs.statSync(path.resolve(DIRNAME, a)).mtime.getTime()
      bt = fs.statSync(path.resolve(DIRNAME, b)).mtime.getTime()
      bt - at
    for f in files[0..4]
      msg.send(WEBADDR + f)

module.exports = (robot) ->

  # respond to a "recent" command
  robot.respond(/recent/i, recentFiles)

  # listen for CTCP-PRIVMSG events
  robot.adapter.bot.addListener "ctcp-privmsg", (from, to, text) ->

    # parse the text of the event
    dccReq = parsePrivmsg(from, to, text)

    # shorthand
    dccReq.bot = robot.adapter.bot
  
    # ensure a unique filename
    # XXX: Need to implement advisory locking on the output filename
    # to avoid the race condition between getUniqueFilename being called
    # and the temp file being renamed (after the upload is complete)
    dccReq.outfile = getUniqueFilename( dccReq )

    # outfile will be null if we couldn't find a safe filename
    if dccReq.outfile

      # if there is not port number in the message, we are being
      # asked to set up a passive DCC transfer.
      if dccReq.port == 0
        #dccReq.bot.say dccReq.user, "Initiating passive DCC transfer for #{dccReq.filename}"
        dccPassive(dccReq)

      # begin an active DCC transfer
      else
        #dccReq.bot.say dccReq.user, "Accepting DCC transfer for #{dccReq.filename}"
        dccReceive(dccReq)

    # Whatever the user sent, it wasn't a DCC request.
    else
      dccReq.bot.say("I AM ERROR.")

