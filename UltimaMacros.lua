-- UltimaMacros - Vanilla 1.12.1 (Lua 5.0)
-- Separate macro list stored in SavedVariables with 2056-char per macro cap.
-- Supports per-macro scope: per-character or per-account.
-- SuperMacro-style action mapping: NO reliance on Blizzard macro storage for macro content.
-- We briefly use a proxy macro only to put a valid payload on the cursor during drag.

-- ***********************
-- SavedVariables scaffolding
-- ***********************
if not UltimaMacrosDB then UltimaMacrosDB = {} end
if not UltimaMacrosDB.account then UltimaMacrosDB.account = {} end
if not UltimaMacrosDB.account.macros then UltimaMacrosDB.account.macros = {} end
local UM_GetMappedName
local UM_RefreshActionButtonsForSlot
local UM_MappedSlots = {}
local UM_IconChoicesBuilt = false
local strlen = string.len
local strsub = string.sub
local strfind = string.find
local strlower = string.lower

-- UI scope state (editor checkbox): "char" or "account"
local UM_UI_Scope = "char"
local UM_LocalUI = {}
local UM_hasUnsavedChanges = false
local UM_PendingDelete = nil

local function UM_GetCharKey()
  local name = UnitName("player")
  local realm = GetCVar("realmName") or "Unknown"
  return name .. " - " .. realm
end

local function UM_EnsureTables()
  local ck = UM_GetCharKey()
  if not UltimaMacrosDB.chars then UltimaMacrosDB.chars = {} end
  if not UltimaMacrosDB.chars[ck] then UltimaMacrosDB.chars[ck] = { macros = {}, actions = {} } end
  if not UltimaMacrosDB.chars[ck].macros then UltimaMacrosDB.chars[ck].macros = {} end
  if not UltimaMacrosDB.chars[ck].actions then UltimaMacrosDB.chars[ck].actions = {} end
  if not UltimaMacrosDB.account then UltimaMacrosDB.account = {} end
  if not UltimaMacrosDB.account.macros then UltimaMacrosDB.account.macros = {} end
end

-- ===== Icons =====
local UM_DEFAULT_ICON = "INV_Misc_QuestionMark"
local UM_ICON_CHOICES = {
  "INV_Misc_QuestionMark",
  "INV_Sword_04",
  "Ability_Warrior_Charge",
  "Spell_Nature_Lightning",
  "Spell_Shadow_ShadowBolt",
  "Spell_Holy_SealOfMight",
  "Ability_Marksmanship",
  "INV_Axe_06",
  "INV_Staff_13",
  "INV_Misc_Book_09",
}

local function UM_TexturePath(icon)
  icon = icon or UM_DEFAULT_ICON
  -- accept full texture paths or short tokens
  if string.find(icon, "\\", 1, true) or string.find(icon, "/", 1, true) then
    return icon
  end
  return "Interface\\Icons\\" .. icon
end

-- ***********************
-- Data helpers
-- ***********************
-- Returns: idx, scope ("char"/"account")
local function UM_FindIndexByName(name)
  UM_EnsureTables()
  local ck = UM_GetCharKey()
  local listC = UltimaMacrosDB.chars[ck].macros
  for i=1, table.getn(listC) do
    if listC[i].name == name then
      return i, "char"
    end
  end
  local listA = UltimaMacrosDB.account.macros
  for i=1, table.getn(listA) do
    if listA[i].name == name then
      return i, "account"
    end
  end
  return nil, nil
end

-- Full list for UI: concatenated char then account, sorted alphabetically
-- items are shallow-copied with a ._scope field for display logic
local function UM_List()
  UM_EnsureTables()
  local out = {}
  local ck = UM_GetCharKey()

  local listC = UltimaMacrosDB.chars[ck].macros
  for i=1, table.getn(listC) do
    local m = listC[i]
    tinsert(out, { name = m.name, text = m.text, icon = m.icon, _scope = "char" })
  end

  local listA = UltimaMacrosDB.account.macros
  for i=1, table.getn(listA) do
    local m = listA[i]
    tinsert(out, { name = m.name, text = m.text, icon = m.icon, _scope = "account" })
  end

  table.sort(out, function(a, b)
    local na, nb = string.lower(a.name or ""), string.lower(b.name or "")
    if na ~= nb then return na < nb end
    if a._scope ~= b._scope then return a._scope == "char" end
    return (a.name or "") < (b.name or "")
  end)

  return out
end

local function UM_RefreshAllSlotsForName(name)
  if not name or name == "" then return end

  if CleveRoids and CleveRoids.Frame and CleveRoids.Frame.UPDATE_MACROS then
    pcall(CleveRoids.Frame.UPDATE_MACROS, CleveRoids.Frame)
    if CleveRoids.QueueActionUpdate then pcall(CleveRoids.QueueActionUpdate) end
  end

  for slot in pairs(UM_MappedSlots) do
    if UM_GetMappedName(slot) == name then
      if CleveRoids and CleveRoids.Frame and CleveRoids.Frame.ACTIONBAR_SLOT_CHANGED then
        pcall(CleveRoids.Frame.ACTIONBAR_SLOT_CHANGED, CleveRoids.Frame, slot)
      end
      UM_RefreshActionButtonsForSlot(slot)
    end
  end
end

local function UM_New(name, scope)
  if not name or name == "" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros: name required.|r")
    return
  end
  scope = (scope == "account") and "account" or "char"
  UM_EnsureTables()
  local idx, existingScope = UM_FindIndexByName(name)
  if idx then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros: macro exists ("..existingScope..").|r")
    return
  end
  if scope == "char" then
    local ck = UM_GetCharKey()
    tinsert(UltimaMacrosDB.chars[ck].macros, { name = name, text = "", icon = UM_DEFAULT_ICON })
  else
    tinsert(UltimaMacrosDB.account.macros, { name = name, text = "", icon = UM_DEFAULT_ICON })
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55UltimaMacros: created '"..name.."' ["..scope.."]|r")
  UM_UI_RefreshList()

  -- NEW: make newly-created macros immediately resolve #showtooltip on buttons using that name
  UM_RefreshAllSlotsForName(name)
end

local function UM_Delete(name)
  local idx, scope = UM_FindIndexByName(name)
  if not idx then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros: not found.|r")
    return
  end
  if scope == "char" then
    local ck = UM_GetCharKey()
    tremove(UltimaMacrosDB.chars[ck].macros, idx)
  else
    tremove(UltimaMacrosDB.account.macros, idx)
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55UltimaMacros: deleted '"..name.."' ["..scope.."]|r")
  UM_UI_ClearEditor()
  UM_UI_RefreshList()

  -- NEW: clear any buttons mapped to this name (icon/tooltip won’t be stale)
  UM_RefreshAllSlotsForName(name)
end

-- Save, optionally to a specific scope; if scope is nil, uses UM_UI_Scope from the editor
local function UM_Save(name, text, scope)
  if not name or name == "" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros: name required.|r")
    return
  end
  if not text then text = "" end
  if string.len(text) > 2056 then
    text = string.sub(text, 1, 2056)
  end

  UM_EnsureTables()
  local curIdx, curScope = UM_FindIndexByName(name)
  local targetScope = scope or UM_UI_Scope or "char"

  if curIdx and curScope ~= targetScope then
    local entry
    if curScope == "char" then
      local ck = UM_GetCharKey()
      entry = UltimaMacrosDB.chars[ck].macros[curIdx]
      tremove(UltimaMacrosDB.chars[ck].macros, curIdx)
    else
      entry = UltimaMacrosDB.account.macros[curIdx]
      tremove(UltimaMacrosDB.account.macros, curIdx)
    end
    entry.text = text
    if targetScope == "char" then
      local ck = UM_GetCharKey()
      tinsert(UltimaMacrosDB.chars[ck].macros, entry)
    else
      tinsert(UltimaMacrosDB.account.macros, entry)
    end
  else
    if not curIdx then
      -- create new in target scope
      if targetScope == "char" then
        local ck = UM_GetCharKey()
        tinsert(UltimaMacrosDB.chars[ck].macros, { name = name, text = text, icon = UM_DEFAULT_ICON })
      else
        tinsert(UltimaMacrosDB.account.macros, { name = name, text = text, icon = UM_DEFAULT_ICON })
      end
    else
      -- update existing
      if curScope == "char" then
        local ck = UM_GetCharKey()
        UltimaMacrosDB.chars[ck].macros[curIdx].text = text
      else
        UltimaMacrosDB.account.macros[curIdx].text = text
      end
    end
  end

  DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55UltimaMacros: saved '"..name.."' ["..targetScope.."]|r")
  UM_UI_RefreshList()

  -- NEW: force immediate re-index/refresh so #showtooltip icons update without /reload
  UM_RefreshAllSlotsForName(name)
end

local function UM_Get(name)
  local idx, scope = UM_FindIndexByName(name)
  if not idx then return nil end
  if scope == "char" then
    local ck = UM_GetCharKey()
    return UltimaMacrosDB.chars[ck].macros[idx], scope
  else
    return UltimaMacrosDB.account.macros[idx], scope
  end
end

-- ***********************
-- Execution (Vanilla-safe)
-- ***********************

local function UM_Trim(s)
  if not s then return "" end
  local i, j = 1, string.len(s)
  while i <= j and string.sub(s, i, i) <= " " do i = i + 1 end
  while j >= i and string.sub(s, j, j) <= " " do j = j - 1 end
  return string.sub(s, i, j)
end

local function UM_SendSlash(line)
  local eb = (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or ChatFrameEditBox
  if not eb then return end
  eb:SetText(line)
  ChatEdit_SendText(eb)
end

local function UM_RunLine(line)
  line = UM_Trim(line or "")
  if line == "" then return end

  local lower7 = string.lower(string.sub(line, 1, 7))
  if string.sub(lower7,1,7) == "/script" then
    local code = string.sub(line, 8)
    if code and code ~= "" then
      -- ADDED: pcall protection
      local success, err = pcall(RunScript, code)
      if not success then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros script error: "..tostring(err).."|r")
      end
    end
    return
  end

  local lower4 = string.lower(string.sub(line, 1, 4))
  if lower4 == "/run" then
    local code2 = string.sub(line, 5)
    if code2 and code2 ~= "" then
      -- ADDED: pcall protection
      local success, err = pcall(RunScript, code2)
      if not success then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros script error: "..tostring(err).."|r")
      end
    end
    return
  end

  UM_SendSlash(line)
end

local function UM_ForEachLine(text, fn)
  local pos = 1
  while true do
    local s, e = string.find(text, "\n", pos, 1)
    if s then
      fn(string.sub(text, pos, s-1))
      pos = e + 1
    else
      fn(string.sub(text, pos))
      break
    end
  end
end

local function UM_Run(name)
  local m = UM_Get(name)
  if not m then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros: '"..(name or "?").."' not found.|r")
    return
  end
  UM_ForEachLine((m.text or ""), UM_RunLine)
end

-- ============================================================
-- SuperMacro-style cursor helpers and action mapping
-- ============================================================
local UM_CURSOR = nil
local UM_HooksInstalled = false

local function UM_GetActionMap()
  UM_EnsureTables()
  return UltimaMacrosDB.chars[UM_GetCharKey()].actions
end

UM_GetMappedName = function(slot)
  local t = UM_GetActionMap()
  return t and t[slot] or nil
end

local function UM_SetAction(slot, name)
  UM_GetActionMap()[slot] = name
  UM_MappedSlots[slot] = true
end


local function UM_ClearAction(slot)
  UM_GetActionMap()[slot] = nil
  UM_MappedSlots[slot] = nil
end

local function UM_GetIconFor(name)
  local rec = UM_Get(name)
  local icon = rec and rec.icon or UM_DEFAULT_ICON
  return UM_TexturePath(icon)
end

-- === UI refresh helpers for mapped slots ===
local function UM_ButtonMatchesSlot(btn, slot)
  if not btn then return false end
  if ActionButton_GetPagedID then
    local id = ActionButton_GetPagedID(btn)
    if id then return id == slot end
  end
  return (btn.action == slot)
end

UM_RefreshActionButtonsForSlot = function(slot)
  local function touch(btnName)
    local btn = getglobal(btnName)
    if btn and UM_ButtonMatchesSlot(btn, slot) then
      local name = UM_GetMappedName(slot)
      local iconTex = GetActionTexture and GetActionTexture(slot)
      if not iconTex and name then
        iconTex = UM_GetIconFor(name)
      end

      local icon = getglobal(btnName.."Icon")
      if icon then icon:SetTexture(iconTex) end

      local label = getglobal(btnName.."Name")
      if label then label:SetText(name or "") end

      if ActionButton_Update then
        local oldThis = this
        this = btn
        pcall(ActionButton_Update)
        this = oldThis
      end
    end
  end

  for i=1,12 do touch("ActionButton"..i) end
  for i=1,12 do touch("BonusActionButton"..i) end

  -- FIXED: explicit iteration instead of table.getn(bars)
  local bars = { "MultiBarRight", "MultiBarLeft", "MultiBarBottomLeft", "MultiBarBottomRight" }
  for bi=1, 4 do  -- Changed from: for bi=1, table.getn(bars) do
    local bar = bars[bi]
    for i=1,12 do touch(bar.."Button"..i) end
  end

  if ActionBar_UpdateUsable then ActionBar_UpdateUsable() end
  if ActionBar_UpdateCooldowns then ActionBar_UpdateCooldowns() end
  if ActionBar_UpdateState then ActionBar_UpdateState() end
end

-- At module level, check what's available
local UM_oldPickupMacro, UM_oldEditMacro, UM_oldGetMacroInfo, UM_oldCreateMacro
local UM_oldActionButton_OnClick, UM_oldActionButton_OnReceiveDrag
local UM_oldGetActionInfo = GetActionInfo  -- Will be nil in vanilla
local UM_oldGetMacroIndexByName = GetMacroIndexByName
local UM_proxyMacroIndex = nil

-- Helper to check if slot has a real action (vanilla-compatible)
local function UM_SlotHasRealAction(slot)
  -- If GetActionInfo exists (TBC+), use it
  if UM_oldGetActionInfo then
    local actionType, actionID = UM_oldGetActionInfo(slot)
    return (actionType and actionType ~= "")
  end

  -- Vanilla fallback: check if HasAction returns true and it's NOT our mapping
  if HasAction and HasAction(slot) then
    -- If we have a mapping for this slot, it's not a "real" action
    if UM_GetMappedName(slot) then
      return false
    end
    return true
  end

  return false
end

-- ----- Robust proxy macro pickup (handles multiple CreateMacro signatures) -----
-- Some Vanilla cores want: CreateMacro(name, iconIndex, body, local, perCharacter)
-- Others accept 4 args, and some accept a texture string. We try several safely.

local function UM_SafeCreateMacro(name, iconIndexOrTexture, body)
  if not UM_oldCreateMacro then return nil end

  -- Try multiple signature/arg variants safely with pcall (no hard error)
  local variants = {
    -- 5-arg (preferred on Vanilla): local=nil, perCharacter=1
    {name, iconIndexOrTexture, body, nil, 1},
    -- 5-arg inverted (some cores flipped semantics)
    {name, iconIndexOrTexture, body, 1, nil},
    -- 4-arg (TBC+ style on some clients)
    {name, iconIndexOrTexture, body, 1},
    {name, iconIndexOrTexture, body, nil},
  }

  for v = 1, table.getn(variants) do
    local args = variants[v]
    local ok, idx = pcall(UM_oldCreateMacro, args[1], args[2], args[3], args[4], args[5])
    if ok and type(idx) == "number" then
      return idx
    end
  end

  return nil
end

local UM_proxyMacroIndex = nil

local function UM_GetOrCreateProxyMacroIndex()
  -- If we have a cached index and it's still valid, use it
  if UM_proxyMacroIndex and UM_oldGetMacroInfo and UM_oldGetMacroInfo(UM_proxyMacroIndex) then
    return UM_proxyMacroIndex
  end

  -- If any macro exists at all, just reuse index 1 as a pickup payload
  if UM_oldGetMacroInfo and UM_oldGetMacroInfo(1) then
    UM_proxyMacroIndex = 1
    return 1
  end

  -- Try creating a throwaway proxy macro, trying multiple icon arg types and signatures
  -- Most Vanilla cores want a NUMERIC icon index. We'll try 1 first.
  local tryIcons = {
    1,                                -- numeric index (safest on 1.12)
    "INV_Misc_QuestionMark",          -- icon token (some cores accept this)
    UM_TexturePath(UM_DEFAULT_ICON),  -- full texture path (rarely accepted on 1.12)
  }

  for i = 1, table.getn(tryIcons) do
    local idx = UM_SafeCreateMacro("UMProxy", tryIcons[i], " ")
    if idx then
      UM_proxyMacroIndex = idx
      return idx
    end
  end

  -- Could not create a macro (storage full or API signature mismatch)
  return nil
end

local function UM_PickupUsingMacroProxy()
  if not UM_oldPickupMacro or not UM_oldEditMacro then return false end

  -- Try to reuse any existing macro at slot 1 without creating new ones
  if UM_oldGetMacroInfo and UM_oldGetMacroInfo(1) then
    local ok = pcall(UM_oldPickupMacro, 1)
    return ok and true or false
  end

  -- Only create if absolutely necessary, and clean up immediately
  local idx = UM_SafeCreateMacro("UMProxy", 1, " ")
  if not idx then return false end

  local ok = pcall(UM_oldPickupMacro, idx)

  -- Clean up the proxy macro immediately after pickup
  if DeleteMacro and idx then
    pcall(DeleteMacro, idx)
  end

  return ok and true or false
end

local function UM_PickupProxyForDrag_Fallback()
  ClearCursor()
  for tab = 1, GetNumSpellTabs() do
    local _, _, offset, num = GetSpellTabInfo(tab)
    if num then
      for i = 1, num do
        local id = offset + i
        local nm = GetSpellName(id, BOOKTYPE_SPELL)
        if nm then
          PickupSpell(id, BOOKTYPE_SPELL)
          return true
        end
      end
    end
  end
  for bag = 0, 4 do
    local slots = GetContainerNumSlots and GetContainerNumSlots(bag)
    if slots then
      for slot = 1, slots do
        local tx = GetContainerItemInfo(bag, slot)
        if tx then
          PickupContainerItem(bag, slot)
          return true
        end
      end
    end
  end
  return false
end

local function UM_StartDrag(name)
  if not name or name == "" or not UM_Get(name) then return end
  UM_CURSOR = name
  ClearCursor()
  if UM_PickupUsingMacroProxy() then return end
  if UM_PickupProxyForDrag_Fallback() then return end
  UM_CURSOR = nil
  DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros: couldn't start drag (no valid pickup payload).|r")
end

local function UM_EndDrag()
  -- Intentionally NOT clearing UM_CURSOR here; the action button needs it.
  -- You can cancel a stuck cursor with right-click (Blizzard default).
end

-- ============================================================
-- SuperCleveroidMacros / SuperMacro compatibility (tooltips)
-- Make UM macros resolvable by name via GetMacroIndexByName+GetMacroInfo
-- so #showtooltip and SCM’s parser work.
-- ============================================================

-- Two “virtual id” spaces:
--  - SLOT space: map action slot -> virtual macro id (kept for completeness)
--  - NAME space: map macro name -> virtual macro id (required for SCM)
local UM_SCM_SLOT_BASE = 50000
local UM_SCM_NAME_BASE = 60000

local UM_SCM_compat_enabled = false
local UM_oldGetActionInfo, UM_oldGetMacroInfo, UM_oldGetMacroIndexByName

-- name<->index tables for virtual NAME space
local UM_fakeName2Index, UM_fakeIndex2Name = {}, {}
local UM_nextNameIndex = UM_SCM_NAME_BASE

local function UM_AssignNameIndex(name)
  local idx = UM_fakeName2Index[name]
  if idx then return idx end
  UM_nextNameIndex = UM_nextNameIndex + 1
  idx = UM_nextNameIndex
  UM_fakeName2Index[name] = idx
  UM_fakeIndex2Name[idx] = name
  return idx
end

-- Utility: resolve a virtual index (slot-space or name-space) to macro name
local function UM_NameFromVirtualIndex(index)
  if type(index) ~= "number" then return nil end
  -- SLOT virtuals
  if index >= UM_SCM_SLOT_BASE and index < UM_SCM_SLOT_BASE + 300 then
    local slot = index - UM_SCM_SLOT_BASE
    return UM_GetMappedName and UM_GetMappedName(slot)
  end
  -- NAME virtuals
  if index > UM_SCM_NAME_BASE then
    return UM_fakeIndex2Name[index]
  end
end

-- Detect SCM/SuperMacro presence (broad but safe)
local function UM_IsSCMLoaded()
  if type(IsAddOnLoaded) == "function" then
    if IsAddOnLoaded("SuperCleveroidMacros") or IsAddOnLoaded("SuperCleveroid")
       or IsAddOnLoaded("SuperMacro") then
      return true
    end
  end
  -- heuristics
  if _G.CleveRoids or _G.SC_Options or _G.SC_Tooltip or _G.SuperMacroFrame then
    return true
  end
  return false
end

local function UM_EnableSCMCompat()
  if UM_SCM_compat_enabled then return end
  UM_SCM_compat_enabled = true

  if not UM_oldGetMacroInfo then
    UM_oldGetMacroInfo = GetMacroInfo
  end

  -- Only hook GetActionInfo if it exists (TBC+)
  if GetActionInfo then
    if not UM_oldGetActionInfo then
      UM_oldGetActionInfo = GetActionInfo
    end

    GetActionInfo = function(slot)
      local realType, realID = UM_oldGetActionInfo(slot)
      if realType and realType ~= "" then
        return realType, realID, nil
      end

      local name = UM_GetMappedName and UM_GetMappedName(slot)
      if name then
        return "macro", (UM_SCM_SLOT_BASE + slot), nil
      end

      return nil
    end
  end

  -- Only hook GetMacroIndexByName if it exists
  if GetMacroIndexByName then
    if not UM_oldGetMacroIndexByName then
      UM_oldGetMacroIndexByName = GetMacroIndexByName
    end

    GetMacroIndexByName = function(name)
      if name and UM_FindIndexByName then
        local idx = UM_FindIndexByName(name)
        if idx then
          return UM_AssignNameIndex(name)
        end
      end
      return UM_oldGetMacroIndexByName(name)
    end
  end

  GetMacroInfo = function(index)
    local vname = UM_NameFromVirtualIndex(index)
    if vname then
      local rec = UM_Get and UM_Get(vname)
      if not rec then return nil end
      local iconTex = UM_GetIconFor and UM_GetIconFor(vname) or "Interface\\Icons\\INV_Misc_QuestionMark"
      local body = (rec and rec.text) or ""
      return vname, iconTex, body
    end
    local name, tex, body = UM_oldGetMacroInfo(index)
    if not name then return nil end
    return name, tex, body
  end
end

-- At initialization, create a single persistent proxy
local function UM_EnsureProxyMacro()
  if UM_proxyMacroIndex and UM_oldGetMacroInfo and UM_oldGetMacroInfo(UM_proxyMacroIndex) then
    return UM_proxyMacroIndex
  end

  -- Look for existing UMProxy
  if UM_oldGetMacroIndexByName then
    local idx = UM_oldGetMacroIndexByName("UMProxy")
    if idx then
      UM_proxyMacroIndex = idx
      return idx
    end
  end

  -- Create permanent proxy
  local idx = UM_SafeCreateMacro("UMProxy", 1, "#showtooltip")
  if idx then
    UM_proxyMacroIndex = idx
  end
  return idx
end

-- ----- Hooks: map your macro to action bar, render icon/name, run on press -----
local function UM_InstallHooks()
  if UM_HooksInstalled then return end
  UM_HooksInstalled = true

  UM_oldPickupMacro = PickupMacro
  UM_oldEditMacro = EditMacro
  UM_oldGetMacroInfo = GetMacroInfo
  UM_oldCreateMacro = CreateMacro

  local UM_oldPlaceAction = PlaceAction
  local UM_oldUseAction = UseAction
  local UM_oldPickupAction = PickupAction
  local UM_oldGetActionText = GetActionText
  local UM_oldGetActionTex = GetActionTexture
  local UM_oldHasAction = HasAction
  -- DON'T save UM_oldGetActionInfo here - it's already saved in SCM compat
  UM_oldActionButton_OnClick = ActionButton_OnClick
  UM_oldActionButton_OnReceiveDrag = ActionButton_OnReceiveDrag

  PlaceAction = function(slot)
    if UM_CURSOR then
      local macroName = UM_CURSOR
      UM_CURSOR = nil
      ClearCursor()

      -- Check if there's a REAL action here
      if UM_SlotHasRealAction(slot) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros: Slot " .. slot .. " is occupied!|r")
        return
      end

      UM_SetAction(slot, macroName)
      UM_RefreshActionButtonsForSlot(slot)
      return
    end
    return UM_oldPlaceAction(slot)
  end

  UseAction = function(slot, checkCursor, onSelf)
    local name = UM_GetMappedName(slot)
    if name then
      UM_Run(name)
      return
    end
    return UM_oldUseAction(slot, checkCursor, onSelf)
  end

  PickupAction = function(slot)
    local name = UM_GetMappedName(slot)
    if name then
      UM_CURSOR = name
      UM_ClearAction(slot)
      UM_RefreshActionButtonsForSlot(slot)
      if UM_PickupUsingMacroProxy and UM_PickupUsingMacroProxy() then
        return
      end
      UM_PickupProxyForDrag_Fallback()
      return
    end
    return UM_oldPickupAction(slot)
  end

  GetActionText = function(slot)
    local name = UM_GetMappedName(slot)
    if name then return name end
    return UM_oldGetActionText(slot)
  end

  GetActionTexture = function(slot)
    local name = UM_GetMappedName(slot)
    if name then
      local tex = UM_oldGetActionTex and UM_oldGetActionTex(slot)
      if tex then return tex end
      return UM_GetIconFor(name)
    end
    return UM_oldGetActionTex and UM_oldGetActionTex(slot) or nil
  end

  -- Check real actions FIRST before claiming slots
  GetActionInfo = function(slot)
    local realType, realID = UM_oldGetActionInfo(slot)
    if realType and realType ~= "" then
      return realType, realID, nil
    end

    local name = UM_GetMappedName and UM_GetMappedName(slot)
    if name then
      return "macro", (UM_SCM_SLOT_BASE + slot), nil
    end
    return nil
  end

  HasAction = function(slot)
    local name = UM_GetMappedName(slot)
    if name then return 1 end
    return UM_oldHasAction(slot)
  end

  ActionButton_OnClick = function(button)
    if UM_CURSOR then
      local btn = this or button
      local id = (ActionButton_GetPagedID and btn and ActionButton_GetPagedID(btn)) or (btn and btn.action)
      if id then
        PlaceAction(id)
        return
      end
    end
    if UM_oldActionButton_OnClick then
      return UM_oldActionButton_OnClick(button)
    end
  end

  ActionButton_OnReceiveDrag = function()
    if UM_CURSOR then
      local btn = this
      local id = (ActionButton_GetPagedID and btn and ActionButton_GetPagedID(btn)) or (btn and btn.action)
      if id then
        PlaceAction(id)
        return
      end
    end
    if UM_oldActionButton_OnReceiveDrag then
      return UM_oldActionButton_OnReceiveDrag()
    end
  end
end

-- ***********************
-- Slash commands
-- ***********************
SLASH_ULTIMAMACROS1 = "/umacro"
SLASH_ULTIMAMACROS2 = "/umacros"
SlashCmdList["ULTIMAMACROS"] = function(msg)
  local cmd = UM_Trim(msg or "")
  if cmd == "" or cmd == "help" then
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffUltimaMacros usage:|r")
    DEFAULT_CHAT_FRAME:AddMessage("/umacro frame  - open/close the editor")
    DEFAULT_CHAT_FRAME:AddMessage("/umacro new <name>       - new per-character macro")
    DEFAULT_CHAT_FRAME:AddMessage("/umacro newa <name>      - new per-account macro")
    DEFAULT_CHAT_FRAME:AddMessage("/umacro del <name>")
    DEFAULT_CHAT_FRAME:AddMessage("/umacro run <name>")
    DEFAULT_CHAT_FRAME:AddMessage("/umacro list")
    return
  end

  local space = string.find(cmd, " ", 1, 1)
  local sub, arg
  if space then
    sub = string.sub(cmd, 1, space - 1)
    arg = string.sub(cmd, space + 1)
  else
    sub, arg = cmd, ""
  end
  sub = string.lower(sub)
  arg = UM_Trim(arg)

  if sub == "frame" then
    UM_ToggleFrame()
  elseif sub == "new" then
    UM_New(arg, "char")
  elseif sub == "newa" then
    UM_New(arg, "account")
  elseif sub == "del" or sub == "delete" then
    UM_Delete(arg)
  elseif sub == "run" then
    UM_Run(arg)
  elseif sub == "list" then
    local list = UM_List()
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffUltimaMacros: "..table.getn(list).." macros (char+account)|r")
    for i=1, table.getn(list) do
      local tag = (list[i]._scope == "account") and "[A]" or "[C]"
      DEFAULT_CHAT_FRAME:AddMessage(" - "..tag.." "..list[i].name.." ("..string.len(list[i].text or "").."/2056)")
    end
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Unknown subcommand. Try /umacro help|r")
  end
end

-- ***********************
-- UI helpers / glue
-- ***********************
local function UM_UI_FixButtonLabels()
  if UltimaMacrosNewCharButton then
    UltimaMacrosNewCharButton:SetText("New")
  end
  if UltimaMacrosSaveButton then
    UltimaMacrosSaveButton:SetText("Save")
  end
  if UltimaMacrosRunButton then
    UltimaMacrosRunButton:SetText("Run")
  end
  if UltimaMacrosDeleteButton then
    UltimaMacrosDeleteButton:SetText("Delete")
  end
end

function UM_UI_RefreshList()
  if not UltimaMacrosListScroll or not UltimaMacrosListContent then return end
  local list = UM_List()

  local idx = 1
  while true do
    local old = getglobal("UltimaMacrosListButton"..idx)
    if not old then break end
    old:Hide()
    idx = idx + 1
  end

  local offsetY = -4
  for i = 1, table.getn(list) do
    local btn = getglobal("UltimaMacrosListButton"..i)
    if not btn then
      btn = CreateFrame("Button", "UltimaMacrosListButton"..i, UltimaMacrosListContent, "UIPanelButtonTemplate")
      btn:SetWidth(150)
      btn:SetHeight(20)
    else
      if btn:GetParent() ~= UltimaMacrosListContent then
        btn:SetParent(UltimaMacrosListContent)
      end
    end

    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", UltimaMacrosListContent, "TOPLEFT", 4, offsetY)

    local name = list[i].name
    local tag  = (list[i]._scope == "account") and "[A] " or "[C] "
    btn:SetText(tag .. name)

    btn:SetScript("OnClick", function()
      UM_UI_LoadIntoEditor(name)
    end)

    btn:SetScript("OnDoubleClick", function()
      UM_UI_LoadIntoEditor(name)
      if UltimaMacrosFrameEditBox then
        UltimaMacrosFrameEditBox:SetFocus()
      end
    end)

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function() UM_StartDrag(name) end)

    btn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText(name)
      local scopeText = (list[i]._scope == "account") and "Account-wide" or "Character"
      GameTooltip:AddLine("Scope: " .. scopeText, 0.7, 0.7, 0.7)
      local charCount = string.len(list[i].text or "")
      GameTooltip:AddLine(charCount .. "/2056 characters", 0.5, 0.5, 0.5)
      GameTooltip:AddLine(" ", 1, 1, 1)
      GameTooltip:AddLine("Double-click to edit", 0.3, 1, 0.3, true)
      GameTooltip:AddLine("Drag to action bar", 0.3, 1, 0.3, true)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:Show()
    offsetY = offsetY - 22
  end

  -- Update content height based on number of items
  local contentHeight = math.max(360, -offsetY + 4)
  UltimaMacrosListContent:SetHeight(contentHeight)

  -- Force scroll frame to update its scroll range
  UltimaMacrosListScroll:UpdateScrollChildRect()

  -- Reset scroll position if we're scrolled past the new content
  local maxScroll = math.max(0, contentHeight - UltimaMacrosListScroll:GetHeight())
  local currentScroll = UltimaMacrosListScroll:GetVerticalScroll()
  if currentScroll > maxScroll then
    UltimaMacrosListScroll:SetVerticalScroll(maxScroll)
  end

  UM_UI_FixButtonLabels()
end

function UM_UI_LoadIntoEditor(name)
  local m, scope = UM_Get(name)
  if not m then return end

  UltimaMacrosFrameNameEdit:SetText(m.name or "")
  UltimaMacrosFrameEditBox:SetText(m.text or "")
  UM_UI_Scope = scope or "char"

  -- Update scope display
  if UltimaMacrosScopeCheck then
    UltimaMacrosScopeCheck:SetChecked(UM_UI_Scope == "char")
    if UM_UI_Scope == "char" then
      UltimaMacrosScopeCheckText:SetText("Per Character (uncheck for Account-wide)")
    else
      UltimaMacrosScopeCheckText:SetText("Account-wide (check for Per Character)")
    end
  end

  if UM_LocalUI.scopeIndicator then
    if UM_UI_Scope == "char" then
      UM_LocalUI.scopeIndicator:SetText("[Char]")
      UM_LocalUI.scopeIndicator:SetTextColor(0.3, 0.8, 1.0)
    else
      UM_LocalUI.scopeIndicator:SetText("[Account]")
      UM_LocalUI.scopeIndicator:SetTextColor(1.0, 0.8, 0.3)
    end
  end

  if UltimaMacrosIconButton then
    local icon = (m.icon and m.icon ~= "") and m.icon or UM_DEFAULT_ICON
    UltimaMacrosIconButton:SetNormalTexture(UM_TexturePath(icon))
    local found = 1
    for i=1, table.getn(UM_ICON_CHOICES) do
      if UM_TexturePath(UM_ICON_CHOICES[i]) == UM_TexturePath(icon) then found = i; break end
    end
    UltimaMacrosIconButton._idx = found
  end

  UM_hasUnsavedChanges = false
  if UM_LocalUI.counter then
    UM_LocalUI.counter:SetTextColor(1, 1, 1)
  end
  UM_UI_UpdateCounter()

  if UltimaMacrosEditScroll and UltimaMacrosEditScroll.UpdateScrollChildRect then
    UltimaMacrosEditScroll:UpdateScrollChildRect()
  end
  -- Reset scroll to top when loading a new macro
  if UltimaMacrosEditScroll then
    UltimaMacrosEditScroll:SetVerticalScroll(0)
  end
end

function UM_UI_ClearEditor()
  UltimaMacrosFrameNameEdit:SetText("")
  UltimaMacrosFrameEditBox:SetText("")
  UM_UI_Scope = "char"
  if UltimaMacrosScopeCheck then
    UltimaMacrosScopeCheck:SetChecked(true)
    UltimaMacrosScopeCheckText:SetText("Per Character")
  end
  if UltimaMacrosIconButton then
    UltimaMacrosIconButton:SetNormalTexture(UM_TexturePath(UM_DEFAULT_ICON))
    UltimaMacrosIconButton._idx = 1
  end
  UM_UI_UpdateCounter()
end

function UM_UI_Save()
  local name = UltimaMacrosFrameNameEdit:GetText() or ""
  local text = UltimaMacrosFrameEditBox:GetText() or ""
  if string.len(text) > 2056 then
    text = string.sub(text, 1, 2056)
    UltimaMacrosFrameEditBox:SetText(text)
  end
  UM_Save(name, text, UM_UI_Scope)
  UM_UI_RefreshList()

  -- Clear unsaved changes flag
  UM_hasUnsavedChanges = false
  if UM_LocalUI.counter then
    UM_LocalUI.counter:SetTextColor(1, 1, 1) -- White when clean
  end
end

function UM_UI_Run()
  local name = UltimaMacrosFrameNameEdit:GetText() or ""
  if name == "" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros: enter a name to run.|r")
    return
  end
  UM_Run(name)
end

function UM_UI_NewChar()
  local base = "New Macro"
  local candidate = base
  local n = 1
  while UM_FindIndexByName(candidate) do
    n = n + 1
    candidate = base .. " " .. n
  end
  UM_New(candidate, "char")
  UM_UI_LoadIntoEditor(candidate)
end

function UM_UI_NewAccount()
  local base = "New Macro"
  local candidate = base
  local n = 1
  while UM_FindIndexByName(candidate) do
    n = n + 1
    candidate = base .. " " .. n
  end
  UM_New(candidate, "account")
  UM_UI_LoadIntoEditor(candidate)
  UM_UI_SetScopeAccount(true)
end

function UM_UI_Delete()
  local name = UltimaMacrosFrameNameEdit:GetText() or ""
  if name == "" then return end

  UM_PendingDelete = name

  -- Create confirmation dialog
  if not StaticPopupDialogs["ULTIMAMACROS_DELETE_CONFIRM"] then
    StaticPopupDialogs["ULTIMAMACROS_DELETE_CONFIRM"] = {
      text = "Delete macro '%s'?",
      button1 = "Delete",
      button2 = "Cancel",
      OnAccept = function()
        if UM_PendingDelete then
          UM_Delete(UM_PendingDelete)
          UM_PendingDelete = nil
        end
      end,
      OnCancel = function()
        UM_PendingDelete = nil
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
    }
  end

  StaticPopup_Show("ULTIMAMACROS_DELETE_CONFIRM", name)
end

function UM_UI_OnTextChanged()
  UM_UI_UpdateCounter()
end

function UM_UI_UpdateCounter()
  if not UltimaMacrosFrameEditBox or not UltimaMacrosFrameCounter then
    return
  end
  local text = UltimaMacrosFrameEditBox:GetText() or ""
  local used = string.len(text)
  if used > 2056 then
    text = string.sub(text, 1, 2056)
    UltimaMacrosFrameEditBox:SetText(text)
    used = 2056
  end
  UltimaMacrosFrameCounter:SetText(used .. "/2056")
end

function UM_UI_ToggleScope()
  local checked = UltimaMacrosScopeCheck:GetChecked()
  if checked then
    UM_UI_Scope = "char"
    UltimaMacrosScopeCheckText:SetText("Per Character (uncheck for Account-wide)")
    if UM_LocalUI.scopeIndicator then
      UM_LocalUI.scopeIndicator:SetText("[Char]")
      UM_LocalUI.scopeIndicator:SetTextColor(0.3, 0.8, 1.0)
    end
  else
    UM_UI_Scope = "account"
    UltimaMacrosScopeCheckText:SetText("Account-wide (check for Per Character)")
    if UM_LocalUI.scopeIndicator then
      UM_LocalUI.scopeIndicator:SetText("[Account]")
      UM_LocalUI.scopeIndicator:SetTextColor(1.0, 0.8, 0.3)
    end
  end
end

function UM_UI_SetScopeAccount()
  UM_UI_Scope = "account"
  UltimaMacrosScopeCheck:SetChecked(false)
  UltimaMacrosScopeCheckText:SetText("Per Account")
end
function UM_UI_SetScopeChar()
  UM_UI_Scope = "char"
  UltimaMacrosScopeCheck:SetChecked(true)
  UltimaMacrosScopeCheckText:SetText("Per Character")
end

local function UM_IconBasename(tex)
  if not tex or tex == "" then return "" end
  -- OPTIMIZED: use gsub instead of multiple find/sub calls
  local s = string.gsub(tex, "^.*\\Icons\\", "")
  s = string.gsub(s, "\\.*", "")
  s = string.gsub(s, "%..*", "")
  return string.lower(s or "")
end

-- Rebuild the icon list by scanning spells, items, and macros.
local function UM_RebuildIconChoices()
  if UM_IconChoicesBuilt then return end
  local seen, out = {}, {}

  local function add(tex)
    if not tex or tex == "" then return end
    if not string.find(tex, "\\", 1, true) then
      tex = "Interface\\Icons\\" .. tex
    end
    if not seen[tex] then
      seen[tex] = true
      table.insert(out, tex)
    end
  end

  -- 1) Spellbook icons
  if type(GetNumSpellTabs) == "function" and type(GetSpellTabInfo) == "function" then
    local numTabs = GetNumSpellTabs()
    for t = 1, (numTabs or 0) do
      local _, _, offset, numSpells = GetSpellTabInfo(t)
      local first = (offset or 0) + 1
      local last  = (offset or 0) + (numSpells or 0)
      if type(GetSpellTexture) == "function" then
        for i = first, last do add(GetSpellTexture(i, BOOKTYPE_SPELL)) end
      end
    end
  end

  -- 2) Equipped items
  if type(GetInventoryItemTexture) == "function" then
    for slot = 0, 23 do add(GetInventoryItemTexture("player", slot)) end
  end

  -- 3) Bag items
  if type(GetContainerNumSlots) == "function" and type(GetContainerItemInfo) == "function" then
    for bag = 0, 4 do
      local slots = GetContainerNumSlots(bag)
      for slot = 1, (slots or 0) do
        local tex = GetContainerItemInfo(bag, slot)
        add(tex)
      end
    end
  end

  -- 4) Existing Blizzard macros
  if type(GetNumMacros) == "function" and type(GetMacroInfo) == "function" then
    local numGlobal, numChar = GetNumMacros()
    for i = 1, (numGlobal or 0) do local _, tex = GetMacroInfo(i); add(tex) end
    for i = 37, 36 + (numChar or 0) do local _, tex = GetMacroInfo(i); add(tex) end
  end

  -- 5) Icons used by UM macros
  if type(UM_List) == "function" then
    local list = UM_List()
    for i = 1, table.getn(list) do add(UM_TexturePath(list[i].icon)) end
  end

  if table.getn(out) > 0 then
    UM_ICON_CHOICES = out -- full texture paths now
  end
  UM_IconChoicesBuilt = true
end

-- ===========================
-- Pure-Lua UI (no XML needed)
-- ===========================

local function UM_SkinFrame(frame)
  frame:SetBackdrop({
    bgFile  = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile= "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
end

-- Helper: Create section header with divider line
local function UM_CreateSectionHeader(parent, text, yOffset)
  local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)
  header:SetText(text)

  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  line:SetPoint("LEFT", header, "BOTTOMLEFT", 0, -2)
  line:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
  line:SetTexture(0.5, 0.5, 0.5, 0.5)

  return header
end

-- ============================================================
-- Icon Picker (scrollable grid with search)
-- ============================================================
local UM_IconPicker = nil

local function UM_CloseIconPicker()
  if UM_IconPicker then UM_IconPicker:Hide() end
end

local function UM_EnsureIconPicker()
  if UM_IconPicker then return UM_IconPicker end

  local f = CreateFrame("Frame", "UltimaMacrosIconPicker", UIParent)
  f:SetWidth(360); f:SetHeight(320)
  f:SetBackdrop({ bgFile="Interface\\ChatFrame\\ChatFrameBackground",
                  edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                  tile=true, tileSize=16, edgeSize=16,
                  insets={ left=4, right=4, top=4, bottom=4 } })
  f:SetBackdropColor(0,0,0,0.9)
  f:SetBackdropBorderColor(0.3,0.3,0.3,1)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)  -- Changed from this to f
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)  -- Changed from this to f
  f:SetFrameStrata("DIALOG")  -- ADD THIS - ensures it's above the main frame
  f:SetToplevel(true)  -- ADD THIS - makes it independently clickable

  local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  t:SetPoint("TOP", 0, -10)
  t:SetText("Choose Icon")
  f.title = t

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  local lab = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lab:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
  lab:SetText("Search")

  local edit = CreateFrame("EditBox", "UltimaMacrosIconSearch", f, "InputBoxTemplate")
  edit:SetAutoFocus(false)
  edit:SetWidth(220); edit:SetHeight(20)
  edit:SetPoint("LEFT", lab, "RIGHT", 8, 0)
  edit:SetMaxLetters(64)
  edit:SetText("")
  f.searchBox = edit

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", edit, "LEFT", 6, 0)
  hint:SetText("icon name...")
  f.searchHint = hint

  edit:SetScript("OnTextChanged", function()
    if strlen(this:GetText()) == 0 then
      f.searchHint:Show()
    else
      f.searchHint:Hide()
    end
    f:ApplyFilter(this:GetText())
  end)
  edit:SetScript("OnEditFocusGained", function() hint:Hide() end)
  edit:SetScript("OnEditFocusLost", function()
    if edit:GetText() == "" then hint:Show() end
  end)
  edit:SetScript("OnEscapePressed", function()
    edit:ClearFocus()
    if edit:GetText() ~= "" then
      edit:SetText("")
      hint:Show()
      if f.ApplyFilter then f:ApplyFilter("") end
    end
  end)

  local scroll = CreateFrame("ScrollFrame", "UltimaMacrosIconScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -64)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 12)

  local content = CreateFrame("Frame", "UltimaMacrosIconGrid", scroll)
  content:SetWidth(320); content:SetHeight(300)
  scroll:SetScrollChild(content)

  f.scroll = scroll
  f.content = content

  -- ADD MOUSE WHEEL SCROLLING
  local function UM_IconPickerWheelScroll(delta)
    if ScrollFrameTemplate_OnMouseWheel then
      local oldThis = this
      this = scroll
      ScrollFrameTemplate_OnMouseWheel(delta or 0)
      this = oldThis
    else
      local bar = getglobal(scroll:GetName() .. "ScrollBar")
      if bar then
        local step = (bar:GetValueStep() or 20) * 3
        bar:SetValue((bar:GetValue() or 0) - (delta or 0) * step)
      end
    end
  end

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function()
    UM_IconPickerWheelScroll(arg1 or 0)
  end)

  local COLS = 8
  local SIZE = 32
  local PAD  = 6

  function f:ApplyFilter(query)
    query = string.lower(query or "")
    local total = table.getn(UM_ICON_CHOICES)
    local visible = {}

    if query == "" then
      for i = 1, total do visible[table.getn(visible)+1] = i end
    else
      for i = 1, total do
        local tex = UM_ICON_CHOICES[i]
        local base = UM_IconBasename(tex)
        if string.find(base, query, 1, true) then
          visible[table.getn(visible)+1] = i
        end
      end
    end

    local n = table.getn(visible)
    local rows = math.ceil(n / COLS)
    local contentH = rows * (SIZE + PAD) + PAD
    content:SetHeight(contentH)

    -- Update scroll frame
    if scroll.UpdateScrollChildRect then
      scroll:UpdateScrollChildRect()
    end

    local shownSet = {}
    for vi = 1, n do
      local idx = visible[vi]
      local btn = getglobal("UltimaMacrosIconCell"..idx)
      if btn then
        local row = math.floor((vi-1) / COLS)
        local col = math.mod(vi-1, COLS)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", content, "TOPLEFT",
                     PAD + col * (SIZE + PAD),
                     -PAD - row * (SIZE + PAD))
        btn:Show()
        shownSet[idx] = true
      end
    end

    for i = 1, total do
      if not shownSet[i] then
        local btn = getglobal("UltimaMacrosIconCell"..i)
        if btn then btn:Hide() end
      end
    end
  end

  function f:Rebuild(nm)
    local rec = nm and UM_Get(nm)
    UM_RebuildIconChoices()

    local total = table.getn(UM_ICON_CHOICES)

    for i = 1, total do
      local btn = getglobal("UltimaMacrosIconCell"..i)
      if not btn then
        btn = CreateFrame("Button", "UltimaMacrosIconCell"..i, content)
        btn:SetWidth(SIZE); btn:SetHeight(SIZE)
        btn.icon = btn:CreateTexture(nil, "BACKGROUND")
        btn.icon:SetAllPoints(btn)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        btn:SetScript("OnClick", function()
          local tex = this._tex
          local name = UltimaMacrosFrameNameEdit and UltimaMacrosFrameNameEdit:GetText() or ""
          if name == "" then return end
          local r = UM_Get(name); if not r then return end
          r.icon = tex
          if UltimaMacrosIconButton then
            UltimaMacrosIconButton:SetNormalTexture(UM_TexturePath(tex))
          end
          UM_RefreshAllSlotsForName(name)
          UM_CloseIconPicker()
        end)
      end
      local tex = UM_ICON_CHOICES[i]
      btn._tex = tex
      btn.icon:SetTexture(UM_TexturePath(tex))
    end

    local i2 = total + 1
    while true do
      local extra = getglobal("UltimaMacrosIconCell"..i2)
      if not extra then break end
      extra:Hide()
      i2 = i2 + 1
    end

    local q = f.searchBox and f.searchBox:GetText() or ""
    if q == "" then f.searchHint:Show() else f.searchHint:Hide() end
    f:ApplyFilter(q or "")
  end

  tinsert(UISpecialFrames, "UltimaMacrosIconPicker")

  UM_IconPicker = f
  return f
end

local function UM_OpenIconPicker(anchorFrame)
  local f = UM_EnsureIconPicker()
  f:ClearAllPoints()
  if anchorFrame then
    f:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", -8, -8)
  else
    f:SetPoint("CENTER")
  end
  f:Show()
  local nm = (UltimaMacrosFrameNameEdit and UltimaMacrosFrameNameEdit:GetText()) or ""
  f:Rebuild(nm)
end

-- ============================================================
-- Main UI
-- ============================================================
function UM_BuildGUI()
  if UM_LocalUI and UM_LocalUI.frame then return end

  local f = CreateFrame("Frame", "UltimaMacrosFrame", UIParent)
  f:SetWidth(720); f:SetHeight(470)

  if UltimaMacrosDB and UltimaMacrosDB.pos then
    f:ClearAllPoints()
    f:SetPoint(UltimaMacrosDB.pos.p or "CENTER", UIParent, UltimaMacrosDB.pos.rp or "CENTER",
               UltimaMacrosDB.pos.x or 0, UltimaMacrosDB.pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end

  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop",  function()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    UltimaMacrosDB.pos = { p = p, rp = rp, x = x, y = y }
  end)
  f:SetScript("OnHide", function()
    f:StopMovingOrSizing()
    if UltimaMacrosFrameNameEdit then UltimaMacrosFrameNameEdit:ClearFocus() end
    if UltimaMacrosFrameEditBox then UltimaMacrosFrameEditBox:ClearFocus() end
  end)

  UM_SkinFrame(f)
  f:Hide()
  UM_LocalUI.frame = f

  if UISpecialFrames then tinsert(UISpecialFrames, "UltimaMacrosFrame") end
  if UIPanelWindows then
    UIPanelWindows[f:GetName()] = { area = "center", pushable = 1 }
  end

  -- Title
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  title:SetPoint("TOP", f, "TOP", 0, -16)
  title:SetText("UltimaMacros")

  -- Drag area
  local drag = CreateFrame("Frame", nil, f)
  drag:SetWidth(680); drag:SetHeight(26)
  drag:SetPoint("TOP", f, "TOP", 0, -12)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() f:StartMoving() end)
  drag:SetScript("OnDragStop",  function()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    UltimaMacrosDB.pos = { p = p, rp = rp, x = x, y = y }
  end)

  -- Close button
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() HideUIPanel(f) end)

  -- ===== LEFT SIDE: Macro List =====
  local macrosHeader = UM_CreateSectionHeader(f, "Macros", -50)

  local listScroll = CreateFrame("ScrollFrame", "UltimaMacrosListScroll", f, "UIPanelScrollFrameTemplate")
  listScroll:SetWidth(150); listScroll:SetHeight(360)
  listScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -70)

  local listContent = CreateFrame("Frame", "UltimaMacrosListContent", listScroll)
  listContent:SetWidth(150); listContent:SetHeight(360)
  listContent:SetPoint("TOPLEFT", listScroll, "TOPLEFT", 0, 0)
  listScroll:SetScrollChild(listContent)

  -- ===== RIGHT SIDE: Editor =====
  local editorHeader = UM_CreateSectionHeader(f, "Editor", -50)
  editorHeader:ClearAllPoints()
  editorHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -50)

  -- Name field
  local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nameLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 200, -68)
  nameLabel:SetText("Name:")

  local nameEdit = CreateFrame("EditBox", "UltimaMacrosFrameNameEdit", f, "InputBoxTemplate")
  nameEdit:SetWidth(360); nameEdit:SetHeight(20)
  nameEdit:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 5, -4)
  nameEdit:SetAutoFocus(false)
  nameEdit:EnableMouse(true)
  nameEdit:EnableKeyboard(true)
  if nameEdit.SetMaxLetters then nameEdit:SetMaxLetters(64) end
  nameEdit:SetTextInsets(8, 8, 2, 2)

  nameEdit:SetScript("OnMouseDown", function() this:SetFocus() end)
  nameEdit:SetScript("OnEnterPressed", function()
    if UltimaMacrosFrameEditBox then UltimaMacrosFrameEditBox:SetFocus() end
  end)
  nameEdit:SetScript("OnTabPressed", function()
    if UltimaMacrosFrameEditBox then UltimaMacrosFrameEditBox:SetFocus() end
  end)
  nameEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  nameEdit:SetScript("OnKeyDown", function()
    if arg1 == "S" and IsControlKeyDown() then
      UM_UI_Save()
    end
  end)

  -- Scope indicator
  local scopeIndicator = f:CreateFontString("UltimaMacrosScopeIndicator", "OVERLAY", "GameFontHighlight")
  scopeIndicator:SetPoint("LEFT", nameEdit, "RIGHT", 8, 0)
  scopeIndicator:SetText("[Char]")
  scopeIndicator:SetTextColor(0.3, 0.8, 1.0)

  -- Icon button
  local iconBtn = CreateFrame("Button", "UltimaMacrosIconButton", f)
  iconBtn:SetWidth(36); iconBtn:SetHeight(36)
  iconBtn:SetPoint("TOPLEFT", nameEdit, "BOTTOMLEFT", 0, -8)
  iconBtn:SetNormalTexture(UM_TexturePath(UM_DEFAULT_ICON))
  iconBtn:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  iconBtn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  iconBtn:RegisterForDrag("LeftButton")
  iconBtn._idx = 1

  iconBtn:SetScript("OnClick", function() UM_OpenIconPicker(iconBtn) end)
  iconBtn:SetScript("OnDragStart", function()
    local nm = UltimaMacrosFrameNameEdit:GetText() or ""
    UM_StartDrag(nm)
  end)
  iconBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Macro Icon")
    GameTooltip:AddLine("Click to choose a different icon", 1, 1, 1, true)
    GameTooltip:AddLine("Drag to place macro on action bar", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local iconLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  iconLabel:SetPoint("LEFT", iconBtn, "RIGHT", 6, 0)
  iconLabel:SetText("Icon (click to change, drag to action bar)")

  -- Scope checkbox
  local scopeCheck = CreateFrame("CheckButton", "UltimaMacrosScopeCheck", f, "UICheckButtonTemplate")
  scopeCheck:SetPoint("TOPLEFT", iconBtn, "BOTTOMLEFT", -4, -8)
  scopeCheck:SetChecked(true)

  _G["UltimaMacrosScopeCheckText"] = f:CreateFontString("UltimaMacrosScopeCheckText", "OVERLAY", "GameFontHighlightSmall")
  UltimaMacrosScopeCheckText:SetPoint("LEFT", scopeCheck, "RIGHT", 4, 0)
  UltimaMacrosScopeCheckText:SetText("Per Character (uncheck for Account-wide)")
  scopeCheck:SetScript("OnClick", function() if UM_UI_ToggleScope then UM_UI_ToggleScope() end end)

  -- Buttons
  local BTN_WIDTH = 70
  local BTN_SPACING = 4

  local function makeBtn(name, label, parent)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetWidth(BTN_WIDTH); b:SetHeight(22)
    b:SetText(label)
    return b
  end

  local newC = makeBtn("UltimaMacrosNewCharButton", "New", f)
  newC:SetPoint("TOPLEFT", scopeCheck, "BOTTOMLEFT", 4, -10)
  newC:SetScript("OnClick", function() if UM_UI_NewChar then UM_UI_NewChar() end end)

  local save = makeBtn("UltimaMacrosSaveButton", "Save", f)
  save:SetPoint("LEFT", newC, "RIGHT", BTN_SPACING, 0)
  save:SetScript("OnClick", function() if UM_UI_Save then UM_UI_Save() end end)
  save:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Save Macro (Ctrl+S)")
    GameTooltip:Show()
  end)
  save:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local run = makeBtn("UltimaMacrosRunButton", "Run", f)
  run:SetPoint("LEFT", save, "RIGHT", BTN_SPACING, 0)
  run:SetScript("OnClick", function() if UM_UI_Run then UM_UI_Run() end end)

  local del = makeBtn("UltimaMacrosDeleteButton", "Delete", f)
  del:SetPoint("LEFT", run, "RIGHT", BTN_SPACING, 0)
  del:SetScript("OnClick", function() if UM_UI_Delete then UM_UI_Delete() end end)

  -- Editor background
  local editorBG = CreateFrame("Frame", "UltimaMacrosEditorBG", f)
  editorBG:SetWidth(380); editorBG:SetHeight(230)
  editorBG:SetPoint("TOPLEFT", newC, "BOTTOMLEFT", -4, -8)
  editorBG:SetBackdrop({
    bgFile  = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile= "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 12, edgeSize = 12,
    insets = { left=2, right=2, top=2, bottom=2 }
  })
  editorBG:SetBackdropColor(0,0,0,0.8)

  -- Character counter
  local counter = f:CreateFontString("UltimaMacrosFrameCounter", "OVERLAY", "GameFontHighlightSmall")
  counter:SetPoint("TOPRIGHT", editorBG, "BOTTOMRIGHT", -6, -4)
  counter:SetText("0/2056")

  -- EditBox with scroll
  local editScroll = CreateFrame("ScrollFrame", "UltimaMacrosEditScroll", f, "UIPanelScrollFrameTemplate")
  editScroll:SetWidth(360); editScroll:SetHeight(210)
  editScroll:SetPoint("TOPLEFT", editorBG, "TOPLEFT", 10, -10)
  editScroll:EnableMouse(true)

  local editBox = CreateFrame("EditBox", "UltimaMacrosFrameEditBox", editScroll)
  editBox:SetMultiLine(true)
  editBox:SetWidth(360)
  editBox:SetHeight(1200)
  editBox:SetTextInsets(6, 6, 4, 4)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetAutoFocus(false)
  editBox:EnableMouse(true)
  editBox:EnableKeyboard(true)

  editScroll:SetScrollChild(editBox)
  if editScroll.UpdateScrollChildRect then editScroll:UpdateScrollChildRect() end

  editBox:SetScript("OnTextChanged", function()
    UM_hasUnsavedChanges = true
    counter:SetTextColor(1, 0.8, 0)

    if UM_UI_OnTextChanged then UM_UI_OnTextChanged() end
    if UltimaMacrosEditScroll and UltimaMacrosEditScroll.UpdateScrollChildRect then
      UltimaMacrosEditScroll:UpdateScrollChildRect()
    else
      UltimaMacrosEditScroll:SetScrollChild(editBox)
    end
  end)

  editBox:SetScript("OnMouseDown", function() this:SetFocus() end)
  editBox:SetScript("OnTabPressed", function()
    if UltimaMacrosFrameNameEdit then UltimaMacrosFrameNameEdit:SetFocus() end
  end)
  editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  editBox:SetScript("OnKeyDown", function()
    if arg1 == "S" and IsControlKeyDown() then
      UM_UI_Save()
      this:ClearFocus()
    end
  end)

  editBox:SetScript("OnCursorChanged", function(x, y, w, h)
    local sf = UltimaMacrosEditScroll
    if not sf then return end
    if not y or not h then
      if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
      return
    end

    local view = sf:GetHeight() or 0
    local cur  = sf:GetVerticalScroll() or 0
    local top    = -y
    local bottom = top + h
    local PAD = 8

    if top < cur + PAD then
      sf:SetVerticalScroll(math.max(top - PAD, 0))
    elseif bottom > (cur + view - PAD) then
      sf:SetVerticalScroll(math.max(bottom - view + PAD, 0))
    end
  end)

  local function UM_WheelScroll(sf, delta)
    if ScrollFrameTemplate_OnMouseWheel then
      local oldThis = this
      this = sf
      ScrollFrameTemplate_OnMouseWheel(delta or 0)
      this = oldThis
      return
    end
    local bar = getglobal(sf:GetName() .. "ScrollBar")
    if not bar then return end
    local step = (bar:GetValueStep() or 20) * 3
    bar:SetValue((bar:GetValue() or 0) - (delta or 0) * step)
  end

  editScroll:EnableMouseWheel(true)
  editBox:EnableMouseWheel(true)
  editScroll:SetScript("OnMouseWheel", function()
    UM_WheelScroll(this, arg1 or 0)
  end)
  editBox:SetScript("OnMouseWheel", function()
    UM_WheelScroll(UltimaMacrosEditScroll, arg1 or 0)
  end)
  editScroll:SetScript("OnMouseDown", function()
    if UltimaMacrosFrameEditBox then UltimaMacrosFrameEditBox:SetFocus() end
  end)

  UM_LocalUI.listScroll  = listScroll
  UM_LocalUI.listContent = listContent
  UM_LocalUI.scopeIndicator = scopeIndicator
  UM_LocalUI.counter = counter

  f:SetScript("OnShow", function()
    if UM_UI_RefreshList then UM_UI_RefreshList() end
    if UM_UI_UpdateCounter then UM_UI_UpdateCounter() end
    if UM_RebuildIconChoices then UM_RebuildIconChoices() end
  end)
end

-- --- Event wiring (works without XML) ---
local UM_EventFrame = CreateFrame("Frame")
UM_EventFrame:RegisterEvent("VARIABLES_LOADED")
UM_EventFrame:RegisterEvent("PLAYER_LOGIN")
UM_EventFrame:RegisterEvent("ADDON_LOADED")          -- recheck when SCM/SuperMacro load later
UM_EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD") -- one-shot delayed recheck

UM_EventFrame:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" or event == "PLAYER_LOGIN" then
    UM_BuildGUI()
    UM_EnsureTables()
    UM_InstallHooks()

    -- Immediate SCM check (if it was loaded before us)
    if UM_IsSCMLoaded() then
      UM_EnableSCMCompat()
    end

    if UM_UI_RefreshList then UM_UI_RefreshList() end
    if UM_UI_UpdateCounter then UM_UI_UpdateCounter() end
    if UM_RebuildIconChoices then UM_RebuildIconChoices() end
    if UM_UI_FixButtonLabels then UM_UI_FixButtonLabels() end

  elseif event == "ADDON_LOADED" then
    -- Vanilla-style global arg1 contains the addon name
    local addon = arg1
    if addon == "SuperCleveroidMacros" or addon == "SuperCleveroid" or addon == "SuperMacro" then
      if not UM_SCM_compat_enabled then
        UM_EnableSCMCompat()
      end
    end

  elseif event == "PLAYER_ENTERING_WORLD" then
    -- One-shot delayed check (some UIs finish loading after login)
    if not UM_SCM_compat_enabled and UM_IsSCMLoaded() then
      UM_EnableSCMCompat()
    end
    UM_EventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
  end
end)

local function UM_Open()
  UM_BuildGUI()
  ShowUIPanel(UM_LocalUI.frame)
end

function UM_ToggleFrame()
  UM_BuildGUI()
  if UltimaMacrosFrame:IsShown() then
    HideUIPanel(UltimaMacrosFrame)
  else
    ShowUIPanel(UltimaMacrosFrame)
  end
end
