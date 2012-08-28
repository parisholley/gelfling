zlib = require 'zlib'
dgram = require 'dgram'
crypto = require 'crypto'

exports = module.exports = (host, port, options) ->
  new Gelfling host, port, options

# From https://github.com/Graylog2/graylog2-docs/wiki/GELF
# and https://github.com/Graylog2/gelf-php/blob/master/GELFMessage.php
exports.EMERGENCY = 0
exports.ALERT = 1
exports.CRITICAL = 2
exports.ERROR = 3
exports.WARNING = 4
exports.NOTICE = 5
exports.INFO = 6
exports.DEBUG = 7

exports.Gelfling = class Gelfling

  constructor: (@host = 'localhost', @port = 12201, options = {}) ->
    @maxChunkSize = @getMaxChunkSize options.maxChunkSize
    @defaults = options.defaults ? {}
    @udpClient = dgram.createSocket 'udp4'
    @udpClient.on 'error', options.errHandler ? console.error

  send: (data, callback = ->) ->
    data = [data] if Buffer.isBuffer data

    unless Array.isArray data
      return @encode @convert(data), (err, chunks) =>
        return callback err if err
        @send chunks, callback

    remaining = data.length
    for chunk in data
      @udpClient.send chunk, 0, chunk.length, @port, @host, (err) ->
        return callback err if err
        if --remaining is 0
          callback()


  encode: (msg, callback = ->) ->
    zlib.gzip new Buffer(JSON.stringify msg), (err, compressed) =>
      return callback err if err
      callback null, @split(compressed)


  GELF_ID = [0x1e, 0x0f]

  split: (data, chunkSize = @maxChunkSize) ->
    return [data] if data.length <= chunkSize

    msgId = Array::slice.call crypto.randomBytes(8)
    numChunks = Math.ceil data.length / chunkSize
    for chunkIx in [0...numChunks]
      dataStart = chunkIx * chunkSize
      dataSlice = Array::slice.call data, dataStart, dataStart + chunkSize
      new Buffer GELF_ID.concat msgId, chunkIx, numChunks, dataSlice


  GELF_KEYS = ['version', 'host', 'short_message', 'full_message', 'timestamp', 'level', 'facility', 'line', 'file']
  ILLEGAL_KEYS = ['_id']

  convert: (msg) ->
    msg = {short_message: msg} if typeof msg isnt 'object'

    gelfMsg = {}

    # Default fields
    for own key, val of @defaults
      gelfMsg[key] = if typeof val is 'function' then val(msg) else val

    # Msg fields
    for own key, val of msg
      key = '_' + key unless key in GELF_KEYS
      key = '_' + key if key in ILLEGAL_KEYS
      gelfMsg[key] = val

    # Required fields
    gelfMsg.version ?= '1.0'
    gelfMsg.host ?= require('os').hostname()
    gelfMsg.timestamp ?= +new Date / 1000
    gelfMsg.short_message ?= JSON.stringify msg

    gelfMsg


  getMaxChunkSize: (size = 'wan') ->
    switch size.toLowerCase()
      when 'wan' then 1420
      when 'lan' then 8154
      else parseInt size

