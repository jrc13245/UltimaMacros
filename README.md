# UltimaMacros

A lightweight, self-contained macro system for **World of Warcraft 1.12.1**.  
Provides its own macro storage (up to **7000 characters** per macro) and an in-game editor with per-character or account-wide scope.

UltimaMacros:

- Stores macros in its own SavedVariables.
- Lets you drag macros directly to your action bars.
- Refreshes icons, names, and tooltips immediately when you save or edit a macro.
- Offers a modernized editor with character count and simple focus/keyboard navigation.
- Any icon from your spells, gear, or blizzard macros can be seen in the icon picker grid.

---

## ✨ Features

- **Separate macro storage** (doesn’t count against Blizzard’s macro limits).
- **Longer macros**: up to 7000 characters.
- **Per-character or account-wide** macros (toggle in the UI).
- **Drag & drop action mapping** — place any UltimaMacro onto your action bars.
- **Dynamic icon & tooltip updates** when you edit or save a macro (no UI reload needed).
- **Friendly editor** with:
  - Clickable name and body fields
  - Tab/Enter navigation
  - Esc to clear focus (press Esc again to close the window)
  - Live character counter
  - Grid-style icon picker with access to icons from your gear, spells and blizzard macros
  
---

## ⚙️ Installation

1. Download or copy the `UltimaMacros` folder into your WoW AddOns directory:

World of Warcraft\Interface\AddOns\

2. Launch the game and enable **UltimaMacros** on the AddOns screen.
3. Saved data is stored in:

WTF\Account<ACCOUNT>\SavedVariables\UltimaMacros.lua


---

![alt text](https://github.com/jrc13245/UltimaMacros/raw/main/example/UltimaMacrosExample.png)

---

## 🚀 Usage

### Opening the Editor
Use any of these methods:

/umacro
/umacros

Or click the **UltimaMacros** button on Blizzard's default macro frame.

### Creating Macros
1. Click **New** to create a new macro.
2. Toggle the **Char/Acct** checkbox to set per-character or account-wide scope.
3. Enter a **name** in the top box.
4. Write your macro body in the large bottom editor box.
5. Click the macro icon to select from available icons.

> The editor supports any standard Blizzard macro commands and commands from any installed addons.

### Placing on Action Bars
- Drag a macro from the **left-hand list** onto any action bar slot.
- **Swap**: Dragging a macro onto a slot with another UltimaMacro will swap them (the old one goes on your cursor).

### Editing Macros
- Click a macro name in the list to load it into the editor.
- Change text or icon, then click **Save**.
- Buttons on your bars update **immediately**.

### Running Macros

/umacro run <name>

Executes a saved macro directly by name.

### Managing Macros

/umacro list -- List all macros
/umacro del <name> -- Delete a macro
/umacro new <name> -- Create new per-character macro
/umacro newa <name> -- Create new account-wide macro


---

## 🖥️ Editor Shortcuts

- **Click** name field → edit macro name.
- **Click** body field → edit macro text.
- **Tab / Enter** in the name field → jump to the body field.
- **Tab** in the body field → jump back to the name field.
- **Esc** clears focus; press **Esc again** to close the window.
- Character counter shows `used/7000` characters.

---

## 🧩 Known Limitations

- Macros made with UltimaMacros cannot be saved the normal way that some actionbar addons are capable of.
- UMacros can be overwritten in their slot by placing a Blizzard action onto the same slot. Umacros cannot be placed where a Blizzard action already exists.
- Macros made here do **not** appear in the default Blizzard macro UI.
- Action buttons use the chosen icon or Blizzard’s standard fallback if the macro can’t resolve an automatic texture.
- Only the UltimaMacros editor can create and edit these macros.
- Icon Picker only includes icons from spells, abilities, gear, and blizzard macros.

---

## 📜 Changelog

### v1.0.2
- First release with:
  - Actionbar slot protections to prevent multiple actions on the same slot

### v1.0.1
- First release with:
  - Icon Grid Picker

### v1.0.0
- First release with:
  - Separate per-character/account macro storage
  - New editor UI with name/body fields
  - Drag-and-drop to action bars
  - Immediate icon/tooltip refresh
  - Esc/Tab/Enter keyboard handling
