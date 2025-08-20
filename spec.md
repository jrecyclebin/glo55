# Glo55 Window Manager Specification

## Overview

Glo55 is a tiling window manager for Linux X11 written in the V language. It features a master/stack layout similar to DWM with a unique styling system that supports image-based theming for windows and toolbars. The window manager is designed for personal use with a focus on visual customization through five different element types: solid colors, gradients, images, patterns, and text.

## Core Architecture

### Project Structure
```
glo55/
├── main.v              # Entry point with main() function
├── x11.v               # X11 bindings and integration
└── glo55/
    ├── config.v        # Configuration loading and management
    ├── theme.v         # Theme loading and element rendering
    ├── window_manager.v # Core window management logic
    └── workspace.v     # Workspace and monitor management
```

### Key Components

#### Main (main.v)
- Entry point with `main()` function
- Orchestrates initialization sequence
- Starts main event loop

#### X11 Integration (x11.v)
- Custom X11 bindings for V
- Handles X11 connection and event processing
- Provides low-level window operations

#### Configuration (glo55/config.v)
- `Config` struct with configuration data
- `Config.load()` static method for loading config.toml
- Methods for accessing keyboard shortcuts and workspace names

#### Theme System (glo55/theme.v)
- `Theme` struct with theme data and elements
- `Theme.load()` static method for loading theme.toml
- Element rendering methods for solid, gradient, image, pattern, and text types

#### Window Manager (glo55/window_manager.v)
- `WindowManager` struct containing all monitor and window state
- Core window management operations
- Integration with X11, config, and theme systems

#### Workspace Management (glo55/workspace.v)
- `Workspace` struct for per-monitor workspace definitions
- `Monitor` struct for multi-monitor support
- Window visibility and layout management

## Multi-Monitor Architecture

### Monitor Struct
Each monitor is independent and contains:
- Complete screen geometry
- Actual screen area available for tiled windows
- List of workspaces (number varies per monitor)
- Complete window list for all workspaces
- References to toolbar instances

### Workspace Behavior
- Workspaces are per-monitor (Monitor 1 might have 5 workspaces, Monitor 2 might have 2)
- Windows can belong to multiple workspaces
- When a workspace is shown, only its attached windows become visible
- Each workspace maintains its own master/stack layout ordering

## Configuration System

### File Structure
- **config.toml**: Main configuration file (keyboard shortcuts, workspace names)
- **theme.toml**: Theme configuration files (multiple, switchable)
- Theme switching: Edit config file and restart window manager

### Config.toml Structure
```toml
[monitor.0]
workspaces = ["main", "web", "code", "chat", "media"]

[monitor.1]
workspaces = ["terminal", "browser", "documents", "4", "5", "6", "7", "8", "9", "temp"]

[keybindings]
# Workspace switching
"Mod+1" = "workspace 1"
"Mod+2" = "workspace 2"
# ... etc

# Move window to workspace  
"Mod+Shift+1" = "move_window_to_workspace 1"
"Mod+Shift+2" = "move_window_to_workspace 2"
# ... etc

# Window focus navigation
"Mod+j" = "focus_down"
"Mod+k" = "focus_up" 
"Mod+h" = "focus_left"
"Mod+l" = "focus_right"

# Window movement
"Mod+Shift+j" = "move_down"
"Mod+Shift+k" = "move_up"
"Mod+Shift+h" = "move_left"
"Mod+Shift+l" = "move_right"

# Launch terminal
"Mod+Shift+Enter" = "exec kitty"
```

## Theme System

### Element Types
1. **Solid** - Solid color fill
2. **Gradient** - Linear gradient between fore/back colors
3. **Image** - Fixed-size image (PNG support via stbi module)
4. **Pattern** - Tiled image pattern
5. **Text** - Text content with template variables

### Common Element Properties
- **Positioning**: Rectangle with coordinates relative to area edges
  - Each coordinate (left, top, right, bottom) can be relative to any area edge
  - Fixed pixel values
- **Interaction**:
  - `action`: Optional clickable action (close, minimize, maximize)

### Color Properties (where applicable)
- `fore`: Foreground color (applies to solid, gradient, text elements)
- `back`: Background color (applies to solid, gradient, text elements - gradients use both colors)

### Element-Specific Properties
**Gradient Elements**:
- `direction`: Rotation in degrees (0° = left-to-right, 90° = top-to-bottom)

**Image/Pattern Elements**:
- `path`: Relative file path to source image

**Text Elements**:
- `content`: Text string with template variables
- `font`: Font name to use
- `size`: Font size in pixels
- Template variables: `$title` (window title), `$workspace` (current workspace name), `$time` (current time)

### Global Variables
- **Syntax**: `$variable_name` references values from `[vars]` section
- **Usage**: Can be used in any string property (colors, paths, text content)
- **Scope**: Available throughout the entire theme file

### State-Based Variables
- **Syntax**: `[window.focused]`, `[window.hover]`, `[window.clicked]`, `[window.collapsed]`
- **Toolbar Syntax**: `[toolbar.0.focused]`, `[toolbar.0.hover]`, `[toolbar.0.clicked]`, `[toolbar.0.collapsed]`
- **Purpose**: Override global variables when specific states are active
- **Inheritance**: State sections inherit from `[vars]` and can override individual variables
- **Priority**: State variables take precedence over global variables when the state is active

> **Important**: State-based variables are NOT elements. Elements can be named anything (e.g., `[window.background]`, `[window.my_custom_element]`), but state-based variables must use the reserved state keywords: `focused`, `hover`, `clicked`, `collapsed`.

### Theme.toml Structure
```toml
# Global variables that can be referenced throughout the theme
[vars]
primary_color = "#87ceeb"
secondary_color = "#4682b4"
background_color = "#2d2d2d"
text_color = "#ffffff"
close_icon_path = "icons/close.png"
pattern_path = "patterns/grid.png"

# Window state overrides
[window.focused]
primary_color = "#ffd700"
text_color = "#000000"

[window.hover]
primary_color = "#add8e6"

[window.clicked]
primary_color = "#ff6347"

[window.collapsed]
primary_color = "#808080"

# Toolbar state overrides
[toolbar.0.focused]
primary_color = "#ff69b4"

[toolbar.0.hover]
primary_color = "#dda0dd"

[toolbar.0.clicked]
primary_color = "#da70d6"

[window]
border_width = 2
window_gap = 4
focus_behavior = "follow_mouse"

[window.background]
type = "solid"
left = { edge = "left", offset = 0 }
top = { edge = "top", offset = 0 }
right = { edge = "right", offset = 0 }
bottom = { edge = "bottom", offset = 0 }
fore = "$background_color"
back = "$background_color"

[window.border_top]
type = "gradient"
left = { edge = "left", offset = 0 }
top = { edge = "top", offset = 0 }
right = { edge = "right", offset = 0 }
bottom = { edge = "top", offset = 2 }
fore = "$primary_color"
back = "$secondary_color"
direction = 90

[toolbar.0]
monitor = 0
border_width = 1

[toolbar.0.workspace_indicator]
type = "text"
left = { edge = "left", offset = 10 }
top = { edge = "top", offset = 4 }
right = { edge = "left", offset = 100 }
bottom = { edge = "bottom", offset = 4 }
fore = "$primary_color"
back = "#00000000"
content = "Workspace: $workspace"
font = "monospace"
size = 10

[toolbar.1]
monitor = 1
border_width = 1

[toolbar.1.clock]
type = "text"
left = { edge = "right", offset = -100 }
top = { edge = "top", offset = 4 }
right = { edge = "right", offset = -10 }
bottom = { edge = "bottom", offset = 4 }
fore = "$text_color"
back = "#00000000"
content = "$time"
font = "monospace"
size = 10
```

## Core Functionality

### Window Management
- **Layout**: Master/stack tiling layout only
- **Focus**: "Focus follows mouse movement" (no configuration)
- **States**: Always tiled (no minimize/maximize/fullscreen)
- **Operations**:
  - Window focus navigation (up/down/left/right)
  - Window movement within layout (up/down/left/right)

### Workspace Management
- **Count**: Up to 10 workspaces per monitor
- **Switching**: Key bindings (Mod+1 through Mod+0)
- **Window Moving**: Key bindings (Mod+Shift+1 through Mod+Shift+0)
- **Indicators**: Visual and keyboard-based workspace switching
- **Scope**: Key bindings operate on currently focused monitor

### Application Launching
- **Terminal**: Mod+Shift+Enter launches kitty
- **General**: Support for "exec" commands in key bindings

## Technical Implementation

### Dependencies
- **X11**: Custom binding implementation
- **Image Loading**: stbi module for V (PNG support only)
- **Configuration**: TOML parsing
- **Logging**: V's built-in `log` module (log.info, log.error)

### Event Handling
- **Processing**: Single main event loop
- **Routing**: Component-specific event handlers
- **Event Types**: Key presses, window creation/destruction, window focus, mouse movement, property changes

### Error Handling
- **Logging**: Use `log.error` for all errors
- **Recovery**: Exit on critical failures (X11 connection, config loading)
- **Application Issues**: No special handling for application-specific problems

### Initialization Sequence
1. Connect to X11 display
2. Check if another window manager is running
3. Load configuration (config.toml)
4. Load theme (theme.toml) and associated resources (fonts, images)
5. Build WindowManager struct from display information
6. Initialize cursor
7. Draw toolbars and window decorations
8. Begin handling events

## Integration Layers (External Dependencies)

### X11 Integration
- **Purpose**: Low-level window system interaction
- **Testing Strategy**: No unit tests - verify through functional testing
- **Risk Area**: Window creation, focus management, event routing

### Image Loading (stbi module)
- **Purpose**: PNG image loading for theming
- **Testing Strategy**: No unit tests - verify through theme rendering
- **Risk Area**: Image file format handling, memory management

### TOML Configuration Parsing
- **Purpose**: Configuration and theme file parsing
- **Testing Strategy**: No unit tests - verify through config/theme loading
- **Risk Area**: File format validation, type conversion

## Core Logic (Test Coverage Required)

### Layout Management
- Master/stack layout calculations
- Window positioning and sizing
- Gap and border width application

### Window Management Operations
- Focus navigation logic
- Window movement within layout
- Workspace window visibility

### Theme Rendering
- Element positioning calculations
- Color and gradient rendering
- Text rendering with variables
- Image and pattern tiling

### Configuration Management
- Key binding parsing and execution
- Workspace name management
- Theme switching logic

### Event Processing
- Event routing to appropriate handlers
- Key combination handling
- Window state synchronization

## Functional Testing Notes

The following areas should be verified through functional testing rather than unit tests:

1. **X11 Integration**
   - Window creation and management
   - Focus behavior verification
   - Event processing accuracy
   - Multi-monitor detection and handling

2. **Image Loading and Rendering**
   - PNG image loading from theme files
   - Image positioning and scaling
   - Pattern tiling functionality
   - Transparency handling

3. **Configuration Loading**
   - TOML file parsing correctness
   - Key binding functionality
   - Theme switching behavior
   - Error handling for malformed files

4. **End-to-End Workflow**
   - Complete initialization sequence
   - Window management operations
   - Workspace switching and window movement
   - Theme rendering and visual appearance