local VERSION_URL = 'http://mysite.com/game/version.txt'
local GAME_URL = 'http://mysite.com/game/game.love'

local updater =  require('vendor.love-update')

local current_progress = 0

-- compare a new version to to the version stored in a VERSION file
local function compare_versions(new_version)
  local current_version = love.filesystem.read('VERSION') or 0

  if new_version and new_version > current_version then
    return new_version
  end

  return false
end

-- Store download percentage
local download_progress = function(total_bytes, current_bytes, progress, speed)
  current_progress = progress
end

-- when passed a version, returns a new promise
-- which resolves when the download is complete,
-- and the newer_version value has been written to a file
local function download_update(newer_version)
  if newer_version then
    return updater.download(GAME_URL, 'game.love', download_progress):next(function()
      love.filesystem.write('VERSION', newer_version)
    end)
  end

  return true
end

-- launch a downloaded file called game.love, passing in the global arg
local function launch()
  updater.launch('game.love', arg)
end

function love.load()
  -- fetch the latest version from VERSION_URL
  -- Pass version to compare version
  -- Pass comparison results to download_update
  -- [maybe] download a newer version
  -- then launch game
  updater.fetch(VERSION_URL)
    :next(compare_versions)
    :next(download_update)
    :next(launch)
    :catch(function(reason)
      print('an error occurred while updating', reason)
    end)
end

function love.update()
  -- Runs promises and checks background thread channels
  updater.update()
end

function love.draw()
  -- Print generic loading text
  love.graphics.setColor(255, 255, 255, 255)
  love.graphics.print(string.format('Loading... (%d%%)', current_progress), 20, 20)
end

function love.keypressed(key)
  if key == 'esc' then
    love.event.quit()
  end
end
