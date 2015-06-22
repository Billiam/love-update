-- # Patching example
--
-- Downloads only changed files by comparing a manifest file stored remotely
-- and locally. After finishing, launch a game by requiring some entrypoint file

-- _Note: In this example if one download fails while others succeed,
-- some files may be from your updated version, while others may
-- be outdated.
-- A workaround for this might be to download files to a subdirectory,
-- and move them out once they have all completed._

-- ## Configuration

-- Where does the remote manifest live?
local VERSION_URL = 'http://mysite.com/game/manifest.json'

-- This will be prepended to generate download URLs
local SOURCE_URL = 'http://mysite.com/games/assets/'

-- The filename where your manifest file will be stored
local MANIFEST_FILE = 'manifest.json'

-- ## Required resources
local updater = require('vendor.love-update')
-- json library of your choosing.
local json = require('vendor.json')

-- A string used to display progress to the user
local current_status = 'Checking for updates'

-- Compares hashes (however you calculate them) in a remote json file
-- to a local file. Return a promise that resolves when all the files
-- with mismatched hashes have finished downolading, or a boolean value
-- immediately
local function compare_versions(manifest_json)
  -- if json cannot be parsed, throw an error, which will cause the
  -- `catch` error handler in `love.load` to fire
  local manifest = json.parse(manifest_json) or error('Could not parse remote manifest')
  local old_manifest = get_current_manifest()

  local updated_files = {}

  -- build up a list of files which have been updated
  for filename, hash in pairs(manifest) do
    if hash ~= old_manifest[filename] then
      table.insert(updated_files, {filename = filename, url = SOURCE_URL .. filename})
    end
  end


  -- if there are any changed files, download all of them and
  -- update the stored manifest file afterward if successful.
  if #updated_files > 0 then
    current_status = 'Downloading update'

    return updater.download_multiple(unpack(updated_files))
      :next(function()
        update_manifest(manifest_json)
      end)
  end

  -- if no files have been changed,
  -- there is no reason to update the local manifest
  return true
end

-- Write some content (ex: json) to the local manifest file
local function update_manifest(content)
  return love.filesystem.write(MANIFEST_FILE, content)
end

-- require your game module
-- module could override love.update, love.draw etc
local function launch()
  require('game').init(arg)
end

-- fetch the current stored manifest data, or an empty table
-- if unavailable
local function get_current_manifest()
  return json.parse(love.filesystem.load('manifest.json') or '{}')
end

function love.load()
  -- Fetch a manifest file from `VERSION_URL`  
  -- Pass manifest data to compare_versions method.  
  -- After any required downloads have completed, launch the game  
  -- If any errors occurred during this process, print an error to the console
  --
  -- _Note: Don't do this. Inform the user about what has happened
  -- and how they might correct it_
  updater.fetch(VERSION_URL)
    :next(compare_versions)
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
  -- Display the current progress status to the user
  love.graphics.print(current_status, 20, 20)
end

function love.keypressed(key)
  if key == 'esc' then
    love.event.quit()
  end
end
