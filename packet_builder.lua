-- Packet building module
-- Handles conversion from field data to binary packet format

local field_utils = require('fields.utils');

local packet_builder = {};

-- Write nested struct to packet - handle both bit fields and regular fields
function packet_builder.write_nested_struct_to_packet(packet, field, field_data, base_offset)
    local array_count = field.array_size or 1;
    
    for struct_idx = 1, array_count do
        local current_offset = base_offset;
        
        for _, nested_field in ipairs(field.nested_fields) do
            if not nested_field.name:find('padding') then
                local nested_value = field_data[struct_idx][nested_field.name][1] or 0;
                
                -- Handle arrays within nested structs
                if nested_field.array_size then
                    if nested_field.base_type == 'uint8_t' or nested_field.base_type == 'char' then
                        local str = field_data[struct_idx][nested_field.name][1] or '';
                        for i = 0, nested_field.array_size - 1 do
                            local byte_val = (i + 1) <= #str and str:byte(i + 1) or 0;
                            packet[current_offset + i + 1] = byte_val;
                        end
                        current_offset = current_offset + nested_field.array_size;
                    else
                        local element_size = nested_field.bits <= 8 and 1 or nested_field.bits <= 16 and 2 or 4;
                        local array_data = field_data[struct_idx][nested_field.name];
                        for i = 1, nested_field.array_size do
                            local value = array_data[i] or 0;
                            packet_builder.write_value_to_packet(packet, value, current_offset, element_size);
                            current_offset = current_offset + element_size;
                        end
                    end
                else
                    -- Handle regular scalar fields
                    local field_size = nested_field.bits <= 8 and 1 or nested_field.bits <= 16 and 2 or 4;
                    packet_builder.write_value_to_packet(packet, nested_value, current_offset, field_size);
                    current_offset = current_offset + field_size;
                end
            else
                -- Handle padding
                local padding_size = nested_field.bits <= 8 and 1 or nested_field.bits <= 16 and 2 or 4;
                current_offset = current_offset + padding_size;
            end
        end
    end
end

-- Write a value to packet at specified offset with given size
function packet_builder.write_value_to_packet(packet, value, offset, size_bytes)
    if size_bytes == 1 then
        packet[offset + 1] = bit.band(value, 0xFF);
    elseif size_bytes == 2 then
        packet[offset + 1] = bit.band(value, 0xFF);
        packet[offset + 2] = bit.band(bit.rshift(value, 8), 0xFF);
    elseif size_bytes == 4 then
        packet[offset + 1] = bit.band(value, 0xFF);
        packet[offset + 2] = bit.band(bit.rshift(value, 8), 0xFF);
        packet[offset + 3] = bit.band(bit.rshift(value, 16), 0xFF);
        packet[offset + 4] = bit.band(bit.rshift(value, 24), 0xFF);
    end
end

-- Write array field to packet
function packet_builder.write_array_to_packet(packet, field, field_data, offset)
    if field_utils.is_char_array(field) then
        local str = field_data[1] or '';
        for i = 0, field.array_size - 1 do
            local byte_val = (i + 1) <= #str and str:byte(i + 1) or 0;
            packet[offset + i + 1] = byte_val;
        end
    else
        local element_size = field.bits <= 8 and 1 or field.bits <= 16 and 2 or 4;
        for i = 1, field.array_size do
            local value = field_data[i] or 0;
            local element_offset = offset + (i - 1) * element_size;
            packet_builder.write_value_to_packet(packet, value, element_offset, element_size);
        end
    end
end

-- Write scalar field to packet (handles bit fields)
function packet_builder.write_scalar_to_packet(packet, field, field_data, offset)
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
        local size_bytes = field.bits <= 8 and 1 or field.bits <= 16 and 2 or 4;
        packet_builder.write_value_to_packet(packet, value, offset, size_bytes);
    end
end

-- Main packet creation function
function packet_builder.create_packet(struct_info, struct_data)
    if not struct_info then return {}; end

    local packet = {};
    for i = 1, struct_info.size do
        packet[i] = 0;
    end

    struct_info.fields:each(function(field)
        local field_data = struct_data[field.name];
        local offset = field.offset;
        
        if field_utils.is_nested_struct(field) then
            packet_builder.write_nested_struct_to_packet(packet, field, field_data, offset);
        elseif field_utils.is_array_field(field) then
            packet_builder.write_array_to_packet(packet, field, field_data, offset);
        else
            packet_builder.write_scalar_to_packet(packet, field, field_data, offset);
        end
    end);

    return packet;
end

return packet_builder;