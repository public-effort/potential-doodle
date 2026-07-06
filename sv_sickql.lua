---@class SickQLInit
---@field Driver 'sqlite' | 'tmysql' | 'mysqloo' | string
---@field Hostname? string
---@field Username? string
---@field Password? string
---@field Database? string
---@field Port? integer

---@class SickQLConnection
---@field Escape fun(self, string: string): string
---@field Query fun(self, query: string, onData?: fun(data: (table<string, string>)[]), onError?: fun(why: string))
---@field Connect fun(self): unknown, unknown
---@field Disconnect fun(self)

if util.IsBinaryModuleInstalled('mysqloo') then
    require('mysqloo')
end

if util.IsBinaryModuleInstalled('tmysql4') then
    require('tmysql4')
end

local CONNECTION_META = {}
CONNECTION_META.__index = CONNECTION_META

---@cast CONNECTION_META { impl: SickQLConnection, driver: unknown }

function CONNECTION_META:Escape(string)
    return self.impl.Escape(self.driver, string)
end

function CONNECTION_META:Query(query, onData, onError)
    return self.impl.Query(self.driver, query, onData, onError)
end

function CONNECTION_META:Disconnect()
    self.impl.Disconnect(self.driver)
end

SickQL = SickQL or {}
---@type table<string, SickQLConnection>
SickQL.Impl = SickQL.Impl or {}

---@param init SickQLInit
---@return SickQLConnection | nil, string | nil
function SickQL:New(init)
    local impl = self.Impl[init.Driver:lower()]

    if impl == nil then
        return nil, 'No such SickQL implementation!'
    end

    local driver, err = impl.Connect(init)

    if err ~= nil then
        return nil, err
    end

    return setmetatable({
        impl = impl,
        driver = driver,
    }, CONNECTION_META), nil
end

SickQL.Impl['sqlite'] = SickQL.Impl['sqlite'] or {
    Connect = function(init)
        return nil, nil
    end,
    Escape = function(string)
        return sql.SQLStr(string, true)
    end,
    Query = function(driver, query, onData, onError)
        local res = sql.Query(query)

        if res == false then
            if onError then
                onError(sql.LastError())
            end

            return
        end

        local data = res or {}

        if onData then
            onData(data)
        end
    end,
    Disconnect = function(driver) end,
}

SickQL.Impl['tmysql'] = SickQL.Impl['tmysql'] or {
    Connect = function(init)
        ---@diagnostic disable-next-line: undefined-global
        local connection, err = tmysql.Connect(
            init.Hostname,
            init.Username,
            init.Password,
            init.Database,
            init.Port
        )

        if err ~= nil then
            return nil, err
        end

        hook.Add('Think', string.format('SickQL.TMySQLPolling(%s)', connection), function()
            connection:Poll()
        end)

        return connection, nil
    end,
    Escape = function(driver, string)
        return driver:Escape(string)
    end,
    Query = function(driver, query, onData, onError)
        driver:Query(query, function(res)
            res = res[1]

            if res.status == true then
                if onData then
                    onData(res.data)
                end
            else
                if onError then
                    onError(res.error)
                end
            end
        end)
    end,
    Disconnect = function(driver)
        driver:Disconnect()
    end,
}

SickQL.Impl['mysqloo'] = SickQL.Impl['mysqloo'] or {
    Connect = function(init)
        ---@diagnostic disable-next-line: undefined-global
        local db = mysqloo.connect(
            init.Hostname,
            init.Username,
            init.Password,
            init.Database,
            init.Port
        )

        local err

        function db:onConnectionFailed(why)
            err = why
        end

        db:connect()
        db:wait()

        ---@diagnostic disable-next-line: undefined-global
        if db:status() == mysqloo.DATABASE_CONNECTED then
            return db, nil
        else
            return nil, err
        end
    end,
    Escape = function(driver, string)
        return driver:escape(string)
    end,
    Query = function(driver, query, onData, onError)
        local q = driver:query(query)

        if onData then
            function q:onSuccess(data)
                onData(data)
            end
        end

        if onError then
            function q:onError(why)
                onError(why)
            end
        end

        q:start()
    end,
    Disconnect = function(driver)
        driver:disconnect()
    end,
}
