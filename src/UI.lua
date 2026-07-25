local Config = require(script.Parent.Config)
local GitHubAPI = require(script.Parent.GitHubAPI)
local SyncManager = require(script.Parent.SyncManager)

local UI = {}

function UI.Init(plugin)
    local toolbar = plugin:CreateToolbar("GitHub Sync")
    
    local pushButton = toolbar:CreateButton("GitHubPush", "Push scripts to GitHub", "rbxassetid://6023426915", "Push")
    local pullButton = toolbar:CreateButton("GitHubPull", "Pull scripts from GitHub", "rbxassetid://6023426915", "Pull")
    local settingsButton = toolbar:CreateButton("GitHubSettings", "GitHub Settings", "rbxassetid://6023426915", "Settings")
    local viewerButton = toolbar:CreateButton("GitHubViewer", "Repository Viewer", "rbxassetid://6023426915", "Repo Viewer")
    
    local settingsWidgetInfo = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,
        false,
        false,
        350, 200,
        300, 150
    )
    local settingsWidget = plugin:CreateDockWidgetPluginGui("GitHubSyncSettings", settingsWidgetInfo)
    settingsWidget.Title = "GitHub Sync - Settings"
    
    local viewerWidgetInfo = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,
        false,
        false,
        500, 400,
        400, 300
    )
    local viewerWidget = plugin:CreateDockWidgetPluginGui("GitHubSyncViewer", viewerWidgetInfo)
    viewerWidget.Title = "GitHub Repository Viewer"
    
    -- Settings GUI
    local settingsGui = Instance.new("Frame")
    settingsGui.Size = UDim2.new(1, 0, 1, 0)
    settingsGui.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    settingsGui.Parent = settingsWidget
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 10)
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    listLayout.Parent = settingsGui
    
    local tokenLabel = Instance.new("TextLabel")
    tokenLabel.Size = UDim2.new(0.9, 0, 0, 25)
    tokenLabel.BackgroundTransparency = 1
    tokenLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    tokenLabel.TextXAlignment = Enum.TextXAlignment.Left
    tokenLabel.Text = "GitHub Personal Access Token (PAT):"
    tokenLabel.Parent = settingsGui
    
    local tokenBox = Instance.new("TextBox")
    tokenBox.Size = UDim2.new(0.9, 0, 0, 35)
    tokenBox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    tokenBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    tokenBox.TextSize = 14
    tokenBox.ClearTextOnFocus = false
    tokenBox.Text = Config.GetToken(plugin)
    tokenBox.Parent = settingsGui
    
    local repoLabel = Instance.new("TextLabel")
    repoLabel.Size = UDim2.new(0.9, 0, 0, 25)
    repoLabel.BackgroundTransparency = 1
    repoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    repoLabel.TextXAlignment = Enum.TextXAlignment.Left
    repoLabel.Text = "Repository (owner/repo):"
    repoLabel.Parent = settingsGui
    
    local repoBox = Instance.new("TextBox")
    repoBox.Size = UDim2.new(0.9, 0, 0, 35)
    repoBox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    repoBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    repoBox.TextSize = 14
    repoBox.ClearTextOnFocus = false
    repoBox.Text = Config.GetRepo(plugin)
    repoBox.Parent = settingsGui
    
    local saveButton = Instance.new("TextButton")
    saveButton.Size = UDim2.new(0.9, 0, 0, 35)
    saveButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
    saveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    saveButton.TextSize = 16
    saveButton.Font = Enum.Font.SourceSansBold
    saveButton.Text = "Save Settings"
    saveButton.Parent = settingsGui
    
    saveButton.MouseButton1Click:Connect(function()
        Config.SetToken(plugin, tokenBox.Text)
        Config.SetRepo(plugin, repoBox.Text)
        saveButton.Text = "Saved!"
        task.wait(1.5)
        saveButton.Text = "Save Settings"
    end)
    
    -- Repository Viewer GUI
    local viewerGui = Instance.new("Frame")
    viewerGui.Size = UDim2.new(1, 0, 1, 0)
    viewerGui.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    viewerGui.Parent = viewerWidget
    
    local viewerTopBar = Instance.new("Frame")
    viewerTopBar.Size = UDim2.new(1, 0, 0, 40)
    viewerTopBar.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    viewerTopBar.BorderSizePixel = 0
    viewerTopBar.Parent = viewerGui
    
    local refreshButton = Instance.new("TextButton")
    refreshButton.Size = UDim2.new(0, 120, 0, 30)
    refreshButton.Position = UDim2.new(0, 10, 0, 5)
    refreshButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
    refreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    refreshButton.Font = Enum.Font.SourceSansBold
    refreshButton.TextSize = 14
    refreshButton.Text = "Refresh Viewer"
    refreshButton.Parent = viewerTopBar
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -140, 1, 0)
    statusLabel.Position = UDim2.new(0, 140, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    statusLabel.TextSize = 14
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Text = "Click Refresh to load repository files."
    statusLabel.Parent = viewerTopBar
    
    local scrollingFrame = Instance.new("ScrollingFrame")
    scrollingFrame.Size = UDim2.new(1, 0, 1, -40)
    scrollingFrame.Position = UDim2.new(0, 0, 0, 40)
    scrollingFrame.BackgroundTransparency = 1
    scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollingFrame.Parent = viewerGui
    
    local scrollerLayout = Instance.new("UIListLayout")
    scrollerLayout.Padding = UDim.new(0, 4)
    scrollerLayout.Parent = scrollingFrame
    
    local function refreshViewer()
        local token = Config.GetToken(plugin)
        local repo = Config.GetRepo(plugin)
        if token == "" or repo == "" then
            statusLabel.Text = "Error: Token or Repository not configured in Settings."
            return
        end
        
        statusLabel.Text = "Fetching repository tree..."
        for _, child in ipairs(scrollingFrame:GetChildren()) do
            if child:IsA("TextLabel") then
                child:Destroy()
            end
        end
        
        local successBranch, branchOrErr = GitHubAPI.GetDefaultBranch(token, repo)
        local branch = successBranch and branchOrErr or "main"
        
        local successTree, treeData = GitHubAPI.GetRepoTree(token, repo, branch)
        if not successTree or not treeData or not treeData.tree then
            statusLabel.Text = "Failed to fetch tree: " .. tostring(treeData)
            return
        end
        
        local count = 0
        for _, node in ipairs(treeData.tree) do
            if node.type == "blob" then
                count = count + 1
                local itemLabel = Instance.new("TextLabel")
                itemLabel.Size = UDim2.new(1, -20, 0, 24)
                itemLabel.BackgroundTransparency = 1
                itemLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
                itemLabel.TextSize = 13
                itemLabel.TextXAlignment = Enum.TextXAlignment.Left
                itemLabel.Text = "  " .. node.path
                itemLabel.Parent = scrollingFrame
            end
        end
        
        statusLabel.Text = string.format("Loaded %d file(s) from branch '%s'.", count, branch)
    end
    
    refreshButton.MouseButton1Click:Connect(refreshViewer)
    
    settingsButton.Click:Connect(function()
        settingsWidget.Enabled = not settingsWidget.Enabled
    end)
    
    viewerButton.Click:Connect(function()
        viewerWidget.Enabled = not viewerWidget.Enabled
        if viewerWidget.Enabled then
            refreshViewer()
        end
    end)
    
    pushButton.Click:Connect(function()
        local token = Config.GetToken(plugin)
        local repo = Config.GetRepo(plugin)
        
        print("[GitHubSync] Pushing to GitHub...")
        local success, message = SyncManager.Push(token, repo)
        print("[GitHubSync]", message)
        
        if success then
            pushButton.SetActive(true)
            task.delay(2, function()
                pushButton.SetActive(false)
            end)
        else
            pushButton.SetActive(false)
        end
    end)
    
    pullButton.Click:Connect(function()
        local token = Config.GetToken(plugin)
        local repo = Config.GetRepo(plugin)
        
        print("[GitHubSync] Pulling from GitHub...")
        local success, message = SyncManager.Pull(token, repo)
        print("[GitHubSync]", message)
    end)
end

return UI
