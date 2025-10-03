-- UltimaMacros - Vanilla 1.12.1 (Lua 5.0)
-- Separate macro list stored in SavedVariables with 1028-char per macro cap.
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

-- UI scope state (editor checkbox): "char" or "account"
local UM_UI_Scope = "char"

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
  return "Interface\\Icons\\" .. icon
end

-- Make the frame behave like a standard panel (ShowUIPanel/HideUIPanel)
if UIPanelWindows then
  UIPanelWindows["UltimaMacrosFrame"] = { area = "center", pushable = 1 }
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

-- Re-index SCM/CleveRoids and repaint any slots mapped to this macro name
local function UM_RefreshAllSlotsForName(name)
  if not name or name == "" then return end

  -- Re-index SuperCleveroid/SuperMacro so #showtooltip parsing is up-to-date
  if CleveRoids and CleveRoids.Frame and CleveRoids.Frame.UPDATE_MACROS then
    pcall(CleveRoids.Frame.UPDATE_MACROS, CleveRoids.Frame)
    if CleveRoids.QueueActionUpdate then pcall(CleveRoids.QueueActionUpdate) end
  end

  -- Refresh any actionbar slot mapped to this name (dynamic icon, tooltip, usable/cooldown/state)
  for slot = 1, 120 do
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
  if string.len(text) > 1028 then
    text = string.sub(text, 1, 1028)
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
    if code and code ~= "" then RunScript(code) end
    return
  end

  local lower4 = string.lower(string.sub(line, 1, 4))
  if lower4 == "/run" then
    local code2 = string.sub(line, 5)
    if code2 and code2 ~= "" then RunScript(code2) end
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
end

local function UM_ClearAction(slot)
  UM_GetActionMap()[slot] = nil
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

      -- Use the CURRENT GetActionTexture (our override defers to SCM for #showtooltip),
      -- then fallback to UM’s saved static icon if it’s nil.
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
  local bars = { "MultiBarRight", "MultiBarLeft", "MultiBarBottomLeft", "MultiBarBottomRight" }
  for bi=1, table.getn(bars) do
    local bar = bars[bi]
    for i=1,12 do touch(bar.."Button"..i) end
  end

  if ActionBar_UpdateUsable then ActionBar_UpdateUsable() end
  if ActionBar_UpdateCooldowns then ActionBar_UpdateCooldowns() end
  if ActionBar_UpdateState then ActionBar_UpdateState() end
end

-- ----- SuperMacro-like proxy pickup -----
local UM_oldPickupMacro, UM_oldEditMacro, UM_oldGetMacroInfo, UM_oldCreateMacro
local UM_oldActionButton_OnClick, UM_oldActionButton_OnReceiveDrag
local UM_proxyMacroIndex = nil

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
  if not UM_oldPickupMacro then return false end
  local idx = UM_GetOrCreateProxyMacroIndex()
  if not idx then return false end
  local ok = pcall(UM_oldPickupMacro, idx)
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

-- Public drag API for UI (no OnDragStop clearing!)
function UM_StartDrag(name)
  if not name or name == "" or not UM_Get(name) then return end
  UM_CURSOR = name
  ClearCursor()
  if UM_PickupUsingMacroProxy() then return end
  if UM_PickupProxyForDrag_Fallback() then return end
  UM_CURSOR = nil
  DEFAULT_CHAT_FRAME:AddMessage("|cffff5555UltimaMacros: couldn't start drag (no valid pickup payload).|r")
end

function UM_EndDrag()
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

  -- Save originals once
  UM_oldGetActionInfo       = UM_oldGetActionInfo       or GetActionInfo
  UM_oldGetMacroInfo        = UM_oldGetMacroInfo        or GetMacroInfo
  UM_oldGetMacroIndexByName = UM_oldGetMacroIndexByName or GetMacroIndexByName

  -- 1) Report UM-mapped slots as “macro” with a stable virtual id (slot-space)
  GetActionInfo = function(slot)
    local name = UM_GetMappedName and UM_GetMappedName(slot)
    if name then
      return "macro", (UM_SCM_SLOT_BASE + slot), nil
    end
    return UM_oldGetActionInfo and UM_oldGetActionInfo(slot) or nil
  end

  -- 2) Make GetMacroIndexByName(name) return a **virtual id** for UM macros (name-space)
  GetMacroIndexByName = function(name)
    if name and UM_FindIndexByName then
      local idx = UM_FindIndexByName(name)
      if idx then
        return UM_AssignNameIndex(name)
      end
    end
    return UM_oldGetMacroIndexByName(name)
  end

  -- 3) Serve GetMacroInfo for both virtual id spaces (slot & name)
  GetMacroInfo = function(index)
    local vname = UM_NameFromVirtualIndex(index)
    if vname then
      local rec = UM_Get and UM_Get(vname)
      local iconTex = UM_GetIconFor and UM_GetIconFor(vname) or "Interface\\Icons\\INV_Misc_QuestionMark"
      local body = (rec and rec.text) or ""
      -- Vanilla returns (name, texture, body)
      return vname, iconTex, body
    end
    -- Not one of ours → fall back to whatever (Blizzard or SuperMacro wrapper)
    return UM_oldGetMacroInfo(index)
  end
end

-- ----- Hooks: map your macro to action bar, render icon/name, run on press -----
local function UM_InstallHooks()
  if UM_HooksInstalled then return end
  UM_HooksInstalled = true

  UM_oldPickupMacro       = PickupMacro
  UM_oldEditMacro         = EditMacro
  UM_oldGetMacroInfo      = GetMacroInfo
  UM_oldCreateMacro       = CreateMacro

  local UM_oldPlaceAction   = PlaceAction
  local UM_oldUseAction     = UseAction
  local UM_oldPickupAction  = PickupAction
  local UM_oldGetActionText = GetActionText
  local UM_oldGetActionTex  = GetActionTexture
  UM_oldActionButton_OnClick       = ActionButton_OnClick
  UM_oldActionButton_OnReceiveDrag = ActionButton_OnReceiveDrag

  PlaceAction = function(slot)
    if UM_CURSOR then
      UM_SetAction(slot, UM_CURSOR)
      UM_CURSOR = nil
      ClearCursor()
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
      if not UM_PickupUsingMacroProxy then return end
      if not UM_PickupUsingMacroProxy() then
        UM_PickupProxyForDrag_Fallback()
      end
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
      -- Try Blizzard/SCM dynamic resolution (#showtooltip) first
      local tex = UM_oldGetActionTex and UM_oldGetActionTex(slot)
      if tex then return tex end
      -- Fallback so we never show a blank icon
      return UM_GetIconFor(name)
    end
    return UM_oldGetActionTex and UM_oldGetActionTex(slot) or nil
  end

  -- Click-to-place while a drag is active
  ActionButton_OnClick = function(button)
    if UM_CURSOR then
      local btn = this or button
      local id = (ActionButton_GetPagedID and btn and ActionButton_GetPagedID(btn)) or (btn and btn.action)
      if id then
        PlaceAction(id)
        UM_RefreshActionButtonsForSlot(id)
        return
      end
    end
    if UM_oldActionButton_OnClick then
      return UM_oldActionButton_OnClick(button)
    end
  end

  -- Drop-to-place (OnReceiveDrag) — ensure UM_CURSOR is still honored
  ActionButton_OnReceiveDrag = function()
    if UM_CURSOR then
      local btn = this
      local id = (ActionButton_GetPagedID and btn and ActionButton_GetPagedID(btn)) or (btn and btn.action)
      if id then
        PlaceAction(id)
        UM_RefreshActionButtonsForSlot(id)
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
      DEFAULT_CHAT_FRAME:AddMessage(" - "..tag.." "..list[i].name.." ("..string.len(list[i].text or "").."/1028)")
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
    UltimaMacrosNewCharButton:SetText("New (C)")
  end
  if UltimaMacrosNewAccountButton then
    UltimaMacrosNewAccountButton:SetText("New (A)")
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

    -- normal click loads into editor
    btn:SetScript("OnClick", function() UM_UI_LoadIntoEditor(name) end)

    -- Left-drag from the list starts our drag (no Shift); no OnDragStop clearing
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function() UM_StartDrag(name) end)

    btn:Show()
    offsetY = offsetY - 22
  end

  UltimaMacrosListContent:SetHeight(math.max(330, -offsetY + 4))
  UM_UI_FixButtonLabels()
end

function UM_UI_LoadIntoEditor(name)
  local m, scope = UM_Get(name)
  if not m then return end
  UltimaMacrosFrameNameEdit:SetText(m.name or "")
  UltimaMacrosFrameEditBox:SetText(m.text or "")
  UM_UI_Scope = scope or "char"
  if UltimaMacrosScopeCheck then
    UltimaMacrosScopeCheck:SetChecked(UM_UI_Scope == "char")
    UltimaMacrosScopeCheckText:SetText((UM_UI_Scope == "char") and "Per Character" or "Per Account")
  end
  if UltimaMacrosIconButton then
    local icon = (m.icon and m.icon ~= "") and m.icon or UM_DEFAULT_ICON
    UltimaMacrosIconButton:SetNormalTexture(UM_TexturePath(icon))
    local found = 1
    for i=1, table.getn(UM_ICON_CHOICES) do
      if UM_ICON_CHOICES[i] == icon then found = i; break end
    end
    UltimaMacrosIconButton._idx = found
  end
  UM_UI_UpdateCounter()
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
  if string.len(text) > 1028 then
    text = string.sub(text, 1, 1028)
    UltimaMacrosFrameEditBox:SetText(text)
  end
  UM_Save(name, text, UM_UI_Scope)
  UM_UI_RefreshList()
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
  UM_Delete(name)
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
  if used > 1028 then
    text = string.sub(text, 1, 1028)
    UltimaMacrosFrameEditBox:SetText(text)
    used = 1028
  end
  UltimaMacrosFrameCounter:SetText(used .. "/1028")
end

function UM_UI_ToggleScope()
  local checked = UltimaMacrosScopeCheck:GetChecked()
  if checked then
    UM_UI_Scope = "char"
    UltimaMacrosScopeCheckText:SetText("Per Character")
  else
    UM_UI_Scope = "account"
    UltimaMacrosScopeCheckText:SetText("Per Account")
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

-- ===========================
-- Pure-Lua UI (no XML needed)
-- ===========================
local UM_LocalUI = {}  -- local namespace for UI locals

local function UM_SkinFrame(frame)
  frame:SetBackdrop({
    bgFile  = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile= "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
end

function UM_BuildGUI()
  if UM_LocalUI and UM_LocalUI.frame then return end
  UM_LocalUI = UM_LocalUI or {}

  local f = CreateFrame("Frame", "UltimaMacrosFrame", UIParent)
  f:SetWidth(700); f:SetHeight(440)

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
  -- after you build the widgets inside UM_BuildGUI(), add:
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

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  title:SetPoint("TOP", f, "TOP", 0, -16)
  title:SetText("UltimaMacros")

  local drag = CreateFrame("Frame", nil, f)
  drag:SetWidth(660); drag:SetHeight(26)
  drag:SetPoint("TOP", f, "TOP", 0, -12)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() f:StartMoving() end)
  drag:SetScript("OnDragStop",  function()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    UltimaMacrosDB.pos = { p = p, rp = rp, x = x, y = y }
  end)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() HideUIPanel(f) end)

  local listScroll = CreateFrame("ScrollFrame", "UltimaMacrosListScroll", f, "UIPanelScrollFrameTemplate")
  listScroll:SetWidth(150); listScroll:SetHeight(310)
  listScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -72)

  local listContent = CreateFrame("Frame", "UltimaMacrosListContent", listScroll)
  listContent:SetWidth(150); listContent:SetHeight(310)
  listContent:SetPoint("TOPLEFT", listScroll, "TOPLEFT", 0, 0)
  listScroll:SetScrollChild(listContent)

  -- Name box
  local nameEdit = CreateFrame("EditBox", "UltimaMacrosFrameNameEdit", f, "InputBoxTemplate")
  nameEdit:SetWidth(380); nameEdit:SetHeight(20)
  nameEdit:SetPoint("TOPLEFT", f, "TOPLEFT", 205, -44)
  nameEdit:SetAutoFocus(false)
  nameEdit:EnableMouse(true)
  nameEdit:EnableKeyboard(true)
  if nameEdit.SetMaxLetters then nameEdit:SetMaxLetters(64) end
  nameEdit:SetTextInsets(8, 8, 2, 2)

  -- Click → focus name field (Vanilla: use 'this', not 'self')
  nameEdit:SetScript("OnMouseDown", function() this:SetFocus() end)

  -- Enter/Tab → jump to body
  nameEdit:SetScript("OnEnterPressed", function()
  if UltimaMacrosFrameEditBox then UltimaMacrosFrameEditBox:SetFocus() end
    end)
  nameEdit:SetScript("OnTabPressed", function()
  if UltimaMacrosFrameEditBox then UltimaMacrosFrameEditBox:SetFocus() end
    end)

  -- Esc → clear focus (Esc again will close via UISpecialFrames)
  nameEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

  local scopeCheck = CreateFrame("CheckButton", "UltimaMacrosScopeCheck", f, "UICheckButtonTemplate")
  scopeCheck:SetPoint("LEFT", nameEdit, "RIGHT", 2, 0)
  scopeCheck:SetChecked(true)
  _G["UltimaMacrosScopeCheckText"] = f:CreateFontString("UltimaMacrosScopeCheckText", "OVERLAY", "GameFontHighlightSmall")
  UltimaMacrosScopeCheckText:SetPoint("LEFT", scopeCheck, "RIGHT", 4, 0)
  UltimaMacrosScopeCheckText:SetText("Per Character")
  scopeCheck:SetScript("OnClick", function() if UM_UI_ToggleScope then UM_UI_ToggleScope() end end)

  -- Icon button (unchanged except for new anchor you picked)
  local iconBtn = CreateFrame("Button", "UltimaMacrosIconButton", f)
  iconBtn:SetWidth(22); iconBtn:SetHeight(22)
  iconBtn:SetPoint("LEFT", UltimaMacrosScopeCheckText, "RIGHT", -37, -30)
  iconBtn:SetNormalTexture(UM_TexturePath(UM_DEFAULT_ICON))
  iconBtn:RegisterForDrag("LeftButton")
  iconBtn._idx = 1
  iconBtn:SetScript("OnClick", function()
  local nm = (UltimaMacrosFrameNameEdit and UltimaMacrosFrameNameEdit:GetText()) or ""
  if nm == "" then return end
    local rec = UM_Get(nm); if not rec then return end
    iconBtn._idx = (iconBtn._idx or 1) + 1
    local total = table.getn(UM_ICON_CHOICES)
    if iconBtn._idx > total then iconBtn._idx = 1 end
      local choice = UM_ICON_CHOICES[iconBtn._idx]
      rec.icon = choice
      iconBtn:SetNormalTexture(UM_TexturePath(choice))
      UM_RefreshAllSlotsForName(nm)
      end)
  iconBtn:SetScript("OnDragStart", function()
  local nm = UltimaMacrosFrameNameEdit:GetText() or ""
  UM_StartDrag(nm)
  end)

  local function makeBtn(name, label, parent)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetWidth(80); b:SetHeight(22)
    b:SetText(label)
    return b
  end

  local newC = makeBtn("UltimaMacrosNewCharButton", "New (C)", f)
  newC:SetPoint("TOPLEFT", nameEdit, "BOTTOMLEFT", 0, -10)
  newC:SetScript("OnClick", function() if UM_UI_NewChar then UM_UI_NewChar() end end)

  local newA = makeBtn("UltimaMacrosNewAccountButton", "New (A)", f)
  newA:SetPoint("LEFT", newC, "RIGHT", 5, 0)
  newA:SetScript("OnClick", function() if UM_UI_NewAccount then UM_UI_NewAccount() end end)

  local save = makeBtn("UltimaMacrosSaveButton", "Save", f)
  save:SetPoint("LEFT", newA, "RIGHT", 5, 0)
  save:SetScript("OnClick", function() if UM_UI_Save then UM_UI_Save() end end)

  local run = makeBtn("UltimaMacrosRunButton", "Run", f)
  run:SetPoint("LEFT", save, "RIGHT", 5, 0)
  run:SetScript("OnClick", function() if UM_UI_Run then UM_UI_Run() end end)

  local del = makeBtn("UltimaMacrosDeleteButton", "Delete", f)
  del:SetPoint("LEFT", run, "RIGHT", 5, 0)
  del:SetScript("OnClick", function() if UM_UI_Delete then UM_UI_Delete() end end)

  local editorBG = CreateFrame("Frame", "UltimaMacrosEditorBG", f)
  editorBG:SetWidth(380); editorBG:SetHeight(300)
  editorBG:SetPoint("TOPLEFT", newC, "BOTTOMLEFT", 0, -12)
  editorBG:SetBackdrop({
    bgFile  = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile= "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 12, edgeSize = 12,
    insets = { left=2, right=2, top=2, bottom=2 }
  })
  editorBG:SetBackdropColor(0,0,0,0.8)

  local counter = f:CreateFontString("UltimaMacrosFrameCounter", "OVERLAY", "GameFontHighlightSmall")
  counter:SetPoint("TOPRIGHT", editorBG, "BOTTOMRIGHT", -6, -4)
  counter:SetText("0/1028")

  -- Body area: ScrollFrame + EditBox
  local editScroll = CreateFrame("ScrollFrame", "UltimaMacrosEditScroll", f, "UIPanelScrollFrameTemplate")
  editScroll:SetWidth(365); editScroll:SetHeight(280)
  editScroll:SetPoint("TOPLEFT", editorBG, "TOPLEFT", 10, -10)
  editScroll:EnableMouse(true)

  -- Create the EditBox BEFORE assigning as child
  local editBox = CreateFrame("EditBox", "UltimaMacrosFrameEditBox", editScroll)
  editBox:SetMultiLine(true)
  editBox:SetWidth(380); editBox:SetHeight(260)
  editBox:SetTextInsets(6, 6, 4, 4)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetAutoFocus(false)
  editBox:EnableMouse(true)
  editBox:EnableKeyboard(true)
  editBox:SetScript("OnTextChanged", function() if UM_UI_OnTextChanged then UM_UI_OnTextChanged() end end)


  -- Click inside → focus body (Vanilla: use 'this')
  editBox:SetScript("OnMouseDown", function() this:SetFocus() end)

  -- Tab → go back to the name
  editBox:SetScript("OnTabPressed", function()
  if UltimaMacrosFrameNameEdit then UltimaMacrosFrameNameEdit:SetFocus() end
    end)

  -- Esc → clear focus (Esc again closes via UISpecialFrames)
  editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)

  -- Now wire the scroll child (AFTER editBox exists)
  editScroll:SetScrollChild(editBox)

  -- If you click anywhere on the scrollframe background, focus the edit box
  editScroll:SetScript("OnMouseDown", function()
  if UltimaMacrosFrameEditBox then UltimaMacrosFrameEditBox:SetFocus() end
    end)

  UM_LocalUI.listScroll  = listScroll
  UM_LocalUI.listContent = listContent

  f:SetScript("OnShow", function()
    if UM_UI_RefreshList then UM_UI_RefreshList() end
    if UM_UI_UpdateCounter then UM_UI_UpdateCounter() end
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
