# Glo55 Window Manager - TODO List

## Phase 1: Foundation and Basic Structure (1/4 complete)

### 1.1 Project Setup
- [x] Create main.v as the entry point with basic main() function
- [x] Create directory structure: x11/ and glo55/
- [x] Create placeholder files for all major components
- [x] Create v.mod file with module configuration

### 1.2 Basic X11 Integration
- [x] Define core X11 types (Client, Atom, X11Color, ScreenRect)
- [x] Implement X11 connection handling
- [x] Update main() to attempt X11 connection
- [x] Add basic logging using V's log module

### 1.3 Core Data Structures
- [ ] Define WindowManager struct with monitors, layouts, draw
- [ ] Define Monitor, Workspace, WindowSpec, Window structs
- [ ] Define Layout interface and WindowUpdate struct
- [ ] Define TilingLayout struct

### 1.4 Basic Event Handling
- [ ] Define basic X11 event types
- [ ] Create event dispatch system
- [ ] Add basic event handler methods to WindowManager
- [ ] Update main() with event loop

## Phase 2: Configuration System (0/4 complete)

### 2.1 TOML Parsing Infrastructure
- [ ] Add TOML dependency to v.mod
- [ ] Create basic TOML loading utilities
- [ ] Implement file path resolution
- [ ] Add configuration testing

### 2.2 Configuration Structure
- [ ] Define Config struct with monitors and keybindings
- [ ] Implement Config.from_toml() static method
- [ ] Add keybinding parsing and validation
- [ ] Add workspace configuration and validation

### 2.3 Theme System Foundation
- [ ] Define Theme struct with vars, windows, toolbars
- [ ] Implement Theme.from_toml() static method
- [ ] Add variable substitution system
- [ ] Add state-based variable support

### 2.4 Element System
- [ ] Define ElementType enum and Element struct
- [ ] Implement Element.from_toml() static method
- [ ] Add positioning system with edge-relative coordinates
- [ ] Add element type validation

## Phase 3: Layout System (0/4 complete)

### 3.1 Layout Interface
- [ ] Complete Layout interface definition
- [ ] Add WindowUpdate handling and validation
- [ ] Create layout testing infrastructure
- [ ] Integrate layout with Workspace

### 3.2 TilingLayout Implementation
- [ ] Complete TilingLayout struct implementation
- [ ] Implement arrange() method with master/stack logic
- [ ] Add layout calculations for master and stack panes
- [ ] Handle edge cases and configuration changes

### 3.3 Layout Testing
- [ ] Create comprehensive unit tests for layout
- [ ] Add edge case testing
- [ ] Implement performance testing
- [ ] Add integration tests

### 3.4 Workspace Integration
- [ ] Implement Workspace.add() and Workspace.remove()
- [ ] Add window management and ordering
- [ ] Integrate with WindowManager for multi-monitor
- [ ] Add workspace testing

## Phase 4: Window Management Core (0/4 complete)

### 4.1 Window Lifecycle
- [ ] Implement WindowManager.on_window_open()
- [ ] Implement WindowManager.on_window_close()
- [ ] Add window property management
- [ ] Add window lifecycle testing

### 4.2 Focus Management
- [ ] Implement focus follows mouse behavior
- [ ] Implement focus navigation (up/down/left/right)
- [ ] Implement window movement within layout
- [ ] Add focus testing

### 4.3 Multi-Monitor Support
- [ ] Implement monitor detection and configuration
- [ ] Add per-monitor workspace management
- [ ] Implement monitor switching and routing
- [ ] Add multi-monitor testing

### 4.4 Workspace Operations
- [ ] Implement workspace switching (Mod+1-0)
- [ ] Implement window movement between workspaces (Mod+Shift+1-0)
- [ ] Add workspace management and persistence
- [ ] Add workspace testing

## Phase 5: Drawing and Rendering (0/4 complete)

### 5.1 Drawing Context
- [ ] Define DrawingContext struct
- [ ] Implement DrawingContext.create()
- [ ] Add font management with XftFontOpenName
- [ ] Add color conversion and drawing utilities

### 5.2 Element Rendering
- [ ] Implement solid element rendering
- [ ] Implement gradient element rendering
- [ ] Implement image and pattern rendering
- [ ] Implement text element rendering with UTF-8

### 5.3 Theme Application
- [ ] Implement variable substitution system
- [ ] Add state-based variable overrides
- [ ] Implement theme scaling rules
- [ ] Create theme rendering pipeline

### 5.4 Window Decoration
- [ ] Implement window background rendering
- [ ] Implement window border rendering
- [ ] Add toolbar rendering
- [ ] Add decoration testing

## Phase 6: Event Handling and Integration (0/4 complete)

### 6.1 Key Binding System
- [ ] Implement key combination parsing
- [ ] Add command execution system
- [ ] Implement all keybinding commands
- [ ] Add keybinding testing

### 6.2 Mouse Interaction
- [ ] Implement mouse click handling
- [ ] Add hover state detection
- [ ] Implement element actions (close, minimize, maximize)
- [ ] Add mouse interaction testing

### 6.3 Application Launching
- [ ] Implement exec command support
- [ ] Add terminal launching (Mod+Shift+Enter)
- [ ] Add process management
- [ ] Add application testing

### 6.4 Final Integration
- [ ] Implement complete initialization sequence
- [ ] Add comprehensive error handling
- [ ] Implement performance optimizations
- [ ] Add final testing

## Phase 7: Testing and Polish (0/4 complete)

### 7.1 Unit Testing
- [ ] Create test files for all major components
- [ ] Implement unit tests for core logic
- [ ] Add test utilities and helpers
- [ ] Implement comprehensive test coverage

### 7.2 Functional Testing
- [ ] Create functional test scenarios
- [ ] Implement test automation
- [ ] Add integration testing
- [ ] Create user acceptance tests

### 7.3 Error Handling
- [ ] Add error handling throughout
- [ ] Implement error recovery
- [ ] Add user-friendly error messages
- [ ] Create error testing

### 7.4 Documentation and Examples
- [ ] Write user documentation
- [ ] Create example configurations
- [ ] Add developer documentation
- [ ] Create supplementary materials

## Current Focus: Phase 1.1 - Project Setup
## Next Priority: Phase 1.2 - Basic X11 Integration
## Recent Wins: None yet

## Overall Progress: 0% complete (0/28 total tasks)

## Task Sizing Guide
Each task is designed to be implemented in a single development session with clear success criteria. Tasks align with testing boundaries and deliver working functionality that can be demonstrated.