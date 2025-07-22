addon.name    = 'injector';
addon.author  = 'sruon';
addon.version = '1.0';
addon.desc    = 'Dynamic packet injector for Ashita v4';
addon.link    = '';

require('common');
local imgui = require('imgui');
local structs = require('structs');
local field_utils = require('fields.utils');
local field_data = require('fields.data');
local field_renderer = require('fields.renderer');
local packet_builder = require('packet_builder');

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

-- Wrapper functions for backwards compatibility
local function get_helper_value(field_name)
    return field_data.get_helper_value(field_name);
end

local function init_struct_data(struct_name)
    local struct_data = field_data.init_struct_data(struct_name, get_struct_fields);
    if struct_data then
        injector.struct_data[struct_name] = struct_data;
        return true;
    end
    return false;
end


local function create_packet(struct_name)
    local struct_info = get_struct_fields(struct_name);
    local struct_data = injector.struct_data[struct_name];
    return packet_builder.create_packet(struct_info, struct_data);
end

local function print_struct_data(struct_name)
    local struct_info = get_struct_fields(struct_name);
    if not struct_info then return; end

    print(('=== %s ==='):fmt(struct_name));
    local data = injector.struct_data[struct_name];

    struct_info.fields:each(function(field)
        if field.nested_fields then
            -- Skip nested fields in preview for now
            print(('  %s: [nested struct - %d items]'):fmt(field.name or 'unknown', field.array_size or 1));
            return;
        end
        
        local field_data = data[field.name];
        if not field_data then
            print(('  %s: [no data]'):fmt(field.name or 'unknown'));
            return;
        end

        if field.array_size then
            if field.base_type == 'uint8_t' or field.base_type == 'char' then
                local str = field_data[1] or '';
                print(('  %s (%s): "%s"'):fmt(tostring(field.name), tostring(field.type), str));
            else
                local values = {};
                for i = 1, field.array_size do
                    values[i] = tostring(field_data[i] or 0);
                end
                print(('  %s (%s): [%s]'):fmt(tostring(field.name), tostring(field.type), table.concat(values, ', ')));
            end
        else
            local value = field_data[1];
            print(('  %s (%s): %d'):fmt(tostring(field.name), tostring(field.type), value or 0));
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
        if string.find(field.name:lower(), 'padding') or field.name == 'id' or field.name == 'sync' or field.name == 'size' then
            return;
        end

        local data = injector.struct_data[injector.current_struct][field.name];
        
        if field_utils.is_nested_struct(field) then
            field_renderer.render_nested_struct_field(field, data, injector.hex_displays);
        else
            field_renderer.render_complete_field(field, data, injector.hex_displays);
        end
    end);

    imgui.Separator();

    imgui.PushStyleColor(ImGuiCol_Button, { 0.2, 0.4, 0.8, 1.0 });
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.3, 0.5, 0.9, 1.0 });
    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.1, 0.3, 0.7, 1.0 });
    if imgui.Button('Preview', { 80, 25 }) then
        print_struct_data(injector.current_struct);
        
        -- Print hex packet preview
        local packet = create_packet(injector.current_struct);
        local hex_string = '';
        for i = 1, #packet do
            hex_string = hex_string .. ('%02X '):fmt(packet[i]);
        end
        
        -- Print hex output in 16-byte lines
        print('Hex Preview:');
        for i = 1, #packet, 16 do
            local line = '';
            for j = i, math.min(i + 15, #packet) do
                line = line .. ('%02X '):fmt(packet[j]);
            end
            print(line);
        end
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
        print(('Calculated struct size: %d bytes'):fmt(struct_info.size));
        print(('Generated packet size: %d bytes'):fmt(#packet));

        -- Print packet data in 16-byte lines
        print('Packet data:');
        for i = 1, #packet, 16 do
            local line = '';
            for j = i, math.min(i + 15, #packet) do
                line = line .. ('%02X '):fmt(packet[j]);
            end
            print(line);
        end

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
