local foreground, work_channel, response_channel = unpack({...})

if foreground == false then
  require('love.filesystem')

  local work = require('love-update.thread')
  work(work_channel, response_channel)

  return
end

local work_channel = love.thread.getChannel('updater_work')
local response_channel = love.thread.getChannel('updater_response')

local file = foreground:gsub("%.", "/")
local thread_path = love.filesystem.isFile(file .. ".lua") and file .. ".lua" or file .. "/init.lua"

local noop = function() end

local Promise = require('love-update.vendor.promise')
local loaded_modules = {'main', 'conf', 'love-update.vendor.promise'}

local threads

-- Callback handler
local Callbacks = {
  _last_id = 0,
  list = {},
}

function Callbacks:nextId()
  self._last_id = self._last_id + 1
  return self._last_id
end

function Callbacks:add(callback)
  local id = self:nextId()

  self.list[id] = callback

  return id
end

function Callbacks:call(id, success, ...)
  local resolution = success and 'resolve' or 'reject'
  local callback = self:get(id)

  if type(callback) == 'table' and callback.is_promise then
    callback[resolution](callback, ...)
  elseif type(callback) == 'function' then
    callback(...)
  end
end

function Callbacks:get(id)
  return self.list[id] or noop
end

-- Worker instance
local Worker = {
  path = thread_path,
  work_channel = work_channel,
  response_channel = response_channel
}

function Worker:init()
  if not threads then
    threads = {}
    
    for i=1, 3 do
      local thread = love.thread.newThread(self.path)
      thread:start(false, self.work_channel, self.response_channel)
      table.insert(threads, thread)
    end
  end
end

function Worker:add(job)
  self:init()
  self.work_channel:push(job)
end

function Worker:shutdown()
  if threads then
    for i=1, #threads do 
      self.work_channel:push({job = 'QUIT'})
    end 
    threads = nil
  end
end

-- Updater/Launcher instance
local Launcher = {
  threads = 1
}

local function save_content(filename)
  return function(result)
    if not love.filesystem.write(filename, result) then
      error("Unable to save file " .. filename)
    end
    return filename
  end
end

function Launcher.fetch(url)
  local promise = Promise.new()

  Worker:add({
    job = 'DOWNLOAD',
    id = Callbacks:add(promise),
    url = url
  })

  return promise
end

function Launcher.download(url, filename, progress_callback)
  local promise = Promise.new()

  Worker:add({
    job = 'DOWNLOAD',
    id = Callbacks:add(promise),
    progress_id = Callbacks:add(progress_callback),
    url = url,
  })

  return promise:next(save_content(filename))
end

function Launcher.download_multiple(...)
  local promises = {}

  for i,v in ipairs({...}) do
    assert(v.url, 'Url is required')
    assert(v.filename, 'Filename is required')

    local promise = Launcher.download(v.url, v.filename)
    table.insert(promises, promise)
  end

  return Promise.all(promises)
end

function Launcher.update()
  local messages = response_channel:getCount()

  for i=1,messages do
    local data = response_channel:pop()
    if data then
      Callbacks:call(unpack(data))
    end
  end

  Promise.update()
end

function Launcher.launch(app, args)
  if not app then
    app = 'app.love'
  end

  if not Launcher.can_launch(app) then
    error('Unable to launch ' .. app)
  end

  love.filesystem.mount(app, "")

  for i,module_name in ipairs(loaded_modules) do
    package.loaded[module_name] = nil
  end

  Worker:shutdown()
  
  love.conf = nil
  love.init()
  love.load(args)
end

function Launcher.can_launch(app)
  return love.filesystem.isFile(app)
end

return Launcher
