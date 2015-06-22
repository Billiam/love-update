require('love.timer')

local request = require('love-update.vendor.luajit-request')

local request_args = function(headers)
  local defaults = {
    timeout = 15,
    headers = {
      ["User-Agent"] = 'LÖVE Launcher'
    }
  }

  headers = type(headers) == 'table' and headers or {}

  for k,v in pairs(headers) do
    defaults.headers[k] = v
  end

  return defaults
end

local send_request = function(url, args)
  if not url then
    return false, 'Cannot fetch the latest version without a URL'
  end

  local response = request.send(url, args)

  if not response then
    return false, 'Could not request data from url: ' .. url
  end

  local code = tonumber(response.code)
  if not (code >= 200 and code < 300) then
    local result = string.format("Made a request to url ( %s ) and received a respons code of ( %d )", url, response.code)
    result = result .. "\n\n" .. response.body
    return false, result
  end

  return true, response.body
end

local throttle_progress = function(progress_id, channel)
  if not progress_id then
    return
  end

  local last_time
  local last_total = 0
  local updates = 30

  local smoothing = 0.1
  local average_speed = 0

  return function(dl_total, dl_current)
    if not last_time then
      last_time = love.timer.getTime()
    end

    local now = love.timer.getTime()

    local time_diff = now - last_time

    -- throttle status updates
    if time_diff < 1/updates then
      return
    end

    local dl_diff = dl_current - last_total
    local current_speed = dl_diff/time_diff

    last_total = dl_current
    last_time = now

    average_speed = smoothing * current_speed + (1-smoothing) * average_speed

    local percent = dl_total > 0 and dl_current / dl_total or 0

    channel:push({
      progress_id,
      'success',
      dl_total,
      dl_current,
      percent,
      average_speed
    })
  end
end

local tasks = {
  DOWNLOAD = function(complete_id, data, channel)
    local args = request_args()
    local progress_id, url = data.progress_id, data.url

    args.transfer_info_callback = throttle_progress(progress_id, channel)
    return send_request(url, args)
  end
}

--worker loop
local update_loop = function(work_channel, response_channel)
  while true do
    local data = work_channel:demand()
    if data and type(data) == 'table' then
      local id, job = data.id, data.job

      data.id=nil
      data.job=nil
      
      if job == 'QUIT' then
        break
      end
      
      local task = tasks[job]
      
      if task then
        local success, result = task(id, data, response_channel)

        response_channel:push({
          id,
          success,
          result
        })
      end
    else
      print('Received invalid worker data')
    end
  end
end

return update_loop
