addon.name    = 'injector';
addon.author  = 'sruon';
addon.version = '1.0';
addon.desc    = 'Dynamic packet injector for Ashita v4';
addon.link    = '';

require('common');
local imgui = require('imgui');
local structs = require('structs');

local injector = T{
    is_open = T{ true, },
    current_packet_type = 'C2S',
    current_struct = 'GP_CLI_COMMAND_LOGIN',
    struct_data = T{ },
    hex_displays = { },
};

local function get_struct_fields(struct_name)
    return structs.get_struct(struct_name, injector.current_packet_type);
end

local function get_helper_value(field_name)
    local target = AshitaCore:GetMemoryManager():GetTarget();
    local party = AshitaCore:GetMemoryManager():GetParty();

    if field_name == 'UniqueNo' then
        if target and target:GetTargetIndex(0) > 0 then
            return target:GetServerId(0);
        else
            return party:GetMemberServerId(0);
        end
    elseif field_name == 'ActIndex' then
        if target and target:GetTargetIndex(0) > 0 then
            return target:GetTargetIndex(0);
        else
            return party:GetMemberTargetIndex(0);
        end
    end
    return nil;
end

local function init_struct_data(struct_name)
    local struct_info = get_struct_fields(struct_name);
    if not struct_info then return false; end

    injector.struct_data[struct_name] = T{ };

    struct_info.fields:each(function(field)
        local base_type, count = field.type:match('([%w_]+)%[(%d+)%]');
        if base_type then
            count = tonumber(count);
            if base_type == 'uint8_t' or base_type == 'char' then
                injector.struct_data[struct_name][field.name] = T{ '' };
            else
                local array = T{};
                for i = 1, count do array[i] = 0; end
                injector.struct_data[struct_name][field.name] = array;
            end
        else
            injector.struct_data[struct_name][field.name] = T{ 0 };
        end
    end);

    if injector.struct_data[struct_name].id then
        injector.struct_data[struct_name].id[1] = struct_info.packet_id;
    end

    return true;
end

local function render_field_input(field, value_table)
    local changed = false;
    local base_type, count = field.type:match('([%w_]+)%[(%d+)%]');

    if base_type then
        count = tonumber(count);
        if base_type == 'uint8_t' or base_type == 'char' then
            imgui.PushItemWidth(200);
            local str_buffer = T{ value_table[1] or '' };
            changed = imgui.InputText(('##%s'):fmt(field.name), str_buffer, count);
            if changed then value_table[1] = str_buffer[1]; end
            imgui.PopItemWidth();
        else
            imgui.Text(('Array[%d]:'):fmt(count));
            for i = 1, count do
                if i > 1 then imgui.SameLine(); end
                imgui.PushItemWidth(60);
                local element_value = T{ value_table[i] or 0 };
                local element_changed = imgui.InputInt(('##%s_%d'):fmt(field.name, i), element_value);
                if element_changed then
                    value_table[i] = element_value[1];
                    changed = true;
                end
                imgui.PopItemWidth();
                if i % 4 == 0 and i < count then imgui.NewLine(); end
            end
        end
    else
        local is_signed = field.type:match('^int') ~= nil;
        local max_value, min_value = 0, 0;

        if field.bits <= 8 then
            if is_signed then
                max_value, min_value = 127, -128;
            else
                max_value, min_value = 255, 0;
            end
        elseif field.bits <= 16 then
            if is_signed then
                max_value, min_value = 32767, -32768;
            else
                max_value, min_value = 65535, 0;
            end
        elseif field.bits <= 32 then
            if is_signed then
                max_value, min_value = 2147483647, -2147483648;
            else
                max_value, min_value = 4294967295, 0;
            end
        end

        imgui.PushItemWidth(120);
        if injector.hex_displays[field.name] then
            local hex_str = T{ ('0x%X'):fmt(value_table[1]) };
            imgui.InputText(('##%s'):fmt(field.name), hex_str, ImGuiInputTextFlags_ReadOnly);
        else
            changed = imgui.InputInt(('##%s'):fmt(field.name), value_table);
            if changed then
                value_table[1] = math.max(min_value, math.min(value_table[1], max_value));
            end
        end
        imgui.PopItemWidth();
    end

    return changed;
end

local function create_packet(struct_name)
    local struct_info = get_struct_fields(struct_name);
    if not struct_info then return {}; end

    local packet = {};
    for i = 1, struct_info.size do
        packet[i] = 0;
    end

    local data = injector.struct_data[struct_name];

    struct_info.fields:each(function(field)
        local field_data = data[field.name];
        local offset = field.offset;
        local base_type, count = field.type:match('([%w_]+)%[(%d+)%]');

        if base_type then
            count = tonumber(count);
            if base_type == 'uint8_t' or base_type == 'char' then
                local str = field_data[1] or '';
                for i = 1, count do
                    local byte_val = i <= #str and str:byte(i) or 0;
                    packet[offset + i] = byte_val;
                end
            else
                for i = 1, count do
                    local value = field_data[i] or 0;
                    local element_offset = offset + (i - 1) * (base_type:match('32') and 4 or base_type:match('16') and 2 or 1);

                    if base_type:match('32') then
                        packet[element_offset + 1] = bit.band(value, 0xFF);
                        packet[element_offset + 2] = bit.band(bit.rshift(value, 8), 0xFF);
                        packet[element_offset + 3] = bit.band(bit.rshift(value, 16), 0xFF);
                        packet[element_offset + 4] = bit.band(bit.rshift(value, 24), 0xFF);
                    elseif base_type:match('16') then
                        packet[element_offset + 1] = bit.band(value, 0xFF);
                        packet[element_offset + 2] = bit.band(bit.rshift(value, 8), 0xFF);
                    else
                        packet[element_offset + 1] = bit.band(value, 0xFF);
                    end
                end
            end
        else
            local value = field_data[1];

            -- Handle bit fields that share bytes (like id/size in first word)
            if offset == 0 and (field.name == 'id' or field.name == 'size') then
                -- These are bit fields in the first 16-bit word
                local current_word = (packet[2] or 0) * 256 + (packet[1] or 0);

                if field.name == 'id' then
                    -- ID is bits 0-8 (9 bits)
                    current_word = bit.band(current_word, 0xFE00); -- Clear ID bits
                    current_word = bit.bor(current_word, bit.band(value, 0x1FF)); -- Set ID bits
                elseif field.name == 'size' then
                    -- Size is bits 9-15 (7 bits)
                    current_word = bit.band(current_word, 0x01FF); -- Clear size bits
                    current_word = bit.bor(current_word, bit.lshift(bit.band(value, 0x7F), 9)); -- Set size bits
                end

                packet[1] = bit.band(current_word, 0xFF);
                packet[2] = bit.band(bit.rshift(current_word, 8), 0xFF);
            else
                -- Regular fields
                if field.bits <= 8 then
                    packet[offset + 1] = bit.band(value, 0xFF);
                elseif field.bits <= 16 then
                    packet[offset + 1] = bit.band(value, 0xFF);
                    packet[offset + 2] = bit.band(bit.rshift(value, 8), 0xFF);
                elseif field.bits <= 32 then
                    packet[offset + 1] = bit.band(value, 0xFF);
                    packet[offset + 2] = bit.band(bit.rshift(value, 8), 0xFF);
                    packet[offset + 3] = bit.band(bit.rshift(value, 16), 0xFF);
                    packet[offset + 4] = bit.band(bit.rshift(value, 24), 0xFF);
                end
            end
        end
    end);

    return packet;
end

local function print_struct_data(struct_name)
    local struct_info = get_struct_fields(struct_name);
    if not struct_info then return; end

    print(('=== %s ==='):fmt(struct_name));
    local data = injector.struct_data[struct_name];

    struct_info.fields:each(function(field)
        local field_data = data[field.name];
        local base_type, count = field.type:match('([%w_]+)%[(%d+)%]');

        if base_type then
            if base_type == 'uint8_t' or base_type == 'char' then
                local str = field_data[1] or '';
                print(('  %s (%s): "%s"'):fmt(field.name, field.type, str));
            else
                local values = {};
                for i = 1, tonumber(count) do
                    values[i] = tostring(field_data[i] or 0);
                end
                print(('  %s (%s): [%s]'):fmt(field.name, field.type, table.concat(values, ', ')));
            end
        else
            local value = field_data[1];
            print(('  %s (%s): %d'):fmt(field.name, field.type, value));
        end
    end);
    print('================');
end

local function render_packet_builder()
    local struct_info = get_struct_fields(injector.current_struct);
    if not struct_info then
        imgui.Text('No structure information found for: ' .. injector.current_struct);
        return;
    end

    imgui.Text(('Packet Builder: %s'):fmt(injector.current_struct));
    imgui.Separator();

    struct_info.fields:each(function(field)
        if string.find(field.name:lower(), 'padding') or field.name:any('id', 'sync', 'size') then
            return;
        end

        imgui.TextColored({ 0.4, 0.8, 1.0, 1.0 }, field.name);
        imgui.SameLine();
        imgui.TextColored({ 0.4, 1.0, 0.4, 1.0 }, ('(%s)'):fmt(field.type));

        local show_bits = false;
        if field.type:match('uint8_t') or field.type:match('int8_t') then
            show_bits = field.bits ~= 8;
        elseif field.type:match('uint16_t') or field.type:match('int16_t') then
            show_bits = field.bits ~= 16;
        elseif field.type:match('uint32_t') or field.type:match('int32_t') then
            show_bits = field.bits ~= 32;
        else
            show_bits = true;
        end

        if show_bits then
            imgui.SameLine();
            imgui.TextColored({ 0.7, 0.7, 0.7, 1.0 }, (' (%d bits)'):fmt(field.bits));
        end

        if injector.hex_displays[field.name] == nil then
            injector.hex_displays[field.name] = (field.name == 'id');
        end

        local data = injector.struct_data[injector.current_struct][field.name];
        local base_type, count = field.type:match('([%w_]+)%[(%d+)%]');

        if base_type then
            if base_type == 'uint8_t' or base_type == 'char' then
                local window_width = imgui.GetWindowWidth();
                local input_width = 200;
                local right_margin = 20;
                local controls_x = window_width - input_width - right_margin;

                imgui.SameLine();
                imgui.SetCursorPosX(controls_x);
            end

            local changed = render_field_input(field, data);
        else
            local needs_helper_button = field.name:any('UniqueNo', 'ActIndex');
            local button_width = needs_helper_button and 25 or 0;
            local window_width = imgui.GetWindowWidth();
            local input_width = 120;
            local hex_label_width = 15;
            local checkbox_width = 20;
            local right_margin = 20;
            local total_width = button_width + input_width + hex_label_width + checkbox_width;
            local controls_x = window_width - total_width - right_margin;

            imgui.SameLine();
            imgui.SetCursorPosX(controls_x);

            if needs_helper_button then
                local button_label = field.name == 'UniqueNo' and 'U' or 'A';
                if imgui.Button(button_label, { button_width - 2, 20 }) then
                    local value = get_helper_value(field.name);
                    if value then data[1] = value; end
                end
                imgui.SameLine();
            end

            local changed = render_field_input(field, data);

            imgui.SameLine();
            imgui.TextColored({ 0.8, 0.8, 0.8, 1.0 }, '0x');
            imgui.SameLine();
            local hex_toggle = T{ injector.hex_displays[field.name] };
            if imgui.Checkbox(('##hex_%s'):fmt(field.name), hex_toggle) then
                injector.hex_displays[field.name] = hex_toggle[1];
            end
        end

        imgui.Spacing();
    end);

    imgui.Separator();

    imgui.Text('Packet Preview:');
    local packet = create_packet(injector.current_struct);
    local hex_string = '';
    for i = 1, #packet do
        hex_string = hex_string .. ('%02X '):fmt(packet[i]);
    end
    imgui.TextColored({ 0.8, 0.8, 0.8, 1.0 }, hex_string);

    imgui.Spacing();

    imgui.PushStyleColor(ImGuiCol_Button, { 0.2, 0.4, 0.8, 1.0 });
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.3, 0.5, 0.9, 1.0 });
    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.1, 0.3, 0.7, 1.0 });
        if imgui.Button('Preview', { 80, 25 }) then
        print_struct_data(injector.current_struct);
    end
    imgui.PopStyleColor(3);

    imgui.SameLine();

    imgui.PushStyleColor(ImGuiCol_Button, { 0.8, 0.2, 0.2, 1.0 });
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.9, 0.3, 0.3, 1.0 });
    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.7, 0.1, 0.1, 1.0 });
    if imgui.Button('Inject', { 80, 25 }) then
        local packet = create_packet(injector.current_struct);

        -- Debug output
        print(('=== DEBUG PACKET INJECTION ==='));
        print(('Struct: %s'):fmt(injector.current_struct));
        print(('Packet ID: 0x%04X (%d)'):fmt(struct_info.packet_id, struct_info.packet_id));
        print(('Packet size: %d bytes'):fmt(#packet));

        local hex_debug = '';
        for i = 1, #packet do
            hex_debug = hex_debug .. ('%02X '):fmt(packet[i]);
            if i % 16 == 0 then hex_debug = hex_debug .. '\n'; end
        end
        print(('Packet data: %s'):fmt(hex_debug));

        -- Try to send the packet
        local success, error_msg = pcall(function()
            if injector.current_packet_type == 'C2S' then
                AshitaCore:GetPacketManager():AddOutgoingPacket(struct_info.packet_id, packet);
            else -- S2C
                AshitaCore:GetPacketManager():AddIncomingPacket(struct_info.packet_id, packet);
            end
        end);

        if success then
            local direction = injector.current_packet_type == 'C2S' and 'outgoing' or 'incoming';
            print(('Packet %s sent successfully as %s!'):fmt(injector.current_struct, direction));
        else
            print(('Failed to send packet: %s'):fmt(error_msg or 'unknown error'));
        end
        print(('==============================='));
    end
    imgui.PopStyleColor(3);

    imgui.SameLine();
    imgui.TextDisabled(('Packet ID: 0x%03X'):fmt(struct_info.packet_id));
end

local function render_packet_type_tabs()
    if imgui.BeginTabBar('PacketTypeTabs') then
        if imgui.BeginTabItem('Client to Server (C2S)') then
            if injector.current_packet_type ~= 'C2S' then
                injector.current_packet_type = 'C2S';
                injector.current_struct = 'GP_CLI_COMMAND_LOGIN';
                init_struct_data(injector.current_struct);
            end
            imgui.EndTabItem();
        end
        
        if imgui.BeginTabItem('Server to Client (S2C)') then
            if injector.current_packet_type ~= 'S2C' then
                injector.current_packet_type = 'S2C';
                local all_s2c = structs.get_all_structs('S2C');
                local first_struct = all_s2c:keys()[1];
                injector.current_struct = first_struct or 'GP_SERV_COMMAND_PACKETCONTROL';
                init_struct_data(injector.current_struct);
            end
            imgui.EndTabItem();
        end
        
        imgui.EndTabBar();
    end
end

local function render_struct_selector()
    local all_structs = structs.get_all_structs(injector.current_packet_type);
    local struct_names = all_structs:keys();

    struct_names:sort(function(a, b)
        local info_a = all_structs[a];
        local info_b = all_structs[b];
        if info_a and info_b then
            return info_a.packet_id < info_b.packet_id;
        end
        return a < b;
    end);

    imgui.Text('Select Structure:');
    imgui.SameLine();

    local preview = injector.current_struct;
    local current_struct_info = all_structs[injector.current_struct];
    if current_struct_info then
        preview = ('0x%04X %s'):fmt(current_struct_info.packet_id, injector.current_struct);
    end

    imgui.PushItemWidth(200);
    if imgui.BeginCombo('##struct_selector', preview) then
        struct_names:each(function(struct_name, index)
            local struct_info = all_structs[struct_name];
            local label = struct_name;
            if struct_info then
                label = ('0x%04X %s'):fmt(struct_info.packet_id, struct_name);
            end

            local is_selected = (struct_name == injector.current_struct);
            if imgui.Selectable(label, is_selected) then
                injector.current_struct = struct_name;
                init_struct_data(struct_name);
            end

            if is_selected then imgui.SetItemDefaultFocus(); end
        end);
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
end

ashita.events.register('load', 'load_cb', function()
    init_struct_data(injector.current_struct);
end);

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1] ~= '/injector') then return; end

    e.blocked = true;
    injector.is_open[1] = not injector.is_open[1];
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    if (not injector.is_open[1]) then return; end

    imgui.SetNextWindowSize({ 450, 350, }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 400, 300, }, { FLT_MAX, FLT_MAX, });

    if (imgui.Begin('Packet Injector', injector.is_open)) then
        render_packet_type_tabs();
        imgui.Spacing();
        render_struct_selector();
        imgui.Spacing();
        render_packet_builder();
        imgui.Spacing();
    end
    imgui.End();
end);
