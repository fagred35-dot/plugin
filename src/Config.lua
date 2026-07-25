local Config = {}

local TOKEN_KEY = "GitHubSync_Token"
local REPO_KEY = "GitHubSync_Repo"

function Config.GetToken(pluginInstance)
    if not pluginInstance then return "" end
    local success, val = pcall(function()
        return pluginInstance:GetSetting(TOKEN_KEY)
    end)
    return success and (val or "") or ""
end

function Config.SetToken(pluginInstance, token)
    if not pluginInstance then return end
    pcall(function()
        pluginInstance:SetSetting(TOKEN_KEY, token)
    end)
end

function Config.GetRepo(pluginInstance)
    if not pluginInstance then return "" end
    local success, val = pcall(function()
        return pluginInstance:GetSetting(REPO_KEY)
    end)
    return success and (val or "") or ""
end

function Config.SetRepo(pluginInstance, repo)
    if not pluginInstance then return end
    pcall(function()
        pluginInstance:SetSetting(REPO_KEY, repo)
    end)
end

return Config
