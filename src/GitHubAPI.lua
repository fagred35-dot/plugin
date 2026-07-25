local HttpService = game:GetService("HttpService")
local Base64 = require(script.Parent.Base64)

local GitHubAPI = {}

function GitHubAPI.MakeRequest(token, url, method, body)
    local headers = {
        ["Authorization"] = "token " .. token,
        ["Accept"] = "application/vnd.github+json",
        ["X-GitHub-Api-Version"] = "2022-11-28",
        ["Content-Type"] = "application/json"
    }
    
    local requestData = {
        Url = url,
        Method = method or "GET",
        Headers = headers
    }
    
    if body then
        requestData.Body = HttpService:JSONEncode(body)
    end
    
    local success, response = pcall(function()
        return HttpService:RequestAsync(requestData)
    end)
    
    if not success then
        return false, "HTTP Request failed: " .. tostring(response)
    end
    
    if response.Success then
        local data = nil
        pcall(function()
            if response.Body and response.Body ~= "" then
                data = HttpService:JSONDecode(response.Body)
            end
        end)
        return true, data, response.StatusCode
    else
        return false, string.format("GitHub API Error (%d): %s", response.StatusCode, response.Body or "Unknown error"), response.StatusCode
    end
end

function GitHubAPI.GetDefaultBranch(token, ownerRepo)
    local url = string.format("https://api.github.com/repos/%s", ownerRepo)
    local success, data, code = GitHubAPI.MakeRequest(token, url, "GET")
    if not success then
        return false, data
    end
    return true, data.default_branch or "main"
end

function GitHubAPI.GetRepoTree(token, ownerRepo, branch)
    local url = string.format("https://api.github.com/repos/%s/git/trees/%s?recursive=1", ownerRepo, branch)
    return GitHubAPI.MakeRequest(token, url, "GET")
end

function GitHubAPI.GetFileSha(token, ownerRepo, path)
    local url = string.format("https://api.github.com/repos/%s/contents/%s", ownerRepo, path)
    local success, data = GitHubAPI.MakeRequest(token, url, "GET")
    if success and type(data) == "table" and data.sha then
        return data.sha
    end
    return nil
end

function GitHubAPI.PutFile(token, ownerRepo, path, content, message)
    local url = string.format("https://api.github.com/repos/%s/contents/%s", ownerRepo, path)
    -- First get existing SHA if any
    local sha = GitHubAPI.GetFileSha(token, ownerRepo, path)
    
    local encodedContent = Base64.encode(content)
    local body = {
        message = message or ("Update " .. path),
        content = encodedContent
    }
    if sha then
        body.sha = sha
    end
    
    return GitHubAPI.MakeRequest(token, url, "PUT", body)
end

function GitHubAPI.GetFileContent(token, ownerRepo, path)
    local url = string.format("https://api.github.com/repos/%s/contents/%s", ownerRepo, path)
    local success, data = GitHubAPI.MakeRequest(token, url, "GET")
    if success and type(data) == "table" and data.content then
        local decoded = Base64.decode(data.content)
        return true, decoded, data.sha
    end
    return false, "Failed to get file content or file not found"
end

return GitHubAPI
