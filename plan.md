# Glo55 Window Manager - Implementation Plan with Agent Prompts

## Overview
This plan provides detailed, step-by-step implementation prompts for building Glo55. Each prompt is designed to be given to a development agent and includes context, requirements, and success criteria.

## Phase 1: Foundation and Basic Structure

### 1.1 Project Setup
```
Create the basic V module structure for Glo55 window manager:

1. Create main.v as the entry point with a basic main() function
2. Create the directory structure: x11/ and glo55/
3. Create placeholder files: x11/client.v, x11/events.v, x11/screen.v
4. Create placeholder files: glo55/config.v, glo55/drawing.v, glo55/element.v, glo55/layout.v, glo55/theme.v, glo55/window_manager.v, glo55/workspace.v
5. Create a basic v.mod file with module configuration

The main() function should:
- Print "Glo55 Window Manager starting..."
- Have basic error handling structure
- Be ready for X11 connection initialization

Success criteria:
- All files exist in correct locations
- v mod shows no syntax errors
- Running the program prints the startup message
- Directory structure matches the specification exactly
```

### 1.2 Basic X11 Integration
```
Implement basic X11 connection and type definitions:

1. In x11/client.v, define the core X11 types:
   - type Client = u64
   - type Atom = u64  
   - type X11Color = u64
   - struct ScreenRect { x int, y int, width u32, height u32 }

2. Create basic X11 connection handling:
   - Add X11 display connection function
   - Implement basic error handling for connection failures
   - Add display closing/cleanup function

3. In main.v, update main() to:
   - Attempt X11 connection
   - Print success/failure message
   - Clean up connection before exit

4. Add basic logging using V's log module for connection status

Requirements:
- Use V's built-in log module for all logging
- Handle connection errors gracefully with log.error
- Ensure proper resource cleanup
- Follow V language conventions for error handling

Success criteria:
- Program successfully connects to X11 display
- Connection errors are logged and handled gracefully
- Resources are properly cleaned up
- No memory leaks or resource issues
```

### 1.3 Core Data Structures
```
Define the core data structures for window management:

1. In glo55/window_manager.v:
   - Define struct WindowManager with monitors []Monitor, layouts []Layout, draw DrawingContext
   - Add mut properties for windows []Window and other global state
   - Define type MonitorId = int

2. In glo55/workspace.v:
   - Define struct Monitor with workspaces []Workspace, geometry ScreenRect, work_area ScreenRect
   - Define struct Workspace with title string, layout &Layout, mut windows []WindowSpec
   - Define struct WindowSpec with info &Window, mut rect ScreenRect

3. In glo55/window_manager.v:
   - Define struct Window with id Client, mut title string, mut flags u32
   - Add basic window management methods

4. In glo55/layout.v:
   - Define interface Layout with arrange method
   - Define struct WindowUpdate with window_index int, target_rect ScreenRect
   - Define struct TilingLayout with master_ratio f32, gap_width u32, border_width u32

Requirements:
- All structs match the specification exactly
- Use appropriate mut modifiers for mutable fields
- Include basic documentation comments for each struct
- Ensure type safety with proper field types

Success criteria:
- All core data structures are defined
- V compiler validates all struct definitions
- Types match the interface specification
- Basic mutability is correctly configured
```

### 1.4 Basic Event Handling
```
Implement basic event handling infrastructure:

1. In x11/events.v:
   - Define basic X11 event types as enums
   - Create event dispatch system with basic routing
   - Implement event loop skeleton

2. In glo55/window_manager.v:
   - Add basic event handler methods: on_window_open, on_window_close, on_key_press, on_motion_notify
   - Implement basic event routing logic
   - Add logging for all event handling

3. In main.v:
   - Replace basic main() with event loop
   - Add event dispatch to WindowManager
   - Implement graceful shutdown handling

4. Add basic event testing:
   - Log all received events
   - Implement basic event filtering
   - Add performance monitoring for event processing

Requirements:
- Event loop runs continuously until shutdown
- All events are logged for debugging
- Event handlers have proper error handling
- No event processing bottlenecks

Success criteria:
- Event loop runs without crashing
- Events are properly logged and routed
- Basic window manager operations respond to events
- Performance is acceptable for basic usage
```

## Phase 2: Configuration System

### 2.1 TOML Parsing Infrastructure
```
Add TOML parsing capabilities for configuration files:

1. Add TOML dependency to v.mod file
2. Create basic TOML loading utilities in glo55/config.v:
   - Function to load TOML file with error handling
   - Basic TOML validation and error reporting
   - Utility functions for accessing TOML values safely

3. Implement file path resolution:
   - Support for relative and absolute paths
   - Default config file locations (~/config/glo55/, /etc/glo55/, ./)
   - Error handling for missing files

4. Add configuration testing:
   - Test loading valid TOML files
   - Test error handling for malformed files
   - Test file path resolution

Requirements:
- Use V's TOML parsing module
- Handle all TOML parsing errors gracefully
- Provide clear error messages for configuration issues
- Support multiple config file locations

Success criteria:
- TOML files load successfully
- Parsing errors are caught and reported clearly
- File path resolution works correctly
- Configuration loading is robust and user-friendly
```

### 2.2 Configuration Structure
```
Implement the main configuration structure:

1. In glo55/config.v:
   - Define struct Config with monitors []MonitorConfig, keybindings map[string]string
   - Define struct MonitorConfig with workspaces []string
   - Implement Config.from_toml() static method
   - Add methods for accessing keyboard shortcuts and workspace names

2. Implement keybinding parsing:
   - Parse key combinations like "Mod+1", "Mod+Shift+Enter"
   - Support for modifier keys: Mod, Shift, Control, Alt
   - Map keybindings to commands like "workspace 1", "exec kitty"

3. Add workspace configuration:
   - Support per-monitor workspace definitions
   - Handle workspace name validation
   - Support up to 10 workspaces per monitor

4. Add configuration validation:
   - Validate keybinding syntax
   - Check workspace name uniqueness per monitor
   - Ensure required configuration sections exist

Requirements:
- Configuration matches the TOML structure in the specification
- Keybindings are parsed and validated correctly
- Workspace configuration supports multi-monitor setups
- All validation errors are clearly reported

Success criteria:
- Config.toml files load and validate correctly
- Keybindings are parsed into internal representation
- Workspace configuration supports multiple monitors
- Configuration errors are caught and reported usefully
```

### 2.3 Theme System Foundation
```
Implement the theme system foundation:

1. In glo55/theme.v:
   - Define struct Theme with vars map[string]string, windows []WindowTheme, toolbars []ToolbarTheme
   - Define struct WindowTheme with border_width u32, window_gap u32, focus_behavior string
   - Define struct ToolbarTheme with monitor int, border_width u32
   - Implement Theme.from_toml() static method

2. Implement variable substitution system:
   - Parse variables with $variable_name syntax
   - Support recursive variable references
   - Handle missing variables gracefully

3. Add state-based variable support:
   - Parse state sections: [windows.focused], [windows.hover], etc.
   - Implement variable inheritance from [vars] section
   - Add state variable priority handling

4. Create theme loading and validation:
   - Load theme.toml files with error handling
   - Validate theme structure and required fields
   - Support multiple theme files for switching

Requirements:
- Theme structure matches the specification exactly
- Variable substitution works with all string properties
- State-based variables override global variables correctly
- Theme loading is robust and user-friendly

Success criteria:
- Theme.toml files load and validate correctly
- Variable substitution works for all element properties
- State-based variables override globals appropriately
- Theme switching works by changing config file
```

### 2.4 Element System
```
Implement the element rendering system:

1. In glo55/element.v:
   - Define enum ElementType { solid, gradient, image, pattern, text }
   - Define struct Element with type ElementType, properties map[string]string
   - Define struct ThemeArea with positioning information
   - Implement Element.from_toml() static method

2. Implement positioning system:
   - Parse edge-relative coordinates: { edge = "left", offset = 0 }
   - Support all edge types: left, top, right, bottom
   - Convert ThemeArea to ScreenRect with proper scaling

3. Add element type validation:
   - Validate required properties for each element type
   - Check color format for solid/gradient elements
   - Validate image paths and font specifications

4. Create element rendering interface:
   - Define render method signature for each element type
   - Add element property accessors
   - Implement element validation before rendering

Requirements:
- All 5 element types are supported with correct properties
- Positioning system supports edge-relative coordinates
- Element validation catches configuration errors early
- ThemeArea to ScreenRect conversion works correctly

Success criteria:
- All element types parse correctly from TOML
- Positioning calculations work for all edge combinations
- Element validation catches common configuration errors
- Element system is ready for integration with drawing context
```

## Phase 3: Layout System

### 3.1 Layout Interface
```
Implement the layout interface and basic infrastructure:

1. In glo55/layout.v:
   - Complete the Layout interface definition:
     interface Layout {
         arrange(windows []WindowSpec, work_area ScreenRect) []WindowUpdate
     }
   - Add layout validation methods
   - Create layout factory for creating different layout types

2. Implement WindowUpdate handling:
   - Add validation for window_index bounds
   - Implement ScreenRect intersection checking
   - Add update application logic

3. Create layout testing infrastructure:
   - Add test utilities for creating mock window configurations
   - Implement layout result validation
   - Add performance measurement for layout calculations

4. Integrate with Workspace:
   - Update Workspace to use Layout interface
   - Add layout change notification system
   - Implement layout arrangement triggering

Requirements:
- Layout interface is clean and extensible
- WindowUpdate validation prevents crashes
- Layout testing supports comprehensive validation
- Integration with Workspace is seamless

Success criteria:
- Layout interface compiles without errors
- WindowUpdate validation works correctly
- Layout can be triggered from Workspace
- Basic layout testing infrastructure is in place
```

### 3.2 TilingLayout Implementation
```
Implement the master/stack tiling layout algorithm:

1. In glo55/layout.v:
   - Complete TilingLayout struct implementation
   - Implement arrange() method with master/stack logic:
     - Master window takes left portion (master_ratio of width)
     - Stack windows share remaining space vertically
     - Apply gap_width between windows
     - Apply border_width to each window

2. Add layout calculations:
   - Calculate master pane dimensions
   - Calculate stack pane dimensions
   - Distribute stack windows evenly
   - Apply gaps and borders correctly

3. Handle edge cases:
   - Single window (full work area)
   - Two windows (master + one stack)
   - Many windows (master + multiple stack)
   - Windows that don't fit (minimum size handling)

4. Add layout configuration:
   - Support runtime configuration changes
   - Validate configuration values
   - Add sensible defaults

Requirements:
- Master/stack layout matches DWM behavior
- Gap and border width application is correct
- Edge cases are handled gracefully
- Configuration changes work dynamically

Success criteria:
- Layout arranges windows correctly for all window counts
- Gaps and borders are applied properly
- Master ratio adjustments work correctly
- Layout handles edge cases without crashing
```

### 3.3 Layout Testing
```
Create comprehensive tests for the layout system:

1. Create test file glo55/layout_test.v:
   - Test single window layout (full work area)
   - Test two window layout (master + stack)
   - Test many window layout (master + multiple stack)
   - Test gap and border width application

2. Add edge case testing:
   - Test zero windows (empty layout)
   - Test very small work area
   - Test extreme master ratio values
   - Test large gap/border values

3. Implement performance testing:
   - Measure layout calculation time
   - Test with many windows (50+)
   - Verify no memory leaks
   - Check for layout thrashing

4. Add integration tests:
   - Test layout changes when windows are added/removed
   - Test configuration changes
   - Test workspace integration
   - Test multi-monitor scenarios

Requirements:
- All layout scenarios are tested
- Edge cases are covered
- Performance is acceptable
- Integration with other components works

Success criteria:
- All unit tests pass
- Edge cases are handled correctly
- Performance is within acceptable limits
- Integration tests validate real-world usage
```

### 3.4 Workspace Integration
```
Integrate layout system with workspace management:

1. In glo55/workspace.v:
   - Implement Workspace.add() method:
     - Add window to workspace window list
     - Force new windows to master position (configurable)
     - Trigger layout arrangement
     - Handle floating windows specially

   - Implement Workspace.remove() method:
     - Remove window from workspace
     - Trigger layout arrangement
     - Handle cleanup and state updates

2. Add window management:
   - Implement window ordering (move up/down in list)
   - Add window focus tracking
   - Handle window state changes
   - Support window movement between workspaces

3. Integrate with WindowManager:
   - Route window operations to correct workspace
   - Handle multi-monitor workspace routing
   - Implement workspace switching
   - Add workspace persistence

4. Add workspace testing:
   - Test window addition and removal
   - Test layout triggering
   - Test workspace switching
   - Test multi-monitor scenarios

Requirements:
- Workspace manages windows correctly
- Layout is triggered on all relevant changes
- Multi-monitor workspace isolation works
- Window operations are atomic and consistent

Success criteria:
- Windows are added/removed correctly
- Layout updates happen automatically
- Workspace switching works seamlessly
- Multi-monitor isolation is maintained
```

## Phase 4: Window Management Core

### 4.1 Window Lifecycle
```
Implement complete window lifecycle management:

1. In glo55/window_manager.v:
   - Implement WindowManager.on_window_open():
     - Create Window struct from X11 client
     - Extract initial window properties (title, geometry)
     - Route to active monitor's workspace
     - Apply initial layout

   - Implement WindowManager.on_window_close():
     - Find window in internal list
     - Remove from workspace
     - Cleanup resources
     - Trigger layout update

2. Add window property management:
   - Track window title changes
   - Handle window state changes
   - Manage window flags (visible, floating)
   - Support window property queries

3. Implement window operations:
   - Window focus management
   - Window raising/lowering
   - Window state queries
   - Window decoration updates

4. Add window lifecycle testing:
   - Test window creation and destruction
   - Test property change handling
   - Test focus management
   - Test state persistence

Requirements:
- Window lifecycle is complete and robust
- Property changes are handled correctly
- Focus management works as expected
- Resource cleanup is thorough

Success criteria:
- Windows are managed from creation to destruction
- Property changes update window state correctly
- Focus follows mouse behavior works
- No resource leaks or crashes
```

### 4.2 Focus Management
```
Implement focus management and navigation:

1. In glo55/window_manager.v:
   - Implement focus follows mouse:
     - Track mouse position across monitors
     - Update focus on mouse movement
     - Handle window boundaries
     - Support focus prevention

   - Implement focus navigation:
     - Navigate up/down/left/right in layout
     - Handle layout boundaries
     - Support wrapping behavior
     - Add visual focus indicators

2. Add keyboard focus handling:
   - Process key press events for navigation
   - Implement Mod+j/k/h/l for focus movement
   - Handle focus changes with layout updates
   - Support focus history

3. Implement window movement:
   - Move windows up/down in layout order
   - Handle Mod+Shift+j/k/h/l keybindings
   - Update layout after movement
     - Support movement between workspaces

4. Add focus testing:
   - Test mouse focus following
   - Test keyboard navigation
   - Test window movement
   - Test focus persistence

Requirements:
- Focus follows mouse works correctly
- Keyboard navigation is intuitive
- Window movement updates layout properly
- Focus behavior is consistent and predictable

Success criteria:
- Mouse movement updates focus correctly
- Keyboard navigation works in all directions
- Window movement changes layout order
- Focus behavior matches user expectations
```

### 4.3 Multi-Monitor Support
```
Implement complete multi-monitor support:

1. In glo55/window_manager.v:
   - Implement monitor detection:
     - Query X11 for monitor information
     - Handle monitor hotplugging
     - Support different monitor arrangements
     - Calculate work areas for each monitor

   - Implement per-monitor workspaces:
     - Create workspace arrays per monitor
     - Handle workspace switching per monitor
     - Support different workspace counts per monitor
     - Manage window visibility across monitors

2. Add monitor switching:
   - Track active monitor based on mouse position
   - Handle monitor focus changes
   - Support workspace isolation between monitors
   - Implement monitor-specific configuration

3. Implement multi-monitor window management:
   - Route windows to correct monitor
     - Handle window movement between monitors
     - Support monitor-specific layouts
     - Manage cross-monitor window visibility

4. Add multi-monitor testing:
   - Test monitor detection and configuration
   - Test workspace isolation
   - Test window movement between monitors
   - Test monitor hotplugging

Requirements:
- Multi-monitor detection works correctly
- Workspace isolation is maintained
- Window management works across monitors
- Configuration supports per-monitor settings

Success criteria:
- Multiple monitors are detected and configured
- Workspaces are isolated per monitor
- Windows can move between monitors
- Monitor-specific settings work correctly
```

### 4.4 Workspace Operations
```
Implement workspace switching and management:

1. In glo55/window_manager.v:
   - Implement workspace switching:
     - Handle Mod+1 through Mod+0 keybindings
     - Switch workspace on active monitor
     - Update window visibility
     - Support workspace name display

   - Implement window movement:
     - Handle Mod+Shift+1 through Mod+Shift+0
     - Move windows between workspaces
     - Update layout on both workspaces
     - Handle workspace persistence

2. Add workspace management:
   - Create workspace name system
   - Support workspace configuration
   - Handle workspace state persistence
   - Implement workspace indicators

3. Implement workspace operations:
   - Workspace creation and deletion
   - Workspace reordering
   - Workspace configuration changes
   - Workspace state queries

4. Add workspace testing:
   - Test workspace switching
   - Test window movement between workspaces
   - Test workspace persistence
     - Test workspace configuration

Requirements:
- Workspace switching works with keybindings
- Window movement between workspaces works
- Workspace state is maintained correctly
- Workspace configuration is flexible

Success criteria:
- Mod+1-0 switches workspaces correctly
- Mod+Shift+1-0 moves windows correctly
- Workspace state persists across switches
- Workspace names are displayed properly
```

## Phase 5: Drawing and Rendering

### 5.1 Drawing Context
```
Implement the drawing context for X11 graphics:

1. In glo55/drawing.v:
   - Define DrawingContext struct:
     - screen ScreenRect
     - root Client
     - graphics_context X11 graphics context
     - fonts []Font
     - colors map[string]X11Color

   - Implement DrawingContext.create():
     - Create X11 graphics context
     - Set up default drawing attributes
     - Initialize color mapping
     - Return configured context

2. Add font management:
   - Implement load_fonts() using XftFontOpenName
   - Support multiple font specifications
   - Handle font loading errors
   - Add font caching

3. Implement color conversion:
   - Convert hex colors to X11Color
   - Support alpha channel handling
   - Add color caching
   - Handle color conversion errors

4. Add drawing utilities:
   - Basic shape drawing (rectangles, lines)
   - Text rendering with UTF-8 support
   - Image rendering preparation
   - Clipping and masking support

Requirements:
- Drawing context manages X11 resources correctly
- Font loading works with XftFontOpenName
- Color conversion handles all formats correctly
- Drawing utilities are comprehensive

Success criteria:
- Drawing context creates successfully
- Fonts load without errors
- Color conversion works for all formats
- Basic drawing operations work
```

### 5.2 Element Rendering
```
Implement rendering for all 5 element types:

1. In glo55/element.v:
   - Implement solid element rendering:
     - Fill rectangle with solid color
     - Handle alpha blending
     - Support color conversion
     - Apply positioning correctly

   - Implement gradient element rendering:
     - Create linear gradients between two colors
     - Support direction rotation (0-360 degrees)
     - Handle gradient stops
     - Apply positioning correctly

2. Add image and pattern rendering:
   - Implement image element rendering:
     - Load PNG images using stbi
     - Handle image scaling and positioning
     - Support transparency
     - Cache loaded images

   - Implement pattern element rendering:
     - Tile images across area
     - Handle pattern repetition
     - Support pattern offsets
     - Apply positioning correctly

3. Implement text element rendering:
   - Render UTF-8 text with XftDrawStringUtf8
   - Support template variables ($title, $workspace, $time)
   - Handle font selection and sizing
   - Apply text positioning and alignment

4. Add element rendering testing:
   - Test each element type rendering
   - Test positioning calculations
   - Test template variable substitution
   - Test performance with many elements

Requirements:
- All 5 element types render correctly
- Positioning works for all edge combinations
- Template variables are substituted correctly
- Performance is acceptable for real-time usage

Success criteria:
- Solid colors render correctly
- Gradients render with proper direction
- Images and patterns display properly
- Text renders with correct fonts and variables
```

### 5.3 Theme Application
```
Implement theme application and variable substitution:

1. In glo55/theme.v:
   - Implement variable substitution system:
     - Parse $variable_name in all string properties
     - Support recursive variable references
     - Handle missing variables gracefully
     - Cache resolved variables

   - Implement state-based variable overrides:
     - Apply [windows.focused] variables when window is focused
     - Apply [windows.hover] variables when mouse hovers
     - Apply [windows.clicked] variables when clicked
     - Apply [windows.collapsed] variables when collapsed

2. Add theme scaling rules:
   - Implement Y-axis proportional scaling (relative to 600px)
   - Implement X-axis stretching (fill width)
   - Convert ThemeArea to ScreenRect
   - Handle different screen resolutions

3. Create theme rendering pipeline:
   - Resolve variables for current state
   - Convert positioning to screen coordinates
   - Render elements in correct order
   - Apply theme to windows and toolbars

4. Add theme testing:
   - Test variable substitution
   - Test state-based overrides
   - Test scaling calculations
   - Test theme switching

Requirements:
- Variable substitution works for all properties
- State-based overrides apply correctly
- Scaling rules work for all screen sizes
- Theme rendering is efficient and correct

Success criteria:
- Variables are substituted in all element properties
- State changes update theme correctly
- Scaling works for different resolutions
- Theme switching updates display immediately
```

### 5.4 Window Decoration
```
Implement window decoration and toolbar rendering:

1. In glo55/window_manager.v:
   - Implement window background rendering:
     - Apply window theme background
     - Handle window state variations
     - Support transparent backgrounds
     - Update on theme changes

   - Implement window border rendering:
     - Draw borders with theme colors
     - Handle border width variations
     - Support different border styles
     - Update on focus changes

2. Add toolbar rendering:
   - Create toolbar instances per monitor
   - Render toolbar elements in correct order
     - Handle toolbar state changes
     - Support toolbar interaction

3. Implement decoration updates:
   - Update decorations on window state changes
   - Handle theme switching
   - Support live theme updates
   - Manage decoration performance

4. Add decoration testing:
   - Test window background rendering
   - Test border rendering with different states
   - Test toolbar element rendering
   - Test decoration update performance

Requirements:
- Window decorations render correctly
- Borders reflect window state properly
- Toolbars display elements correctly
- Decoration updates are efficient

Success criteria:
- Window backgrounds match theme
- Borders change color on focus/hover
- Toolbars show workspace indicators
- Decoration performance is acceptable
```

## Phase 6: Event Handling and Integration

### 6.1 Key Binding System
```
Implement comprehensive key binding system:

1. In glo55/config.v:
   - Implement key combination parsing:
     - Parse modifier keys (Mod, Shift, Control, Alt)
     - Parse regular keys (letters, numbers, symbols)
     - Handle key combinations correctly
     - Support keybinding validation

   - Implement command execution:
     - Map keybindings to commands
     - Execute workspace switching commands
     - Execute window movement commands
     - Execute external application commands

2. Add keybinding management:
   - Load keybindings from configuration
   - Support runtime keybinding changes
   - Handle keybinding conflicts
   - Provide keybinding feedback

3. Implement keybinding commands:
     - Workspace switching (workspace 1-10)
     - Window movement (move_window_to_workspace 1-10)
     - Focus navigation (focus_up/down/left/right)
     - Window movement (move_up/down/left/right)
     - Application launching (exec <command>)

4. Add keybinding testing:
   - Test key combination parsing
   - Test command execution
   - Test keybinding conflicts
   - Test keybinding performance

Requirements:
- Key combinations parse correctly
- Commands execute as expected
- Keybinding conflicts are detected
- Performance is acceptable for real-time usage

Success criteria:
- Mod+1-0 switches workspaces
- Mod+Shift+1-0 moves windows
- Mod+j/k/h/l navigates focus
- Mod+Shift+j/k/h/l moves windows
- Mod+Shift+Enter launches terminal
```

### 6.2 Mouse Interaction
```
Implement mouse interaction and element actions:

1. In glo55/window_manager.v:
   - Implement mouse click handling:
     - Detect clicks on window elements
     - Route clicks to appropriate handlers
     - Handle click timing and double-clicks
     - Support click actions (close, minimize, maximize)

   - Implement hover state detection:
     - Track mouse position over elements
     - Update hover state correctly
     - Trigger hover theme changes
     - Handle hover transitions smoothly

2. Add element action system:
   - Implement close action
   - Implement minimize action
   - Implement maximize action
   - Support custom actions

3. Implement drag and drop:
   - Handle window dragging
     - Support window resizing
     - Manage drag state
     - Update layout during drag

4. Add mouse interaction testing:
   - Test click detection and routing
   - Test hover state changes
   - Test element actions
   - Test drag and drop functionality

Requirements:
- Mouse clicks are detected and routed correctly
- Hover states update theme appropriately
- Element actions work as expected
- Drag and drop is smooth and responsive

Success criteria:
- Clicking close buttons closes windows
- Hovering changes element appearance
- Dragging moves windows smoothly
- Mouse interaction is intuitive
```

### 6.3 Application Launching
```
Implement application launching and process management:

1. In glo55/window_manager.v:
   - Implement exec command support:
     - Parse exec commands from keybindings
     - Spawn processes with proper environment
     - Handle process spawning errors
     - Support command arguments

   - Implement terminal launching:
     - Handle Mod+Shift+Enter specially
     - Launch terminal with default configuration
     - Support terminal command customization
     - Handle terminal launching errors

2. Add process management:
   - Track launched processes
   - Handle process termination
   - Support process cleanup
   - Manage process resources

3. Implement application integration:
   - Handle new application windows
     - Support application-specific configuration
     - Manage application lifecycle
     - Provide application feedback

4. Add application testing:
   - Test process spawning
   - Test terminal launching
   - Test command argument handling
   - Test error handling

Requirements:
- Commands execute with proper environment
- Terminal launching works reliably
- Process management is robust
- Error handling is user-friendly

Success criteria:
- Mod+Shift+Enter launches terminal
- Exec commands work with arguments
- Process errors are handled gracefully
- Application integration works smoothly
```

### 6.4 Final Integration
```
Complete the integration and polish the window manager:

1. In main.v:
   - Implement complete initialization sequence:
     - Connect to X11 display
     - Check for existing window manager
     - Load configuration and theme
     - Initialize window manager state
     - Set up event handlers
     - Draw initial interface

   - Implement graceful shutdown:
     - Cleanup all resources
     - Save state if needed
     - Handle shutdown signals
     - Exit cleanly

2. Add comprehensive error handling:
   - Handle X11 connection errors
   - Handle configuration loading errors
   - Handle theme loading errors
   - Handle runtime errors gracefully

3. Implement performance optimizations:
   - Optimize event loop performance
   - Optimize rendering performance
   - Reduce memory usage
   - Improve responsiveness

4. Add final testing:
   - Test complete initialization
   - Test graceful shutdown
   - Test error handling
   - Test performance under load

Requirements:
- Initialization sequence works reliably
- Shutdown is clean and complete
- Error handling is comprehensive
- Performance is optimized for real usage

Success criteria:
- Window manager starts and runs reliably
- Shutdown cleans up all resources
- Errors are handled gracefully
- Performance is acceptable for daily use
```

## Phase 7: Testing and Polish

### 7.1 Unit Testing
```
Create comprehensive unit tests for core logic:

1. Create test files for all major components:
   - glo55/config_test.v
   - glo55/theme_test.v
   - glo55/layout_test.v
   - glo55/workspace_test.v
   - glo55/window_manager_test.v

2. Implement unit tests for:
   - Configuration loading and validation
   - Theme variable substitution
   - Layout calculations and edge cases
   - Workspace management
   - Window lifecycle management

3. Add test utilities:
   - Mock objects for testing
   - Test data generation
   - Assertion helpers
   - Performance measurement

4. Implement test coverage:
   - Aim for high coverage of core logic
   - Test all error conditions
   - Test edge cases and boundary conditions
   - Test integration between components

Requirements:
- All core logic has unit tests
- Tests cover happy paths and error cases
- Test utilities make testing easier
- Coverage is comprehensive and meaningful

Success criteria:
- All unit tests pass
- Core logic is thoroughly tested
- Edge cases are covered
- Tests provide good feedback
```

### 7.2 Functional Testing
```
Create functional tests for end-to-end workflows:

1. Create functional test scenarios:
   - Complete window management workflow
   - Multi-monitor setup and usage
   - Theme switching and rendering
   - Keybinding functionality
   - Mouse interaction testing

2. Implement test automation:
   - Automated window creation and management
   - Automated keybinding testing
   - Automated theme testing
   - Performance testing automation

3. Add integration testing:
   - Test integration between all components
   - Test real-world usage scenarios
   - Test with actual applications
   - Test under various system conditions

4. Create user acceptance tests:
   - Test typical user workflows
   - Test with different configurations
   - Test with different themes
   - Test performance and responsiveness

Requirements:
- End-to-end workflows are tested
- Integration between components works
- Real-world usage scenarios work
- User acceptance criteria are met

Success criteria:
- All functional tests pass
- Integration works correctly
- Real-world usage works
- User acceptance is achieved
```

### 7.3 Error Handling
```
Implement comprehensive error handling:

1. Add error handling throughout:
   - Handle X11 errors gracefully
   - Handle configuration errors with clear messages
   - Handle theme loading errors
   - Handle runtime errors without crashing

2. Implement error recovery:
   - Recover from temporary failures
   - Provide fallback behavior
   - Maintain system stability
   - Allow continued operation after errors

3. Add user-friendly error messages:
   - Clear error descriptions
   - Suggested solutions
   - Error logging for debugging
   - User notification system

4. Create error testing:
   - Test error conditions
   - Test error recovery
   - Test error message clarity
   - Test system stability under errors

Requirements:
- All error conditions are handled
- Error recovery works correctly
- Error messages are user-friendly
- System remains stable under errors

Success criteria:
- Errors don't crash the window manager
- Error messages are clear and helpful
- System recovers from errors gracefully
- Error handling is comprehensive
```

### 7.4 Documentation and Examples
```
Create comprehensive documentation and examples:

1. Write user documentation:
   - Installation instructions
   - Configuration guide
   - Theme creation guide
   - Usage instructions
   - Troubleshooting guide

2. Create example configurations:
   - Basic config.toml example
   - Advanced config.toml example
   - Basic theme.toml example
   - Advanced theme.toml example
   - Multi-monitor configuration example

3. Add developer documentation:
   - API documentation
   - Architecture overview
   - Contribution guide
   - Testing guide
   - Release notes

4. Create supplementary materials:
   - Video tutorials
   - Screenshot gallery
   - Performance benchmarks
   - Community resources

Requirements:
- Documentation is comprehensive and clear
- Examples cover common use cases
- Developer documentation is complete
- Supplementary materials are helpful

Success criteria:
- Users can install and configure easily
- Examples work as documented
- Developers can contribute effectively
- Community resources are valuable
```

## Implementation Notes

### Agent Prompt Guidelines
Each prompt is designed to be:
- **Specific**: Clear, actionable tasks with well-defined scope
- **Contextual**: Includes necessary background and requirements
- **Testable**: Has clear success criteria that can be verified
- **Incremental**: Builds on previous work without breaking changes
- **Complete**: Provides all information needed for implementation

### Quality Assurance
- All code follows V language conventions
- Error handling is comprehensive and user-friendly
- Performance is monitored and optimized
- Testing is integrated throughout development

### Risk Management
- Complex systems are broken into manageable components
- Integration points are clearly defined and tested
- Error conditions are handled gracefully
- Performance bottlenecks are identified and addressed

This plan provides a complete roadmap for implementing Glo55 with clear, actionable prompts for each step of the development process.