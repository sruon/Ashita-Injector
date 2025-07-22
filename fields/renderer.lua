-- Field rendering module
-- Handles all UI rendering logic for different field types

require('common');
local field_utils = require('fields.utils');
local field_data = require('fields.data');
local imgui = require('imgui');

local field_renderer = {};

-- Core input rendering functions
function field_renderer.render_char_array_input(field, value_table)
    imgui.PushItemWidth(200);
    local str_buffer = T { value_table[1] or '' };
    local changed = imgui.InputText(('##%s'):fmt(field.name), str_buffer, field.array_size + 1);
    if changed then value_table[1] = str_buffer[1]; end
    imgui.PopItemWidth();
    return changed;
end

function field_renderer.render_numeric_array_input(field, value_table)
    local changed = false;
    imgui.Text(('Array[%d]:'):fmt(field.array_size));
    for i = 1, field.array_size do
        if i > 1 and (i - 1) % 4 ~= 0 then imgui.SameLine(); end
        imgui.PushItemWidth(160);
        local element_value = T { value_table[i] or 0 };
        local element_changed = imgui.InputInt(('##%s_%d'):fmt(field.name, i), element_value);
        if element_changed then
            value_table[i] = element_value[1];
            changed = true;
        end
        imgui.PopItemWidth();
        if i % 4 == 0 and i < field.array_size then imgui.NewLine(); end
    end
    return changed;
end

function field_renderer.render_scalar_input(field, value_table, hex_displays)
    local changed = false;
    local max_value, min_value = field_utils.get_value_limits(field);

    imgui.PushItemWidth(120);
    if hex_displays[field.name] then
        local hex_str = T { ('0x%X'):fmt(value_table[1]) };
        imgui.InputText(('##%s'):fmt(field.name), hex_str, ImGuiInputTextFlags_ReadOnly);
    else
        changed = imgui.InputInt(('##%s'):fmt(field.name), value_table);
        if changed then
            value_table[1] = math.max(min_value, math.min(value_table[1], max_value));
        end
    end
    imgui.PopItemWidth();
    return changed;
end

function field_renderer.render_field_input(field, value_table, hex_displays)
    if field_utils.is_char_array(field) then
        return field_renderer.render_char_array_input(field, value_table);
    elseif field_utils.is_numeric_array(field) then
        return field_renderer.render_numeric_array_input(field, value_table);
    else
        return field_renderer.render_scalar_input(field, value_table, hex_displays or {});
    end
end

-- Field label and type info rendering
function field_renderer.render_field_label(field)
    imgui.TextColored({ 0.4, 0.8, 1.0, 1.0 }, field.name);
    imgui.SameLine();
    imgui.TextColored({ 0.4, 1.0, 0.4, 1.0 }, ('(%s)'):fmt(field.type));

    if field_utils.should_show_bits_info(field) then
        imgui.SameLine();
        imgui.TextColored({ 0.7, 0.7, 0.7, 1.0 }, (' (%d bits)'):fmt(field.bits));
    end
end

-- Helper button rendering
function field_renderer.render_helper_button(field, data)
    if field_utils.needs_helper_button(field.name) then
        if imgui.Button(('T##%s'):fmt(field.name), { 23, 20 }) then
            local value = field_data.get_helper_value(field.name);
            if value then data[1] = value; end
        end
        imgui.SameLine();
        return true;
    end
    return false;
end

-- Hex toggle rendering
function field_renderer.render_hex_toggle(field, hex_displays)
    imgui.SameLine();
    imgui.TextColored({ 0.8, 0.8, 0.8, 1.0 }, '0x');
    imgui.SameLine();
    local hex_toggle = T { hex_displays[field.name] };
    if imgui.Checkbox(('##hex_%s'):fmt(field.name), hex_toggle) then
        hex_displays[field.name] = hex_toggle[1];
    end
end

-- Layout utilities
function field_renderer.calculate_controls_position(button_width, input_width, hex_width, checkbox_width)
    local window_width = imgui.GetWindowWidth();
    local right_margin = 20;
    local total_width = button_width + input_width + hex_width + checkbox_width;
    return window_width - total_width - right_margin;
end

-- Complete field rendering with layout
function field_renderer.render_complete_field(field, data, hex_displays)
    -- Initialize hex display if needed
    if hex_displays[field.name] == nil then
        hex_displays[field.name] = (field.name == 'id');
    end

    -- Render field label and type info
    field_renderer.render_field_label(field);

    -- Handle layout based on field type
    if field_utils.is_char_array(field) then
        local controls_x = field_renderer.calculate_controls_position(0, 200, 0, 0);
        imgui.SameLine();
        imgui.SetCursorPosX(controls_x);
        field_renderer.render_field_input(field, data, hex_displays);
    elseif field_utils.is_numeric_array(field) then
        field_renderer.render_field_input(field, data, hex_displays);
    else
        local has_helper = field_utils.needs_helper_button(field.name);
        local button_width = has_helper and 25 or 0;
        local controls_x = field_renderer.calculate_controls_position(button_width, 120, 15, 20);

        imgui.SameLine();
        imgui.SetCursorPosX(controls_x);

        field_renderer.render_helper_button(field, data);
        field_renderer.render_field_input(field, data, hex_displays);
        field_renderer.render_hex_toggle(field, hex_displays);
    end

    imgui.Spacing();
end

-- Nested struct rendering - reuses all the above logic
function field_renderer.render_nested_struct_field(field, data, hex_displays)
    local array_count = field.array_size or 1;

    if array_count > 1 then
        imgui.Text(('Nested struct array [%d]:'):fmt(array_count));
    else
        imgui.Text('Nested struct:');
    end
    imgui.Indent();

    for struct_idx = 1, array_count do
        if imgui.TreeNode(('##struct_%s_%d'):fmt(field.name, struct_idx), ('[%d]'):fmt(struct_idx)) then
            local struct_data = data[struct_idx];

            for _, nested_field in ipairs(field.nested_fields) do
                if not nested_field.name:find('padding') then
                    local nested_field_name = ('%s_%d_%s'):fmt(field.name, struct_idx, nested_field.name);
                    local nested_hex_displays = {};
                    nested_hex_displays[nested_field.name] = hex_displays[nested_field_name];

                    -- Reuse the exact same rendering logic as regular fields
                    local field_copy = {
                        name = nested_field.name,
                        type = nested_field.type_name,
                        bits = nested_field.bits,
                        signed = nested_field.signed,
                        array_size = nested_field.array_size,
                        base_type = nested_field.base_type
                    };
                    field_renderer.render_complete_field(field_copy, struct_data[nested_field.name], nested_hex_displays);

                    hex_displays[nested_field_name] = nested_hex_displays[nested_field.name];
                end
            end

            imgui.TreePop();
        end
    end

    imgui.Unindent();
end

return field_renderer;
