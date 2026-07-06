Summit = {}

Summit.SERVER = 0
Summit.CLIENT = 1
Summit.SHARED = 2

---@param path string
local function defineRealm(path)
    local fname = string.StripExtension(string.GetFileFromFilename(string.lower(path)))
    local prefix, suffix = string.Left(fname, 3), string.Right(fname, 3)

    if fname == 'init' or prefix == 'sv_' or suffix == '_sv' then
        return Summit.SERVER
    elseif prefix == 'cl_' or suffix == '_cl' then
        return Summit.CLIENT
    elseif fname == 'shared' or prefix == 'sh_' or suffix == '_sh' then
        return Summit.SHARED
    end

    return nil
end

---@param path string
---@param realm? integer
---@return unknown
function Summit.File(path, realm)
    realm = realm or defineRealm(path)

    if realm == Summit.SERVER and SERVER then
        return include(path)
    elseif realm == Summit.CLIENT then
        if SERVER then
            AddCSLuaFile(path)
        else -- CLIENT
            return include(path)
        end
    elseif realm == Summit.SHARED then
        if SERVER then
            AddCSLuaFile(path)
        end

        return include(path)
    end

    return nil
end

---@param path string
---@param recursive? boolean | integer
function Summit.Dir(path, recursive)
    local files, dirs = file.Find(path .. '/*', 'LUA')

    for _, fname in ipairs(files) do
        if string.GetExtensionFromFilename(string.lower(fname)) == 'lua' then
            Summit.File(path .. '/' .. fname)
        end
    end

    if recursive then
        if type(recursive) == 'number' then
            recursive = recursive > 1 and recursive - 1 or nil
        end

        for _, dir in ipairs(dirs) do
            Summit.Dir(path .. '/' .. dir, recursive)
        end
    end
end

Summit.LoadedModules = {}

---@class ModuleManifest
---@field Recursive? boolean | integer
---@field Disable? boolean
---@field Dependencies? string[]
---@field ShouldLoad? fun(): boolean
---@field LoadAfter? string[]

---@class CachedModule
---@field path string
---@field manifest ModuleManifest

local MANIFEST_NAME = 'manifest.lua'

---@param path string
---@return table<string, CachedModule>
function cacheModules(path)
    local cache = {}
    local _, dirs = file.Find(path .. '/*' , 'LUA')

    for _, dir in ipairs(dirs) do
        local dirpath = path .. '/' .. dir
        local mpath = dirpath .. '/' .. MANIFEST_NAME
        local manifest

        if file.Exists(mpath, 'LUA') then
            if SERVER then
                AddCSLuaFile(mpath)
            end

            manifest = include(mpath)
        end

        cache[dir] = {
            path = dirpath,
            manifest = manifest or {},
        }
    end

    return cache
end

local LOAD_NEVER = -1
local LOAD_NOW = 0
local LOAD_LATER = 1

---@param manifest ModuleManifest
---@param pending table<string, CachedModule>
local function canLoad(manifest, pending)
    if manifest.Disable then
        return LOAD_NEVER
    end

    if manifest.Dependencies then
        for _, mod in ipairs(manifest.Dependencies) do
            if pending[mod] then
                return LOAD_LATER
            elseif not Summit.LoadedModules[mod] then
                return LOAD_NEVER
            end
        end
    end

    if manifest.LoadAfter then
        for _, mod in ipairs(manifest.LoadAfter) do
            if pending[mod] then
                return LOAD_LATER
            end
        end
    end

    if manifest.ShouldLoad then
        return manifest.ShouldLoad() and LOAD_NOW or LOAD_NEVER
    end

    return LOAD_NOW
end

---@param pending table<string, CachedModule> | string
function Summit.Modules(pending)
    if type(pending) == 'string' then
        pending = cacheModules(pending)
    end

    for mod, info in pairs(pending) do
        local state = canLoad(info.manifest, pending)

        if state == LOAD_NOW then
            Summit.Dir(info.path, info.manifest.Recursive)
            Summit.LoadedModules[mod] = true

            hook.Run('SummitModuleLoaded', mod)
        end

        if state ~= LOAD_LATER then
            pending[mod] = nil
        end
    end

    if next(pending) then
        Summit.Modules(pending)
    end
end
