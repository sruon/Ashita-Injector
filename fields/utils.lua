-- Field utilities module for packet injector
-- Handles field type detection, validation, and property access

local field_utils = {};

-- Field type detection utilities
function field_utils.is_array_field(field)
    return field.array_size ~= nil;
end

function field_utils.is_char_array(field)
    return field_utils.is_array_field(field) and field.base_type == 'char';
end

function field_utils.is_numeric_array(field)
    return field_utils.is_array_field(field) and field.base_type ~= 'char';
end

function field_utils.is_nested_struct(field)
    return field.nested_fields ~= nil;
end

function field_utils.needs_helper_button(field_name)
    return field_name:match('UniqueNo') or field_name:match('ActIndex');
end

function field_utils.should_show_bits_info(field)
    if field.type:match('uint8_t') or field.type:match('int8_t') then
        return field.bits ~= 8;
    elseif field.type:match('uint16_t') or field.type:match('int16_t') then
        return field.bits ~= 16;
    elseif field.type:match('uint32_t') or field.type:match('int32_t') then
        return field.bits ~= 32;
    else
        return true;
    end
end

function field_utils.get_value_limits(field)
    local bits = field.bits;

    if field.signed then
        -- Signed: -2^(bits-1) to 2^(bits-1) - 1
        local max_positive = bit.lshift(1, bits - 1) - 1;
        local min_negative = -bit.lshift(1, bits - 1);
        return max_positive, min_negative;
    else
        -- Unsigned: 0 to 2^bits - 1
        local max_value = bit.lshift(1, bits) - 1;
        return max_value, 0;
    end
end

return field_utils;
