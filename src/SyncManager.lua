local GitHubAPI = require(script.Parent.GitHubAPI)
local Serializer = require(script.Parent.Serializer)
local Selection = game:GetService("Selection")

local SyncManager = {}

local function getPlaceName()
    local success, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)
    if success and info and info.Name then
        local name = info.Name:gsub("[^%w%s-_]", ""):gsub("%s+", "_")
        if name ~= "" then return name end
    end
    if game.Name and game.Name ~= "" then
        local name = game.Name:gsub("[^%w%s-_]", ""):gsub("%s+", "_")
        if name ~= "" then return name end
    end
    return "RobloxPlace"
end

local function getObjectPath(obj)
    local parts = {}
    local current = obj
    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    return table.concat(parts, "/")
end

function SyncManager.Push(token, ownerRepo, customBranch, pushAll)
    if not token or token == "" then
        return false, "GitHub Token is not set."
    end
    if not ownerRepo or ownerRepo == "" then
        return false, "Repository path (owner/repo) is not set."
    end
    
    local toProcess = {}
    if pushAll then
        table.insert(toProcess, game:GetService("Workspace"))
        table.insert(toProcess, game:GetService("ServerScriptService"))
        table.insert(toProcess, game:GetService("ReplicatedStorage"))
        table.insert(toProcess, game:GetService("ServerStorage"))
        table.insert(toProcess, game:GetService("StarterPlayer"))
    else
        toProcess = Selection:Get()
    end
    
    if #toProcess == 0 then
        return false, "No scripts or objects selected in Roblox Studio. Please select scripts or parent folders (holding Ctrl)."
    end
    
    local branch = customBranch
    if not branch or branch == "" then
        local successBranch, branchOrErr = GitHubAPI.GetDefaultBranch(token, ownerRepo)
        branch = successBranch and branchOrErr or "main"
    end
    
    local placeName = getPlaceName()
    local pushedCount = 0
    local errors = {}
    
    local function processObject(obj)
        local className = obj.ClassName
        if className == "Script" or className == "LocalScript" or className == "ModuleScript" then
            local fileContent, err = Serializer.Serialize(obj)
            if fileContent then
                local objPath = getObjectPath(obj)
                local remotePath = string.format("%s/%s.lua", placeName, objPath)
                local msg = string.format("Push %s (%s)", obj.Name, className)
                
                local successPut, putErr = GitHubAPI.PutFile(token, ownerRepo, remotePath, fileContent, msg, branch)
                if successPut then
                    pushedCount = pushedCount + 1
                else
                    table.insert(errors, string.format("%s: %s", objPath, tostring(putErr)))
                end
            else
                table.insert(errors, string.format("%s: %s", obj.Name, tostring(err)))
            end
        elseif obj:IsA("Folder") or obj:IsA("Model") or obj:IsA("Workspace") or obj:IsA("DataModelHolder") or obj:IsA("Service") then
            for _, child in ipairs(obj:GetChildren()) do
                processObject(child)
            end
        end
    end
    
    for _, item in ipairs(toProcess) do
        processObject(item)
    end
    
    if pushedCount == 0 and #errors > 0 then
        return false, "Push failed:\n" .. table.concat(errors, "\n")
    elseif #errors > 0 then
        return true, string.format("Pushed %d script(s) with %d error(s).", pushedCount, #errors)
    else
        return true, string.format("Successfully pushed %d script(s) to %s/%s!", pushedCount, ownerRepo, placeName)
    end
end

function SyncManager.Pull(token, ownerRepo, customBranch)
    if not token or token == "" then
        return false, "GitHub Token is not set."
    end
    if not ownerRepo or ownerRepo == "" then
        return false, "Repository path (owner/repo) is not set."
    end
    
    local selected = Selection:Get()
    
    local branch = customBranch
    if not branch or branch == "" then
        local successBranch, branchOrErr = GitHubAPI.GetDefaultBranch(token, ownerRepo)
        branch = successBranch and branchOrErr or "main"
    end
    
    local successTree, treeData = GitHubAPI.GetRepoTree(token, ownerRepo, branch)
    if not successTree or not treeData or not treeData.tree then
        return false, "Failed to fetch repository tree: " .. tostring(treeData)
    end
    
    local placeName = getPlaceName()
    
    if #selected > 0 then
        local updatedCount = 0
        local errors = {}
        
        for _, selObj in ipairs(selected) do
            if selObj.ClassName == "Script" or selObj.ClassName == "LocalScript" or selObj.ClassName == "ModuleScript" then
                local objPath = getObjectPath(selObj)
                local remotePath = string.format("%s/%s.lua", placeName, objPath)
                
                local successContent, content = GitHubAPI.GetFileContent(token, ownerRepo, remotePath, branch)
                if successContent then
                    local _, cleanSource = Serializer.Deserialize(content)
                    selObj.Source = cleanSource
                    updatedCount = updatedCount + 1
                else
                    local found = false
                    local escapedName = selObj.Name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
                    for _, node in ipairs(treeData.tree) do
                        if node.type == "blob" and (node.path:match("/" .. escapedName .. "%.lua$") or node.path:match("/" .. escapedName .. "%.luau$")) then
                            local sCont, cnt = GitHubAPI.GetFileContent(token, ownerRepo, node.path, branch)
                            if sCont then
                                local _, cleanSource = Serializer.Deserialize(cnt)
                                selObj.Source = cleanSource
                                found = true
                                updatedCount = updatedCount + 1
                                break
                            end
                        end
                    end
                    if not found then
                        table.insert(errors, string.format("Could not find remote file for %s", selObj.Name))
                    end
                end
            end
        end
        
        if updatedCount == 0 and #errors > 0 then
            return false, "Selective Pull failed:\n" .. table.concat(errors, "\n")
        else
            return true, string.format("Successfully updated %d script(s) via Selective Pull.", updatedCount)
        end
    else
        local workspace = game:GetService("Workspace")
        local importedCount = 0
        local errors = {}
        
        local prefix = placeName .. "/"
        local foldersCache = {
            ["Workspace"] = workspace
        }
        
        local function getOrCreateFolder(pathParts)
            local currentParent = game
            local currentPathKey = ""
            
            local startIndex = 1
            if #pathParts > 0 and pathParts[1] == placeName then
                startIndex = 2
            end
            
            if #pathParts >= startIndex then
                local serviceName = pathParts[startIndex]
                local success, service = pcall(function() return game:GetService(serviceName) end)
                if success and service then
                    currentParent = service
                    currentPathKey = serviceName
                    startIndex = startIndex + 1
                else
                    -- If it's not a service, start from Workspace as default
                    currentParent = game:GetService("Workspace")
                    currentPathKey = "Workspace"
                end
            else
                currentParent = game:GetService("Workspace")
                currentPathKey = "Workspace"
            end
            
            for i = startIndex, #pathParts - 1 do
                local folderName = pathParts[i]
                currentPathKey = (currentPathKey == "" and "" or currentPathKey .. "/") .. folderName
                local existing = foldersCache[currentPathKey]
                if not existing then
                    existing = currentParent:FindFirstChild(folderName)
                    if not existing or not existing:IsA("Folder") then
                        existing = Instance.new("Folder")
                        existing.Name = folderName
                        existing.Parent = currentParent
                    end
                    foldersCache[currentPathKey] = existing
                end
                currentParent = existing
            end
            
            return currentParent
        end
        
        for _, node in ipairs(treeData.tree) do
            if node.type == "blob" and node.path:sub(1, #prefix) == prefix then
                local relPath = node.path:sub(#prefix + 1)
                local parts = string.split(relPath, "/")
                
                if #parts > 0 then
                    local fileNameWithExt = parts[#parts]
                    local fileName = fileNameWithExt:gsub("%.lua$", ""):gsub("%.luau$", "")
                    
                    local parentFolder = getOrCreateFolder(parts)
                    
                    local successContent, content = GitHubAPI.GetFileContent(token, ownerRepo, node.path, branch)
                    if successContent then
                        local scriptType, cleanSource = Serializer.Deserialize(content)
                        
                        local existingScript = parentFolder:FindFirstChild(fileName)
                        if existingScript and (existingScript.ClassName == "Script" or existingScript.ClassName == "LocalScript" or existingScript.ClassName == "ModuleScript") then
                            existingScript.Source = cleanSource
                        else
                            if existingScript then
                                existingScript:Destroy()
                            end
                            local newScript = Instance.new(scriptType)
                            newScript.Name = fileName
                            newScript.Source = cleanSource
                            newScript.Parent = parentFolder
                        end
                        importedCount = importedCount + 1
                    else
                        table.insert(errors, "Failed to download " .. node.path)
                    end
                end
            end
        end
        
        if importedCount == 0 and #errors > 0 then
            return false, "Safe Pull failed:\n" .. table.concat(errors, "\n")
        else
            return true, string.format("Successfully pulled and imported %d file(s) into Workspace!", importedCount)
        end
    end
end

return SyncManager
