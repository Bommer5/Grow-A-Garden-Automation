--[==[
	MockGarden.client.lua
	Test harness for Grow-A-Garden-Automation.

	Builds a fake Grow A Garden interface inside your own Roblox Studio place so
	you can run main.py against it without touching the live game.

	Install: StarterPlayer > StarterPlayerScripts > new LocalScript, paste this in.
	Run with F5 in Studio, then press F11 for fullscreen so screen pixels line up.

	Hotkeys (harness, not the game):
		F5  force a restock now
		F6  toggle fast hatch (hatchSeconds -> 2)
		F7  reset the HUD counters
--]==]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CONFIG = {
	-- The macro's coordinates are calibrated on 1920x1080, so every element is
	-- placed as a fraction of that design space and stays proportional.
	designWidth = 1920,
	designHeight = 1080,

	-- Restock on the real clock's 5-minute mark, matching main.py's isFiveMinMark().
	restockOnClockMark = true,

	hatchSeconds = 10,
	stockMin = 1,
	stockMax = 8,
	rowHeight = 90,
}

local SEEDS = {
	"Carrot", "Strawberry", "Blueberry", "Orange Tulip", "Tomato", "Corn",
	"Daffodil", "Watermelon", "Pumpkin", "Apple", "Bamboo", "Coconut",
	"Cactus", "Dragon Fruit", "Mango", "Grape", "Mushroom", "Pepper",
	"Cacao", "Beanstalk", "Ember Lily", "Sugar Apple",
}

local GEAR = {
	"Watering Can", "Trowel", "Recall Wrench", "Basic Sprinkler",
	"Advanced Sprinkler", "Medium Toy", "Medium Treat", "Godly Sprinkler",
	"Tanning Mirror", "Master Sprinkler", "Levelup Lollipop",
}

local EGGS = { "Common Egg", "Uncommon Egg", "Rare Egg", "Legendary Egg", "Bug Egg" }

local PETS = {
	"Starfish", "Bunny", "Dog", "Golden Lab", "Raccoon", "Dragonfly",
	"Queen Bee", "Red Fox",
}

----------------------------------------------------------------------
-- geometry helpers
----------------------------------------------------------------------

local function pos(x, y)
	return UDim2.fromScale(x / CONFIG.designWidth, y / CONFIG.designHeight)
end

local function size(w, h)
	return UDim2.fromScale(w / CONFIG.designWidth, h / CONFIG.designHeight)
end

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------

local state = {
	wrenchEquipped = false,
	atGearShop = false,
	dialogueOpen = false,
	openShop = nil, -- "gear" | "seed" | "egg" | nil
	selectedEgg = nil,
	clicksSeen = 0,
	wastedClicks = 0,
	bought = {},
	hatched = {},
	lastAction = "idle",
	plots = {},
}

local function log(msg)
	state.lastAction = msg
	print("[harness] " .. msg)
end

----------------------------------------------------------------------
-- root gui
----------------------------------------------------------------------

local root = new("ScreenGui", {
	Name = "MockGAG",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

new("Frame", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(28, 42, 30),
	BorderSizePixel = 0,
	ZIndex = 0,
}, root)

----------------------------------------------------------------------
-- top bar: Seeds / Garden / Eggs
----------------------------------------------------------------------

-- Matches constantsPositions.py: seeds at (680,135), garden at (960,137).
local function topBarButton(name, x, y, text)
	return new("TextButton", {
		Name = name,
		Position = pos(x - 70, y - 26),
		Size = size(140, 52),
		BackgroundColor3 = Color3.fromRGB(58, 94, 62),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		Text = text,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, root)
end

local seedsButton = topBarButton("SeedsButton", 680, 135, "Seeds")
local gardenButton = topBarButton("GardenButton", 960, 137, "Garden")
local eggsButton = topBarButton("EggsButton", 1240, 136, "Eggs")

----------------------------------------------------------------------
-- HUD so you can see what the macro actually did
----------------------------------------------------------------------

local hud = new("Frame", {
	Name = "HUD",
	Position = pos(20, 20),
	Size = size(420, 190),
	BackgroundColor3 = Color3.fromRGB(18, 18, 20),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	ZIndex = 50,
}, root)

local hudText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(190, 255, 190),
	Font = Enum.Font.Code,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
}, hud)

local function countKeys(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

local function refreshHud()
	local pct = 0
	if state.clicksSeen > 0 then
		pct = math.floor((state.wastedClicks / state.clicksSeen) * 100)
	end
	hudText.Text = string.format(
		" shop: %s   wrench: %s\n clicks seen: %d  (wasted: %d / %d%%)\n bought: %d kinds\n hatched: %d pets\n hatch time: %ds\n last: %s\n F5 restock  F6 fast-hatch  F7 reset",
		tostring(state.openShop),
		state.wrenchEquipped and "yes" or "no",
		state.clicksSeen,
		state.wastedClicks,
		pct,
		countKeys(state.bought),
		#state.hatched,
		CONFIG.hatchSeconds,
		state.lastAction
	)
end

----------------------------------------------------------------------
-- shop window
----------------------------------------------------------------------

-- Matches constantsPositions.py: 555,225 -> 1360,980.
local shopWindow = new("Frame", {
	Name = "ShopWindow",
	Position = pos(555, 225),
	Size = size(1360 - 555, 980 - 225),
	BackgroundColor3 = Color3.fromRGB(242, 236, 214),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 10,
}, root)

local shopTitle = new("TextLabel", {
	Name = "ShopTitle",
	Position = UDim2.fromScale(0, 0),
	Size = size(1360 - 555, 70),
	BackgroundColor3 = Color3.fromRGB(96, 142, 86),
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextSize = 30,
	-- buy.py keys off a "Stock" template (filepaths.shopOpenPath) to confirm the
	-- shop is open, so the word has to be in the header.
	Text = "Seed Stock",
	BorderSizePixel = 0,
	ZIndex = 11,
}, shopWindow)

-- Matches constantsPositions.py: X button at (1290,265).
local closeButton = new("TextButton", {
	Name = "CloseButton",
	Position = pos(1290 - 555 - 22, 265 - 225 - 22),
	Size = size(44, 44),
	BackgroundColor3 = Color3.fromRGB(196, 72, 64),
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextSize = 26,
	Text = "X",
	BorderSizePixel = 0,
	ZIndex = 12,
}, shopWindow)

local itemList = new("ScrollingFrame", {
	Name = "ItemList",
	Position = UDim2.fromScale(0, 70 / (980 - 225)),
	Size = UDim2.fromScale(1, 1 - 70 / (980 - 225)),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(),
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ZIndex = 11,
}, shopWindow)

new("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, itemList)

----------------------------------------------------------------------
-- rows
----------------------------------------------------------------------

local function makeRow(itemName, price, order)
	local stock = math.random(CONFIG.stockMin, CONFIG.stockMax)

	local row = new("Frame", {
		Name = "Row_" .. itemName,
		Size = UDim2.new(1, -16, 0, CONFIG.rowHeight),
		BackgroundColor3 = Color3.fromRGB(255, 252, 240),
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, itemList)

	-- Item name on top...
	local nameLabel = new("TextLabel", {
		Name = "ItemName",
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(0.6, 0, 0, 34),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(40, 40, 40),
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = itemName,
	}, row)

	-- ...and the price BELOW it. buy.py relies on this ordering: it only clicks a
	-- money symbol whose Y is greater than the item's Y, otherwise the price
	-- belongs to the row above.
	local priceButton = new("TextButton", {
		Name = "MoneySymbol",
		Position = UDim2.fromOffset(14, 46),
		Size = UDim2.fromOffset(170, 34),
		BackgroundColor3 = Color3.fromRGB(252, 226, 140),
		TextColor3 = Color3.fromRGB(60, 50, 10),
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		Text = "$ " .. price,
		BorderSizePixel = 0,
	}, row)

	local stockLabel = new("TextLabel", {
		Name = "StockLabel",
		Position = UDim2.new(0.68, 0, 0, 28),
		Size = UDim2.new(0.3, 0, 0, 34),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(90, 110, 90),
		Font = Enum.Font.Code,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "x" .. stock,
	}, row)

	local function setStock(n)
		stock = n
		stockLabel.Text = "x" .. stock
		if stock <= 0 then
			-- Out of stock hides the money symbol, exactly like the real shop,
			-- so the macro has nothing to match and moves on.
			priceButton.Visible = false
			nameLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			stockLabel.Text = "SOLD OUT"
		else
			priceButton.Visible = true
			nameLabel.TextColor3 = Color3.fromRGB(40, 40, 40)
		end
	end

	priceButton.MouseButton1Click:Connect(function()
		state.clicksSeen += 1
		if stock <= 0 then
			-- This is the interesting number: buy.py fires 40 clicks per item
			-- regardless of stock, so everything past the last unit is waste.
			state.wastedClicks += 1
		else
			setStock(stock - 1)
			state.bought[itemName] = (state.bought[itemName] or 0) + 1
			if state.openShop == "egg" then
				state.selectedEgg = itemName
				log("bought " .. itemName .. " (egg ready to place)")
			else
				log("bought " .. itemName)
			end
		end
		refreshHud()
	end)

	setStock(stock)
	return { row = row, setStock = setStock, reroll = function()
		setStock(math.random(CONFIG.stockMin, CONFIG.stockMax))
	end }
end

local shopRows = { gear = {}, seed = {}, egg = {} }

local function buildShop(kind, items, basePrice)
	local rows = {}
	for i, itemName in ipairs(items) do
		rows[i] = makeRow(itemName, basePrice * i, i)
		rows[i].row.Visible = false
		rows[i].row.Name = kind .. "_" .. itemName
	end
	shopRows[kind] = rows
end

buildShop("seed", SEEDS, 25)
buildShop("gear", GEAR, 120)
buildShop("egg", EGGS, 5000)

local function showShop(kind)
	local titles = { seed = "Seed Stock", gear = "Gear Stock", egg = "Egg Stock" }
	for group, rows in pairs(shopRows) do
		for _, entry in ipairs(rows) do
			entry.row.Visible = (group == kind)
		end
	end
	shopTitle.Text = titles[kind]
	local count = #shopRows[kind]
	itemList.CanvasSize = UDim2.fromOffset(0, count * (CONFIG.rowHeight + 6))
	itemList.CanvasPosition = Vector2.new()
	shopWindow.Visible = true
	state.openShop = kind
	log("opened " .. kind .. " shop")
	refreshHud()
end

local function closeShop()
	shopWindow.Visible = false
	state.openShop = nil
	state.dialogueOpen = false
	log("shop closed")
	refreshHud()
end

closeButton.MouseButton1Click:Connect(closeShop)

----------------------------------------------------------------------
-- gear shop dialogue (exercises moveToGearShop)
----------------------------------------------------------------------

-- Matches constantsPositions.py: options region 960,515 -> 1700,700.
local dialogue = new("Frame", {
	Name = "Dialogue",
	Position = pos(960, 515),
	Size = size(1700 - 960, 700 - 515),
	BackgroundColor3 = Color3.fromRGB(30, 30, 36),
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 20,
}, root)

new("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, dialogue)

-- Three wordings, mirroring the three showGearShopImagePaths templates.
local DIALOGUE_OPTIONS = {
	"Show me your gear shop",
	"Let me see the gear",
	"Open gear shop",
}

for i, text in ipairs(DIALOGUE_OPTIONS) do
	local opt = new("TextButton", {
		Name = "GearOption" .. i,
		Size = UDim2.new(1, -16, 0, 50),
		BackgroundColor3 = Color3.fromRGB(70, 78, 92),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.Gotham,
		TextSize = 20,
		Text = text,
		BorderSizePixel = 0,
		LayoutOrder = i,
	}, dialogue)

	opt.MouseButton1Click:Connect(function()
		dialogue.Visible = false
		state.dialogueOpen = false
		task.wait(0.2)
		showShop("gear")
	end)
end

----------------------------------------------------------------------
-- garden: place eggs, wait, hatch
----------------------------------------------------------------------

local garden = new("TextButton", {
	Name = "Garden",
	Position = pos(300, 700),
	Size = size(1320, 330),
	BackgroundColor3 = Color3.fromRGB(78, 112, 68),
	Text = "",
	AutoButtonColor = false,
	BorderSizePixel = 0,
	ZIndex = 2,
}, root)

new("TextLabel", {
	Position = UDim2.fromScale(0, 0),
	Size = size(400, 40),
	BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(215, 235, 205),
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "  Garden",
}, garden)

local eggHotbar = new("Frame", {
	Name = "EggHotbar",
	Position = pos(300, 630),
	Size = size(1320, 56),
	BackgroundTransparency = 1,
	ZIndex = 4,
}, root)

new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, eggHotbar)

local function refreshHotbar()
	for _, child in ipairs(eggHotbar:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	if not state.selectedEgg then
		return
	end
	local btn = new("TextButton", {
		Name = "InventoryEgg",
		Size = UDim2.fromOffset(220, 48),
		BackgroundColor3 = Color3.fromRGB(240, 230, 200),
		TextColor3 = Color3.fromRGB(50, 40, 20),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		Text = state.selectedEgg,
		BorderSizePixel = 0,
	}, eggHotbar)
	btn.MouseButton1Click:Connect(function()
		log("egg selected, click the garden to place it")
		refreshHud()
	end)
end

local function placeEgg(eggName, x, y)
	local plot = new("Frame", {
		Name = "Plot",
		Position = UDim2.fromOffset(x - 80, y - 40),
		Size = UDim2.fromOffset(160, 80),
		BackgroundColor3 = Color3.fromRGB(226, 216, 190),
		BorderSizePixel = 0,
		ZIndex = 6,
	}, garden)

	local label = new("TextLabel", {
		Name = "PlotLabel",
		Size = UDim2.fromScale(1, 0.55),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(50, 45, 30),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Text = eggName,
	}, plot)

	local timer = new("TextLabel", {
		Name = "PlotTimer",
		Position = UDim2.fromScale(0, 0.55),
		Size = UDim2.fromScale(1, 0.45),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(110, 100, 80),
		Font = Enum.Font.Code,
		TextSize = 15,
		Text = "",
	}, plot)

	log("placed " .. eggName)

	task.spawn(function()
		local remaining = CONFIG.hatchSeconds
		while remaining > 0 and plot.Parent do
			timer.Text = string.format("%ds", remaining)
			task.wait(1)
			remaining -= 1
		end
		if not plot.Parent then
			return
		end

		-- The macro's hatch trigger: a template for this exact wording.
		timer.Text = "Ready to Hatch"
		timer.TextColor3 = Color3.fromRGB(20, 120, 20)

		local hatchButton = new("TextButton", {
			Name = "HatchButton",
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromOffset(160, 40),
			BackgroundColor3 = Color3.fromRGB(96, 180, 96),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			Text = "Hatch",
			BorderSizePixel = 0,
			ZIndex = 7,
		}, plot)

		hatchButton.MouseButton1Click:Connect(function()
			local pet = PETS[math.random(1, #PETS)]
			table.insert(state.hatched, pet)
			hatchButton:Destroy()
			label.Text = "Pet: " .. pet
			timer.Text = "hatched"
			timer.TextColor3 = Color3.fromRGB(110, 100, 80)
			plot.BackgroundColor3 = Color3.fromRGB(205, 225, 240)
			log("hatched " .. pet)
			refreshHud()
		end)
	end)

	table.insert(state.plots, plot)
end

garden.MouseButton1Click:Connect(function()
	if not state.selectedEgg then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local absPos = garden.AbsolutePosition
	placeEgg(state.selectedEgg, mouse.X - absPos.X, mouse.Y - absPos.Y)
	state.selectedEgg = nil
	refreshHotbar()
	refreshHud()
end)

----------------------------------------------------------------------
-- top bar + keyboard wiring
----------------------------------------------------------------------

seedsButton.MouseButton1Click:Connect(function()
	-- buySeedShop clicks this, then presses E.
	state.dialogueOpen = false
	state.atGearShop = false
	log("at seed shop, waiting for E")
end)

eggsButton.MouseButton1Click:Connect(function()
	showShop("egg")
end)

gardenButton.MouseButton1Click:Connect(function()
	closeShop()
	log("returned to garden")
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	local key = input.KeyCode

	-- constantsPositions.recallWrenchKeybind defaults to "3".
	if key == Enum.KeyCode.Three then
		state.wrenchEquipped = true
		log("recall wrench equipped")
		refreshHud()

	elseif key == Enum.KeyCode.E then
		if state.wrenchEquipped and state.atGearShop then
			dialogue.Visible = true
			state.dialogueOpen = true
			log("gear vendor dialogue open")
		else
			task.wait(0.2)
			showShop("seed")
		end

	elseif key == Enum.KeyCode.F5 then
		for _, rows in pairs(shopRows) do
			for _, entry in ipairs(rows) do
				entry.reroll()
			end
		end
		state.selectedEgg = nil
		refreshHotbar()
		log("manual restock")
		refreshHud()

	elseif key == Enum.KeyCode.F6 then
		CONFIG.hatchSeconds = (CONFIG.hatchSeconds == 10) and 2 or 10
		log("hatch time now " .. CONFIG.hatchSeconds .. "s")
		refreshHud()

	elseif key == Enum.KeyCode.F7 then
		state.clicksSeen = 0
		state.wastedClicks = 0
		state.bought = {}
		state.hatched = {}
		log("counters reset")
		refreshHud()
	end
end)

-- The recall wrench teleport: with the wrench out, a click outside the shop UI
-- puts the player at the gear shop.
UserInputService.InputEnded:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and state.wrenchEquipped and not state.openShop then
		state.atGearShop = true
		log("teleported to gear shop, waiting for E")
		refreshHud()
	end
end)

----------------------------------------------------------------------
-- restock loop
----------------------------------------------------------------------

task.spawn(function()
	local lastMark = -1
	while true do
		if CONFIG.restockOnClockMark then
			local t = os.date("*t")
			-- Same condition as main.py's isFiveMinMark().
			if t.min % 5 == 0 and t.min ~= lastMark then
				lastMark = t.min
				for _, rows in pairs(shopRows) do
					for _, entry in ipairs(rows) do
						entry.reroll()
					end
				end
				log("shops reset at " .. string.format("%02d:%02d", t.hour, t.min))
				refreshHud()
			end
		end
		task.wait(1)
	end
end)

refreshHotbar()
refreshHud()
log("harness ready")
