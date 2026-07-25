local HttpService = game:GetService("HttpService")
local Base64 = require(script.Parent.Base64)

local GitHubAPI = {}

-- Percent-encodes a value so branch names like "feature/new-ui" or paths with
-- spaces do not break (or silently change) the requested URL.
function GitHubAPI.UrlEncode(value)
    return (tostring(value):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- Encodes a repository path, keeping "/" as a real path separator.
function GitHubAPI.UrlEncodePath(path)
    local parts = string.split(tostring(path), "/")
    for i, part in ipairs(parts) do
        parts[i] = GitHubAPI.UrlEncode(part)
    end
    return table.concat(parts, "/")
end

-- GitHub answers GET requests with "Cache-Control: private, max-age=60", so a
-- plain GET can hand back a snapshot of the repository that is up to a minute
-- old (deleted files still appear, freshly pushed files are missing).
-- We disable caching explicitly AND add a unique query parameter so neither
-- GitHub's CDN nor Roblox's HTTP layer can reuse an old response.
local function withCacheBuster(url)
    local separator = string.find(url, "?", 1, true) and "&" or "?"
    return string.format("%s%s_=%d%d", url, separator, os.time(), math.random(0, 999999))
end

function GitHubAPI.MakeRequest(token, url, method, body)
    local headers = {
        ["Authorization"] = "token " .. token,
        ["Accept"] = "application/vnd.github+json",
        ["X-GitHub-Api-Version"] = "2022-11-28",
        ["Content-Type"] = "application/json",
        ["Cache-Control"] = "no-cache, no-store, must-revalidate",
        ["Pragma"] = "no-cache",
        ["If-None-Match"] = ""
    }

    method = method or "GET"
    if method == "GET" then
        url = withCacheBuster(url)
    end

    local requestData = {
        Url = url,
        Method = method,
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
    local success, data = GitHubAPI.MakeRequest(token, url, "GET")
    if not success then
        return false, data
    end
    return true, data.default_branch or "main"
end

function GitHubAPI.GetBranches(token, ownerRepo)
    local branches = {}
    local page = 1

    -- GitHub returns max 100 items per page; without paging repositories with
    -- many branches only exposed the first 30.
    while page <= 10 do
        local url = string.format("https://api.github.com/repos/%s/branches?per_page=100&page=%d", ownerRepo, page)
        local success, data = GitHubAPI.MakeRequest(token, url, "GET")
        if not success or type(data) ~= "table" then
            if page == 1 then
                return false, data or "Failed to fetch branches"
            end
            break
        end

        if #data == 0 then
            break
        end

        for _, branchObj in ipairs(data) do
            if branchObj and branchObj.name then
                table.insert(branches, branchObj.name)
            end
        end

        if #data < 100 then
            break
        end
        page = page + 1
    end

    if #branches == 0 then
        local ok, def = GitHubAPI.GetDefaultBranch(token, ownerRepo)
        table.insert(branches, ok and def or "main")
    end

    return true, branches
end

function GitHubAPI.GetLatestCommitSha(token, ownerRepo, branch)
    if not branch or branch == "" then
        local ok, def = GitHubAPI.GetDefaultBranch(token, ownerRepo)
        branch = ok and def or "main"
    end
    local url = string.format("https://api.github.com/repos/%s/commits/%s", ownerRepo, GitHubAPI.UrlEncode(branch))
    return GitHubAPI.MakeRequest(token, url, "GET")
end

function GitHubAPI.GetRepoTree(token, ownerRepo, branch)
    if not branch or branch == "" then
        local ok, def = GitHubAPI.GetDefaultBranch(token, ownerRepo)
        branch = ok and def or "main"
    end

    -- Resolve the branch to its current commit SHA first. Asking the tree API
    -- for a branch name can return a stale/ambiguous tree when a tag or another
    -- ref shares that name, which made deleted files keep showing up.
    local refUrl = string.format("https://api.github.com/repos/%s/commits/%s",
        ownerRepo, GitHubAPI.UrlEncode(branch))
    local okRef, refData = GitHubAPI.MakeRequest(token, refUrl, "GET")

    local treeRef = GitHubAPI.UrlEncode(branch)
    if okRef and type(refData) == "table" and refData.sha then
        treeRef = refData.sha
    end

    local url = string.format("https://api.github.com/repos/%s/git/trees/%s?recursive=1", ownerRepo, treeRef)
    local success, data, code = GitHubAPI.MakeRequest(token, url, "GET")

    if success and type(data) == "table" and data.truncated then
        warn("[GitHubSync Warning] Repository tree was truncated by GitHub; file list may be incomplete.")
    end

    return success, data, code
end

function GitHubAPI.GetFileSha(token, ownerRepo, path, branch)
    local url = string.format("https://api.github.com/repos/%s/contents/%s", ownerRepo, GitHubAPI.UrlEncodePath(path))
    if branch and branch ~= "" then
        url = url .. "?ref=" .. GitHubAPI.UrlEncode(branch)
    end
    local success, data = GitHubAPI.MakeRequest(token, url, "GET")
    if success and type(data) == "table" and data.sha then
        return data.sha
    end
    return nil
end

function GitHubAPI.PutFile(token, ownerRepo, path, content, message, branch)
    local url = string.format("https://api.github.com/repos/%s/contents/%s", ownerRepo, GitHubAPI.UrlEncodePath(path))
    -- First get existing SHA if any (on the same branch we are writing to)
    local sha = GitHubAPI.GetFileSha(token, ownerRepo, path, branch)

    local encodedContent = Base64.encode(content)
    local body = {
        message = message or ("Update " .. path),
        content = encodedContent
    }
    if sha then
        body.sha = sha
    end
    if branch and branch ~= "" then
        body.branch = branch
    end

    return GitHubAPI.MakeRequest(token, url, "PUT", body)
end

function GitHubAPI.GetFileContent(token, ownerRepo, path, branch)
    local url = string.format("https://api.github.com/repos/%s/contents/%s", ownerRepo, GitHubAPI.UrlEncodePath(path))
    if branch and branch ~= "" then
        url = url .. "?ref=" .. GitHubAPI.UrlEncode(branch)
    end
    local success, data = GitHubAPI.MakeRequest(token, url, "GET")
    if success and type(data) == "table" and data.content then
        local decoded = Base64.decode(data.content)
        return true, decoded, data.sha
    end
    return false, "Failed to get file content or file not found: " .. tostring(path)
end

return GitHubAPI
