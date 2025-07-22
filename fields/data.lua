-- Field data management module
-- Handles initialization and manipulation of field data structures

require('common');
local field_utils = require('fields.utils');

local field_data = {};

-- Field data initialization
function field_data.init_field_data(field)
    if field_utils.is_char_array(field) then
        return T{ '' };
    elseif field_utils.is_numeric_array(field) then
        local array = T{};
        for i = 1, field.array_size do array[i] = 0; end
        return array;
    else
        return T{ 0 };
    end
end

function field_data.init_nested_struct_data(nested_fields)
    local nested_data = T{};
    for _, nested_field in ipairs(nested_fields) do
        if not nested_field.name:find('padding') then
            -- Initialize nested field data exactly like regular fields
            if nested_field.array_size then
                if nested_field.base_type == 'uint8_t' or nested_field.base_type == 'char' then
                    nested_data[nested_field.name] = T{ '' };
                else
                    local array = T{};
                    for i = 1, nested_field.array_size do array[i] = 0; end
                    nested_data[nested_field.name] = array;
                end
            else
                nested_data[nested_field.name] = T{ 0 };
            end
        end
    end
    return nested_data;
end

function field_data.init_struct_data(struct_name, get_struct_fields_func)
    local struct_info = get_struct_fields_func(struct_name);
    if not struct_info then return false; end

    local struct_data = T{};

    struct_info.fields:each(function(field)
        if field_utils.is_nested_struct(field) then
            -- Handle nested struct or array of structs
            local array_count = field.array_size or 1;
            local nested_array = T{};
            for i = 1, array_count do
                nested_array[i] = field_data.init_nested_struct_data(field.nested_fields);
            end
            struct_data[field.name] = nested_array;
        else
            -- Handle regular fields
            struct_data[field.name] = field_data.init_field_data(field);
        end
    end);

    -- Set packet ID if field exists
    if struct_data.id then
        struct_data.id[1] = struct_info.packet_id;
    end

    return struct_data;
end

-- Helper value getters for specific field types
function field_data.get_helper_value(field_name)
    local target = AshitaCore:GetMemoryManager():GetTarget();
    local party = AshitaCore:GetMemoryManager():GetParty();

    if field_name:match('UniqueNo') then
        if target and target:GetTargetIndex(0) > 0 then
            return target:GetServerId(0);
        else
            return party:GetMemberServerId(0);
        end
    elseif field_name:match('ActIndex') then
        if target and target:GetTargetIndex(0) > 0 then
            return target:GetTargetIndex(0);
        else
            return party:GetMemberTargetIndex(0);
        end
    end
    return nil;
end

return field_data;