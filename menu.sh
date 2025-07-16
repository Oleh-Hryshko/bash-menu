#!/bin/bash

# Script: menu.sh
#
# This Bash script provides a dynamic, interactive command-line interface (CLI) menu system. It allows users to navigate
# through various options, execute commands, and manage persistent variables. The menu structure is built dynamically
# from external .menu and .subm files, enabling easy extension and customization without modifying the core script.
#
# (c) Oleh Hryshko


# --- Color Codes ---
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
REVERSE='\033[7m'

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[0;37m'

GREEN_BRIGHT='\033[1;32m'
RED_BRIGHT='\033[1;31m'
YELLOW_BRIGHT='\033[1;33m'
BLUE_BRIGHT='\033[1;34m'
CYAN_BRIGHT='\033[1;36m'
MAGENTA_BRIGHT='\033[1;35m'
WHITE_BRIGHT='\033[1;37m'

RESET="\033[0m"

MENU_COLOR=${WHITE_BRIGHT}

SEPARATOR="----------------"

# Go to the script catalog
SCRIPT_DIR=$(dirname "$(realpath "$0")")
cd "$SCRIPT_DIR" || exit

# --- Configuration ---
# Directory where your MENU files with submenu commands are located.
MENU_DIR="$SCRIPT_DIR/menu"

# Check if MENU_DIR exists, if not, create it.
if [[ ! -d "$MENU_DIR" ]]; then
    echo "Creating MENU directory: $MENU_DIR"
    mkdir -p "$MENU_DIR" || { echo "Error: Failed to create directory $MENU_DIR. Exiting."; exit 1; }
fi

# File to store persisted menu variable values.
MENU_VARS_FILE="$MENU_DIR/menu.cfg"

# Menu LOG file.
MENU_LOG_FILE="$MENU_DIR/menu.log"
echo "Start menu: $(date '+%Y-%m-%d %H:%M:%S')" >> "${MENU_LOG_FILE}"

# --- Functions for Variable Persistence ---

# Saves the current values of environment variables found as placeholders in MENU files.
# It scans all MENU files for <variable_name> placeholders. If a corresponding
# environment variable is set and not empty, its value is saved to MENU_VARS_FILE.
function save_menu_variables {
    #echo "Saving menu variables..."
    declare -A vars_to_save # Associative array to store unique variables to be saved

    # Scan all MENU files for placeholders
    if [[ -d "$MENU_DIR" ]]; then
        local menu_files=()
        while IFS= read -r -d $'\0' menu_file_path; do
            menu_files+=("$menu_file_path")
        done < <(find "$MENU_DIR" -maxdepth 1 -type f -name "*.menu" -print0)

        local placeholder_regex="<([a-zA-Z0-9_]+)>"
        for file in "${menu_files[@]}"; do
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Search for placeholders in each line of the MENU file
                if [[ "$line" =~ $placeholder_regex ]]; then
                    local var_name="${BASH_REMATCH[1]}" # Extract variable name (e.g., 'ip')
                    # If an environment variable with this name exists and is not empty, save it.
                    if [[ -n "${!var_name}" ]]; then
                        vars_to_save["$var_name"]="${!var_name}"
                    fi
                fi
            done < "$file"
        done
    fi

    # Overwrite the variables file with current values
    > "$MENU_VARS_FILE" # Clear the file before writing
    for var_name in "${!vars_to_save[@]}"; do
        echo "${var_name}=${vars_to_save[$var_name]}" >> "$MENU_VARS_FILE"
    done
    #echo "Variables saved to $MENU_VARS_FILE"
}

# Loads saved variable values from MENU_VARS_FILE and exports them as environment variables.
# This ensures previously entered values are available across script runs.
function load_menu_variables {
    if [[ -f "$MENU_VARS_FILE" ]]; then
        #echo -e "\nCustom variables:"
        local variables_loaded_count=0

        while IFS='=' read -r var_name var_value || [[ -n "$var_name" ]]; do
            # Skip empty lines or comments
            if [[ -z "$var_name" || "${var_name:0:1}" == "#" ]]; then
                continue
            fi
            # Remove leading/trailing whitespace from name and value
            var_name=$(echo "$var_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            var_value=$(echo "$var_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Export the variable as an environment variable
            export "${var_name}=${var_value}"
			echo "${var_name}=${var_value}"
            ((variables_loaded_count++))
        done < "$MENU_VARS_FILE"
    fi
}

# --- Global Variables for Menu Functions ---
# These will hold the current menu items, commands, and selected index.
# They are declared globally to be accessible by show_menu and related functions.
declare -gA menu_commands_map # Global associative array for MENU commands (still useful for quick lookups if needed, but not for order)
declare -ga menu_item_names   # Global array to store MENU item names in their original order
declare -ga menu_item_commands # Global array to store MENU commands in their original order

# --- Core Menu Display Function ---

# Displays a dynamic menu, handles user input (arrow keys, Enter, Backspace),
# and executes selected commands or navigates submenus.
# Arguments:
#   $1: Menu title (string)
#   $2: Name of the array holding menu item names (nameref)
#   $3: Name of the array holding commands/functions for each item (nameref)
#   $4: Name of the variable holding the currently selected index (nameref)
#   $5: Type of menu ("main_menu" or "submenu") for Backspace handling
function show_menu {
    local title="$1"
    declare -n items_array_ref="$2" # Indirect reference to the array of menu item names
    declare -n commands_array_ref="$3" # Indirect reference to the array of commands/functions
    declare -n selected_idx_ref="$4" # Indirect reference to the selected index variable
    local menu_type="$5" # "main_menu" or "submenu"

    local current_index="${selected_idx_ref}" # Initialize current_index from the passed reference

    while true; do
        clear
        # Display menu title (uppercase, underscores replaced with spaces)
		#local cleaned_title=$(echo "${title}" | sed -E 's/^[0-9]{1,2}\.[[:space:]]*//')
		local cleaned_title=$title
		echo -e "${MENU_COLOR}[${cleaned_title^^//_/ }]${RESET}"
        for i in "${!items_array_ref[@]}"; do
            # Remove numeric prefixes (e.g., "1.", "01.", "99.") from the menu item name
            #local cleaned_item_name=$(echo "${items_array_ref[$i]}" | sed -E 's/^[0-9]{1,2}\.[[:space:]]*//')
            local cleaned_item_name=${items_array_ref[$i]}
            if [[ "$i" -eq "$current_index" ]]; then
                echo -e "${MENU_COLOR}${BOLD}> ${REVERSE}${cleaned_item_name}${RESET}" # Highlight selected item
            else
                echo -e "  ${MENU_COLOR}${cleaned_item_name}${RESET}" # Display other items
            fi
        done
        echo ""

        # Read single character input for navigation
        IFS= read -s -n 1 input
        if [[ "$input" == "" ]]; then # Handle Enter key
            input=$'\x0A' # Assign newline character for consistent handling
        fi

        # If the first character is ESC, read more for arrow keys (e.g., ESC[A for Up)
        if [[ "$input" == $'\x1B' ]]; then
            read -s -n 1 -t 0.1 input_second # Read second char with timeout
            read -s -n 1 -t 0.1 input_third  # Read third char with timeout
            input="$input$input_second$input_third" # Concatenate all parts
        fi

        case "$input" in
            $'\x1B[A') # Up arrow key
                ((current_index--))
                if [[ "$current_index" -lt 0 ]]; then
                    current_index=$((${#items_array_ref[@]} - 1)) # Wrap around to the last item
                fi
                # Skip over separator lines if encountered during navigation
				if [[ "${commands_array_ref[$current_index]}" == "" ]]; then
                    ((current_index--))
				fi
                selected_idx_ref=$current_index # Update the referenced selected index
                ;;
            $'\x1B[B') # Down arrow key
                ((current_index++))
                if [[ "$current_index" -ge ${#items_array_ref[@]} ]]; then
                    current_index=0 # Wrap around to the first item
                fi
                # Skip over separator lines if encountered during navigation
				if [[ "${commands_array_ref[$current_index]}" == "" ]]; then
                    ((current_index++))
				fi
                selected_idx_ref=$current_index # Update the referenced selected index
                ;;
            $'\x0A'|'') # Enter key (or empty string if previous read -n1 got it)
                local command_to_run="${commands_array_ref[$current_index]}"

                # Handle special internal commands
                if [[ "$command_to_run" == "" ]]; then
                    continue # Do nothing for separator lines
                elif [[ "$command_to_run" == "exit_menu" ]]; then
                    selected_idx_ref=0 # Reset index before returning to parent menu
                    return # Exit the current menu loop
                elif [[ "$command_to_run" == "log_out" ]]; then
                    log_out # Call the log_out function (which saves variables and exits)
                elif [[ "$command_to_run" == "dynamic_menu_submenu" ]]; then
                    # This triggers loading and displaying a submenu from an MENU file
                    local selected_menu_file_name="${items_array_ref[$current_index]}"
                    submenu_from_menu "$MENU_DIR/$selected_menu_file_name.menu" "$selected_menu_file_name"
                elif [[ "$command_to_run" == "submenu:"* ]]; then
                    local target_submenu_file_full_name="${command_to_run#submenu:}" # Extract "*.submenu"
                    local submenu_full_path="$MENU_DIR/$target_submenu_file_full_name" # Construct full path. Assumes target can be relative path.
                    local submenu_display_name="${items_array_ref[$current_index]}"
                    submenu_from_menu "$submenu_full_path" "$submenu_display_name"
				elif [[ $(type -t "$command_to_run") == "function" ]]; then
                    # If the command is a shell function, execute it
                    "$command_to_run"
                else
                    # For other commands (from MENU files), execute them allowing variable substitution
                    execute_menu_command "$command_to_run" "${items_array_ref[$current_index]}"
                fi
                ;;
            $'\x7F'|'\b') # Backspace key
                if [[ "$menu_type" == "submenu" ]]; then
                    selected_idx_ref=0 # Reset index when returning from a submenu
                    return # Go back to the calling menu
                elif [[ "$menu_type" == "main_menu" ]]; then
                    log_out # Exit the script from the main menu
                fi
                ;;
            *) # For any other key pressed, do nothing and loop again
                ;;
        esac
    done
}

# --- Functions for MENU file reading ---

# Reads commands from an MENU file into global ordered arrays (menu_item_names, menu_item_commands).
# This preserves the order of items as they appear in the MENU file.
# Arguments:
#   $1: Path to the MENU file.
function read_menu_file {
    local menu_file="$1"
    menu_commands_map=() # Clear associative map (still useful for some lookups)
    menu_item_names=()   # Clear ordered names array
    menu_item_commands=() # Clear ordered commands array

    if [[ ! -f "$menu_file" ]]; then
        echo "Error: MENU file '$menu_file' not found." >&2
        return 1
    fi

    local line_num=0
    while IFS='=' read -r name command_val || [[ -n "$name" ]]; do
        ((line_num++))
        # Skip empty lines and lines starting with '#' (comments)
        if [[ -z "$name" || "${name:0:1}" == "#" ]]; then
            continue
        fi

        # Remove leading/trailing whitespace from name and command value
        name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        command_val=$(echo "$command_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ -n "$name" ]]; then
            menu_commands_map["$name"]="$command_val" 	# Populate associative array
            menu_item_names+=("$name")              	# Add to ordered names array
            menu_item_commands+=("$command_val")    	# Add to ordered commands array
        else
            echo "Warning: Skipping line $line_num in $menu_file (missing command name)." >&2
        fi
    done < "$menu_file"
    return 0
}

# Displays a submenu dynamically loaded from an MENU file.
# Reads the MENU file, populates menu items and commands, then calls show_menu.
# Arguments:
#   $1: Path to the MENU file.
#   $2: Title for the submenu.
function submenu_from_menu {
    local menu_path="$1"
    local menu_title="$2"

    if ! read_menu_file "$menu_path"; then
        echo "Failed to load commands from $menu_path."
        press_enter
        return # Go back to the calling menu if file loading fails
    fi

    # Check if any commands were loaded from the MENU file
    if [[ ${#menu_item_names[@]} -eq 0 ]]; then
        echo "No commands found or correctly parsed in '$menu_path'."
        echo "Ensure commands are in 'Name=command' format."
        press_enter
        return # Go back to the calling menu if no items are found
    fi

    # Populate temporary arrays for show_menu directly from the ordered global arrays
    local current_submenu_items=("${menu_item_names[@]}")
    local current_submenu_commands=("${menu_item_commands[@]}")

    # Add 'Back' option to return from the submenu
	current_submenu_items+=("$SEPARATOR")
    current_submenu_commands+=("") # Empty command for separator
    current_submenu_items+=("Back")
    current_submenu_commands+=("exit_menu") # Special command to signal return

    local submenu_selected_index=0 # Initialize selected index for this specific submenu

    # Call the generic show_menu function for the submenu
    show_menu "$menu_title" current_submenu_items current_submenu_commands submenu_selected_index "submenu"
}

# Executes a command, allowing for dynamic substitution of placeholders like <variable_name>.
# It first checks if an environment variable matching the placeholder name exists;
# otherwise, it prompts the user for a value.
# Arguments:
#   $1: The command template string (e.g., "sudo nmap <ip>").
#   $2: The display name of the menu item (for user feedback).
function execute_menu_command {
    local command_template="$1"
    local menu_item_name="$2" # For display purposes
    local final_command="$command_template" # Initialize final_command with template

    # Find all placeholders like <variable_name> using regex
    local placeholder_regex="<([a-zA-Z0-9_]+)>"

    # Loop as long as placeholders are found in the command string
    while [[ "$final_command" =~ $placeholder_regex ]]; do
        local var_name="${BASH_REMATCH[1]}" # Extract the variable name (e.g., 'ip', 'user')
        local placeholder="<${var_name}>"   # Reconstruct the full placeholder (e.g., '<ip>')
        local current_var_value="${!var_name}"
        local var_value=""                  # Variable to hold the resolved value
        local prompt_message="Enter value for '${var_name}'"

        if [[ -n "$current_var_value" ]]; then
            prompt_message+=" (default: ${current_var_value})"
        fi
        prompt_message+=": "

        # Prompt the user for input
        read -p "$prompt_message" user_input_value

        if [[ -z "$user_input_value" ]]; then
            var_value="$current_var_value"
            if [[ -n "$var_value" ]]; then
                echo -e "${YELLOW}Using default value for '${var_name}': ${var_value}${RESET}"
            else
                echo -e "${YELLOW}No value provided for '${var_name}', leaving empty.${RESET}"
            fi
        else
            var_value="${user_input_value}"
            echo -e "${YELLOW}Using user provided value for '${var_name}': ${var_value}${RESET}"
        fi

        # Export the variable as an environment variable
        export "$var_name=${var_value}"

        # Replace ALL occurrences of the current placeholder in final_command
        final_command="${final_command//${placeholder}/${var_value}}"
    done

    if [[ "$command_template" != "$final_command" ]]; then
        save_menu_variables
    fi

    echo -e "${YELLOW_BRIGHT}${BOLD}${REVERSE}\nExecuting: $menu_item_name${RESET}"
    echo -e "${CYAN}Command: $final_command${RESET}" # Show the final command before execution

    #eval "$final_command" # Execute the constructed command
    output=$( { eval "$final_command" 2>&1 | tee /dev/tty; } )
    echo -e "\nStart: $(date '+%Y-%m-%d %H:%M:%S')" >> "${MENU_LOG_FILE}"
    echo -e "Executing: $menu_item_name" >> "${MENU_LOG_FILE}"
    echo -e "Command: $final_command" >> "${MENU_LOG_FILE}"
    echo -e "$output" >> "${MENU_LOG_FILE}"
    press_enter # Wait for user to press Enter before returning to menu
}

# Prompts the user to press Enter to continue.
function press_enter {
	echo ""
    read -p "Press Enter to continue..."
	echo ""
}

TMUX_LOG_SESSION_NAME="MenuLogSession"

function view_menu_log {

    local window_name="Log"
    local tail_command="tail -f \"$MENU_LOG_FILE\"; exec bash"

    if [[ -n "$TMUX" ]]; then

        tmux rename-window "Main"

        if tmux has-window -t ":$window_name" &>/dev/null; then
            echo -e "${GREEN}${BOLD}Switching to existing tmux window '${window_name}' in current session.${RESET}"
            tmux select-window -t ":$window_name"
        else
            echo -e "${GREEN}${BOLD}Creating new tmux window '${window_name}' for menu log...${RESET}"
            tmux new-window -P -d -n "$window_name" bash
            sleep 0.1
            tmux send-keys -t "$window_name" "$tail_command" C-m
            echo -e "${YELLOW_BRIGHT}New window created. Switch to it: ${BOLD}Ctrl+b p/n${RESET} or ${BOLD}Ctrl+b <number>${RESET}"

            _MENU_LOG_WINDOW_CREATED_BY_ME_IN_CURRENT_SESSION="$window_name"
        fi
    else
        if tmux has-session -t "$TMUX_LOG_SESSION_NAME" &>/dev/null; then
            if tmux has-window -t "$TMUX_LOG_SESSION_NAME:$window_name" &>/dev/null; then
                echo -e "${GREEN}${BOLD}Existing detached tmux session '${TMUX_LOG_SESSION_NAME}' with window '${window_name}' found.${RESET}"
                echo -e "${YELLOW_BRIGHT}To view: ${BOLD}tmux attach-session -t ${TMUX_LOG_SESSION_NAME}:${window_name}${RESET}"
            else
                echo -e "${YELLOW_BRIGHT}Detached tmux session '${TMUX_LOG_SESSION_NAME}' found, but window '${window_name}' does not exist.${RESET}"
                echo -e "${GREEN}${BOLD}Creating new window '${window_name}' in existing session '${TMUX_LOG_SESSION_NAME}'...${RESET}"
                tmux new-window -t "$TMUX_LOG_SESSION_NAME" -P -d -n  "$window_name" bash
                sleep 0.1
                tmux send-keys -t "$TMUX_LOG_SESSION_NAME:$window_name" "$tail_command" C-m
                echo -e "${YELLOW_BRIGHT}New window created. To view: ${BOLD}tmux attach-session -t ${TMUX_LOG_SESSION_NAME}:${window_name}${RESET}"

                _MENU_LOG_WINDOW_CREATED_BY_ME_IN_CURRENT_SESSION="$window_name"
            fi
        else
            echo -e "${GREEN}${BOLD}Creating new detached tmux session '${TMUX_LOG_SESSION_NAME}' with window '${window_name}' for menu log...${RESET}"
            tmux new-session -s "$TMUX_LOG_SESSION_NAME" -P -d -n "$window_name" bash
            sleep 0.1
            tmux send-keys -t "$TMUX_LOG_SESSION_NAME:$window_name" "$tail_command" C-m
            echo -e "${YELLOW_BRIGHT}New detached session created.${RESET}"
            echo -e "${YELLOW_BRIGHT}To view: ${BOLD}tmux attach-session -t ${TMUX_LOG_SESSION_NAME}:${window_name}${RESET}"

            _MENU_LOG_SESSION_CREATED_BY_ME="$TMUX_LOG_SESSION_NAME"
        fi
    fi

    return 0
}

# Cleans up the screen, saves menu variables, and exits the script.
function log_out {
	save_menu_variables # Save current variable values before exiting
    clear
    log_out_tmux
    exit
}

function log_out_tmux {
    if [[ -n "$_MENU_LOG_SESSION_CREATED_BY_ME" ]]; then
        echo -e "${YELLOW}Closing detached tmux session: $_MENU_LOG_SESSION_CREATED_BY_ME${RESET}"
        tmux kill-session -t "$_MENU_LOG_SESSION_CREATED_BY_ME" &>/dev/null
    elif [[ -n "$_MENU_LOG_WINDOW_CREATED_BY_ME_IN_CURRENT_SESSION" ]]; then
        if [[ -n "$TMUX" ]]; then
            echo -e "${YELLOW}Closing tmux window: $_MENU_LOG_WINDOW_CREATED_BY_ME_IN_CURRENT_SESSION${RESET}"
            tmux kill-window -t ":$_MENU_LOG_WINDOW_CREATED_BY_ME_IN_CURRENT_SESSION" &>/dev/null
        fi
    fi
}

function variables {
	load_menu_variables
	press_enter
}

# --- Main Menu Functions ---
# Global arrays and index for the main menu, accessible by show_menu.
declare -a main_menu_items
declare -a main_menu_commands
declare -i main_menu_selected_index

# Populates the main menu items and their corresponding commands.
# Includes static items and dynamically loaded MENU-based submenus.
function get_main_menu {
    main_menu_selected_index=0 # Reset selection each time main menu is built

    main_menu_items=() # Clear arrays
    main_menu_commands=()

    # Add dynamic MENU-based submenus by scanning the MENU_DIR
    if [[ -d "$MENU_DIR" ]]; then
        local menu_files=()
        # Find all .MENU files and sort them alphabetically, then extract base name
        while IFS= read -r -d $'\0' menu_file_path; do
            menu_files+=("$(basename "$menu_file_path" .menu)") # Just the filename without .menu
        done < <(find "$MENU_DIR" -maxdepth 1 -type f -name "*.menu" -print0 | sort -z)

		for menu_file_name in "${menu_files[@]}"; do
            main_menu_items+=("$menu_file_name") # Use the cleaned name for display
            main_menu_commands+=("dynamic_menu_submenu") # Command remains the same
        done
    else
        echo "Warning: MENU directory '$MENU_DIR' not found. Dynamic menus will not be loaded." >&2
    fi

    # Add fixed menu items
    if [[ ${#main_menu_items[@]} -gt 0 ]]; then # Add separator only if there are dynamic items

        main_menu_items+=("$SEPARATOR")
        main_menu_commands+=("") # Empty command for separator

		main_menu_items+=("Variables")
        main_menu_commands+=("variables")
    fi

    main_menu_items+=("Exit")
    main_menu_commands+=("log_out")
}

# Displays an animated "Main Menu" title at script start-up.
function animate_menu_title {
    clear

    local title_text="[Main Menu]"
    for (( i=0; i<${#title_text}; i++ )); do
        echo -n "${title_text:i:1}"
        sleep 0.02 # Small delay for animation effect
    done
    sleep 0.5 # Pause after animation
}

# --- Script Start ---
view_menu_log
load_menu_variables # Load persisted variable values
animate_menu_title # Show animated title
get_main_menu # Initialize main menu items
# Main menu loop directly calls show_menu for the main menu
show_menu "Main menu" main_menu_items main_menu_commands main_menu_selected_index "main_menu"
# After show_menu returns (e.g., if log_out is chosen or script exits), the script will end.
