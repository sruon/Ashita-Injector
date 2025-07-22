local c2s = require('c2s');
local s2c = require('s2c');
local c2s_structs = T{ };
local s2c_structs = T{ };

local function load_packet_definitions(packet_data, structs_table)
    for _, packet_info in ipairs(packet_data) do
        local packet_id = tonumber(packet_info.id);
        local struct_name = packet_info.name;
        local fields = T{ };
        local current_offset = 0;

        for _, field_info in ipairs(packet_info.fields) do
            local field_type = field_info.type_name;
            local field_name = field_info.name;
            local bits = field_info.bits;

            local field_size = field_info.size_bytes;
            if field_info.array_size then
                field_size = field_size * field_info.array_size;
            end

            local field_offset = current_offset;

            if bits < 16 and (field_name == 'id' or field_name == 'size') then
                field_offset = 0;
                if field_name == 'size' then
                    current_offset = 2;
                end
            else
                current_offset = current_offset + field_size;
            end

            fields:append({
                name = field_name,
                type = field_type,
                bits = bits,
                comment = '',
                offset = field_offset
            });
        end

        structs_table[struct_name] = {
            fields = fields,
            size = current_offset,
            packet_id = packet_id
        };
    end
end

load_packet_definitions(c2s, c2s_structs);
load_packet_definitions(s2c, s2c_structs);

local function get_all_structs(packet_type)
    if packet_type == 'C2S' then
        return c2s_structs;
    elseif packet_type == 'S2C' then
        return s2c_structs;
    else
        return c2s_structs; -- default to C2S
    end
end

local function get_struct(name, packet_type)
    if packet_type == 'C2S' then
        return c2s_structs[name];
    elseif packet_type == 'S2C' then
        return s2c_structs[name];
    else
        return c2s_structs[name] or s2c_structs[name]; -- search both if not specified
    end
end

return {
    get_all_structs = get_all_structs,
    get_struct = get_struct,
};