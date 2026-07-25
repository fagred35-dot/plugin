-- GitHub Sync Plugin Entry Point
local pluginInstance = plugin

if not pluginInstance then
    return
end

local UI = require(script.Parent.UI)
local Config = require(script.Parent.Config)
local SyncManager = require(script.Parent.SyncManager)
local GitHubAPI = require(script.Parent.GitHubAPI)

UI.Init(pluginInstance)

-- Auto-Sync Logic
task.spawn(function()
    task.wait(5) -- Wait for things to settle
    
    local lastCheckedSha = nil
    
    while true do
        local enabled = Config.GetAutoSync(pluginInstance)
        local token = Config.GetToken(pluginInstance)
        local repo = Config.GetRepo(pluginInstance)
        
        if enabled and token ~= "" and repo ~= "" then
            local branch = Config.GetBranch(pluginInstance)
            if branch == "" then
                local successBranch, branchOrErr = GitHubAPI.GetDefaultBranch(token, repo)
                branch = successBranch and branchOrErr or "main"
            end
            
            -- 1. Initial Push (only once per session or if enabled)
            if not lastCheckedSha then
                print("[GitHubSync] Auto-Sync: Initial Push...")
                SyncManager.Push(token, repo, branch, true)
            end
            
            -- 2. Check for updates on GitHub
            local successCommit, commitData = GitHubAPI.GetLatestCommitSha(token, repo, branch)
            if successCommit and commitData and commitData.sha then
                if lastCheckedSha and commitData.sha ~= lastCheckedSha then
                    print("[GitHubSync] Auto-Sync: Remote changes detected, pulling...")
                    SyncManager.Pull(token, repo, branch)
                end
                lastCheckedSha = commitData.sha
            end
        end
        
        task.wait(60) -- Check every minute
    end
end)

print("[GitHubSync] Plugin initialized successfully.")
