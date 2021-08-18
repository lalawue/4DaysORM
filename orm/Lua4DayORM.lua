
--[[ orm.class.global ]]
------------------------------------------------------------------------------


------------------------------------------------------------------------------
--                                Constants                                 --
------------------------------------------------------------------------------
-- Global
local ID = "id"
local AGGREGATOR = "aggregator"
local QUERY_LIST = "query_list"

-- databases types
local SQLITE = "sqlite3"
local ORACLE = "oracle"
local MYSQL = "mysql"
local POSTGRESQL = "postgresql"

-- Backtrace types
local ERROR = 'e'
local WARNING = 'w'
local INFO = 'i'
local DEBUG = 'd'

local _pairs = pairs

local All_Tables = {}

local Type

local dbInstance

local QueryList
local Query

local function tablePairs(tbl)
    if tbl.__classname__ == QUERY_LIST then
        return tbl()
    else
        return _pairs(tbl)
    end
end

local function BACKTRACE(tracetype, message)
    if DB.backtrace then
        if tracetype == ERROR then
            print("[SQL:Error] " .. message)
            os.exit()

        elseif tracetype == WARNING then
            print("[SQL:Warning] " .. message)

        elseif tracetype == INFO then
            print("[SQL:Info] " .. message)
        end
    end

    if DB.DEBUG and tracetype == DEBUG then
        print("[SQL:Debug] " .. message)
    end
end

local function _endswith(String, End)
    return End == '' or string.sub(String, -string.len(End)) == End
end

local function _cutend(String, End)
    return End == '' and String or string.sub(String, 0, -#End - 1)
end

local function _divided_into(String, separator)
    local separator_pos = string.find(String, separator)
    return string.sub(String, 0, separator_pos - 1),
           string.sub(String, separator_pos + 1, #String)
end

-- function table.has_key(array, key)
--     if Type.is.table(key) and key.colname then
--         key = key.colname
--     end

--     for array_key, _  in pairs(array) do
--         if array_key == key then
--             return true
--         end
--     end
-- end

local function _tableHasValue(array, value)
    if Type.is.table(value) and value.colname then
        value = value.colname
    end

    for _, array_value  in tablePairs(array) do
        if array_value == value then
            return true
        end
    end
end

local function _tableJoin(array, separator)
    local result = ""
    local counter = 0

    if not separator then
        separator = ","
    end

    for _, value in tablePairs(array) do
        if counter ~= 0 then
            value = separator .. value
        end

        result = result .. value
        counter = counter + 1
    end

    return result
end

--[[orm.class.property]]
------------------------------------------------------------------------------

-- Function for create column functions
local function Property(args)
    return function (colname)
        local column_func = {
            -- class type
            __classtype__ = AGGREGATOR,

            -- Asc column name
            colname = colname,

            -- concatenate methods
            __concat = function (left_part, right_part)
                return tostring(left_part) .. tostring(right_part)
            end,

            __tostring = args.parse or self.parse
        }

        setmetatable(column_func, {__tostring = column_func.__tostring,
                                   __concat = column_func.__concat})
        return column_func
    end
end

--[[orm.tools.func]]
------------------------------------------------------------------------------

local OrderBy = {}

OrderBy.ASC = Property({
    parse = function (self)
        return "`" .. self.__table__ .. "`.`" .. self.colname .. "` ASC"
    end
})

OrderBy.DESC = Property({
    parse = function (self)
        return "`" .. self.__table__ .. "`.`" .. self.colname .. "` DESC"
    end
})

OrderBy.MAX = Property({
    parse = function (self)
        return "MAX(`" .. self.__table__ .. "`.`" .. self.colname .. "`)"
    end
})

OrderBy.MIN = Property({
    parse = function (self)
        return "MIN(`" .. self.__table__ .. "`.`" .. self.colname .. "`)"
    end
})

OrderBy.COUNT = Property({
    parse = function (self)
        return "COUNT(`" .. self.__table__ .. "`.`" .. self.colname .. "`)"
    end
})

OrderBy.SUM = Property({
    parse = function (self)
        return "SUM(" .. self.colname .. ")"
    end
})

-- Escape text values to prevent sql injection
local function escapeValue(own_table, colname, colvalue)

  local coltype = own_table:get_column(colname)
  if coltype and coltype.settings.escape_value then

    local fieldtype = coltype.field.__type__
    if fieldtype:find("text") or fieldtype:find("char") then

      if (DB.type == "sqlite3" or DB.type == "mysql" or DB.type == "postgresql") then

        -- See https://keplerproject.github.io/luasql/manual.html for a list of
        -- database drivers that support this method
        colvalue = dbInstance.connect:escape(colvalue)
      elseif (DB.type == "oracle") then
        BACKTRACE(WARNING, "Can't autoescape values for oracle databases (Tried to escape field `" .. colname .. "`)");
      end

    end

  end

  return colvalue;

end


--[[orm.class.select]]
------------------------------------------------------------------------------

-- For WHERE equations ends
local LESS_THEN = "__lt"
local EQ_OR_LESS_THEN = "__lte"
local MORE_THEN = "__gt"
local EQ_OR_MORE_THEN = "__gte"
local IN = "__in"
local NOT_IN = "__notin"
local IS_NULL = '__null'

-- Joining types
local JOIN = {
    INNER = 'i',
    LEFT = 'l',
    RIGHT = 'r',
    FULL = 'f'
}

local Select = function(own_table)
    return {
        ------------------------------------------------
        --          Table info varibles               --
        ------------------------------------------------
        -- Link for table instance
        own_table = own_table,

        -- Create select rules
        _rules = {
            -- Where equation rules
            where = {},
            -- Having equation rules
            having = {},
            -- limit
            limit = nil,
            -- offset
            offset = nil,
            -- order columns list
            order = {},
            -- group columns list
            group = {},
            --Columns rules
            columns = {
                -- Joining tables rules
                join = {},
                -- including columns list
                include = {},
            }
        },

        ------------------------------------------------
        --          Private methods                   --
        ------------------------------------------------

        -- Build correctly equation for SQL searching
        _build_equation = function (self, colname, value)
            local result = ""
            local table_column
            local rule
            local _in

            -- Special conditions that need no value escaping
            if _endswith(colname, IS_NULL) then
                colname = _cutend(colname, IS_NULL)

                if value then
                    result = " IS NULL"
                else
                    result = " NOT NULL"
                end

            elseif _endswith(colname, IN) or _endswith(colname, NOT_IN) then
                rule = _endswith(colname, IN) and IN or NOT_IN

                if type(value) == "table" and #value > 0 then
                    colname = _cutend(colname, rule)
                    table_column = self.own_table:get_column(colname)
                    _in = {}

                    for counter, val in tablePairs(value) do
                        _in[#_in + 1] = table_column.field.as(val)
                    end

                    if rule == IN then
                        result = " IN (" .. _tableJoin(_in) .. ")"
                    elseif rule == NOT_IN then
                        result = " NOT IN (" .. _tableJoin(_in) .. ")"
                    end

                end

            else

                -- Conditions that need value escaping when it's enabled
                local conditionPrepend = ""

                if _endswith(colname, LESS_THEN) and Type.is.number(value) then
                    colname = _cutend(colname, LESS_THEN)
                    conditionPrepend = " < "

                elseif _endswith(colname, MORE_THEN) and Type.is.number(value) then
                    colname = _cutend(colname, MORE_THEN)
                    conditionPrepend = " > "

                elseif _endswith(colname, EQ_OR_LESS_THEN) and Type.is.number(value) then
                    colname = _cutend(colname, EQ_OR_LESS_THEN)
                    conditionPrepend = " <= "

                elseif _endswith(colname, EQ_OR_MORE_THEN) and Type.is.number(value) then
                    colname = _cutend(colname, EQ_OR_MORE_THEN)
                    conditionPrepend = " >= "

                else
                    conditionPrepend = " = "
                end

                value = escapeValue(self.own_table, colname, value)
                table_column = self.own_table:get_column(colname)
                result = conditionPrepend .. table_column.field.as(value)

            end

            if self.own_table:has_column(colname) then
                local parse_column, _ = self.own_table:column(colname)
                result = parse_column .. result
            end

            return result
        end,

        -- Need for ASC and DESC columns
        _update_col_names = function (self, list_of_cols)
            local tablename = self.own_table.__tablename__
            local result = {}
            local parsed_column

            for _, col in tablePairs(list_of_cols) do
                if Type.is.table(col) and col.__classtype__ == AGGREGATOR then
                    col.__table__ = self.own_table.__tablename__
                    result[#result + 1] = col
                else
                    parsed_column, _ = self.own_table:column(col)
                    result[#result + 1] = parsed_column
                end
            end

            return result
        end,

        -- Build condition for equation rules
        ---------------------------------------------------
        -- @rules {table} list of columns
        -- @start_with {string} WHERE or HAVING
        --
        -- @retrun {string} parsed string for select equation
        ---------------------------------------------------
        _condition = function (self, rules, start_with)
            local counter = 0
            local condition = ""
            local _equation

            condition = condition .. start_with

            -- TODO: add OR
            for colname, value in tablePairs(rules) do
                _equation = self:_build_equation(colname, value)

                if counter ~= 0 then
                     _equation = "AND " .. _equation
                end

                condition = condition .. " " .. _equation
                counter = counter + 1
            end

            return condition
        end,

        _has_foreign_key_table = function (self, left_table, right_table)
            for _, key in tablePairs(left_table.__foreign_keys) do
                if key.settings.to == right_table then
                    return true
                end
            end
        end,

        -- Build join tables rules
        _build_join = function (self)
            local result_join = ""
            local unique_tables = {}
            local left_table, right_table, mode
            local join_mode, colname
            local parsed_column, _
            local tablename

            for _, value in tablePairs(self._rules.columns.join) do
                left_table = value[1]
                right_table = value[2]
                mode = value[3]
                tablename = left_table.__tablename__

                if mode == JOIN.INNER then
                    join_mode = "INNER JOIN"

                elseif mode == JOIN.LEFT then
                    join_mode = "LEFT OUTER JOIN"

                elseif mode == JOIN.RIGHT then
                    join_mode = "RIGHT OUTER JOIN"

                elseif mode == JOIN.FULL then
                    join_mode = "FULL OUTER JOIN"

                else
                    BACKTRACE(WARNING, "Not valid join mode " .. mode)
                end

                if self:_has_foreign_key_table(right_table, left_table) then
                    left_table, right_table = right_table, left_table
                    tablename = right_table.__tablename__

                elseif not self:_has_foreign_key_table(right_table, left_table) then
                    BACKTRACE(WARNING, "Not valid tables links")
                end

                for _, key in tablePairs(left_table.__foreign_keys) do
                    if key.settings.to == right_table then
                        colname = key.name

                        result_join = result_join .. " \n" .. join_mode .. " `" ..
                                      tablename .. "` ON "

                        parsed_column, _ = left_table:column(colname)
                        result_join = result_join .. parsed_column

                        parsed_column, _ = right_table:column(ID)
                        result_join = result_join .. " = " .. parsed_column

                        break
                    end
                end
            end

            return result_join
        end,

        -- String with including data in select
        --------------------------------------------
        -- @own_table {table|nil} Table instance
        --
        -- @return {string} comma separated fields
        --------------------------------------------
        _build_including = function (self, own_table)
            local include = {}
            local colname_as, colname

            if not own_table then
                own_table = self.own_table
            end

            -- get current column
            for _, column in tablePairs(own_table.__colnames) do
                colname, colname_as = own_table:column(column.name)
                include[#include + 1] = colname .. " AS " .. colname_as
            end

            include = _tableJoin(include)

            return include
        end,

        -- Method for build select with rules
        _select = function (self)
            local including = self:_build_including()
            local joining = ""
            local _select
            local tablename
            local condition
            local where
            local rule
            local join

            --------------------- Include Columns To Select ------------------
            _select = "SELECT " .. including

            -- Add join rules
            if #self._rules.columns.join > 0 then
                local unique_tables = { self.own_table }
                local join_tables = {}
                local left_table, right_table

                for _, values in tablePairs(self._rules.columns.join) do
                    left_table = values[1]
                    right_table = values[2]

                    if not _tableHasValue(unique_tables, left_table) then
                        unique_tables[#unique_tables + 1] = left_table
                        _select = _select .. ", " .. self:_build_including(left_table)
                    end

                    if not _tableHasValue(unique_tables, right_table) then
                        unique_tables[#unique_tables + 1] = right_table
                        _select = _select .. ", " .. self:_build_including(right_table)
                    end
                end

                join = self:_build_join()
            end

            -- Check aggregators in select
            if #self._rules.columns.include > 0 then
                local aggregators = {}
                local aggregator, as

                for _, value in tablePairs(self._rules.columns.include) do
                    _, as = own_table:column(value.as)
                    aggregators[#aggregators + 1] = value[1] .. " AS " .. as
                end

                _select = _select .. ", " .. _tableJoin(aggregators)
            end
            ------------------- End Include Columns To Select ----------------

            _select = _select .. " FROM `" .. self.own_table.__tablename__ .. "`"

            if join then
                _select = _select .. " " .. join
            end

            -- Build WHERE
            if next(self._rules.where) then
                condition = self:_condition(self._rules.where, "\nWHERE")
                _select = _select .. " " .. condition
            end

            -- Build GROUP BY
            if #self._rules.group > 0 then
                rule = self:_update_col_names(self._rules.group)
                rule = _tableJoin(rule)
                _select = _select .. " \nGROUP BY " .. rule
            end

            -- Build HAVING
            if next(self._rules.having) and self._rules.group then
                condition = self:_condition(self._rules.having, "\nHAVING")
                _select = _select .. " " .. condition
            end

            -- Build ORDER BY
            if #self._rules.order > 0 then
                rule = self:_update_col_names(self._rules.order)
                rule = _tableJoin(rule)
                _select = _select .. " \nORDER BY " .. rule
            end

            -- Build LIMIT
            if self._rules.limit then
                _select = _select .. " \nLIMIT " .. self._rules.limit
            end

            -- Build OFFSET
            if self._rules.offset then
                _select = _select .. " \nOFFSET " .. self._rules.offset
            end

            return dbInstance:rows(_select, self.own_table)
        end,

        -- Add column to table
        -------------------------------------------------
        -- @col_table {table} table with column names
        -- @colname {string/table} column name or list of column names
        -------------------------------------------------
        _add_col_to_table = function (self, col_table, colname)
            if Type.is.str(colname) and self.own_table:has_column(colname) then
                col_table[#col_table + 1] = colname

            elseif Type.is.table(colname) then
                for _, column in tablePairs(colname) do
                    if (Type.is.table(column) and column.__classtype__ == AGGREGATOR
                    and self.own_table:has_column(column.colname))
                    or self.own_table:has_column(column) then
                        col_table[#col_table + 1] = column
                    end
                end

            else
                BACKTRACE(WARNING, "Not a string and not a table (" ..
                                   tostring(colname) .. ")")
            end
        end,

        --------------------------------------------------------
        --                   Column filters                   --
        --------------------------------------------------------

        -- Including columns to select query
        include = function (self, column_list)
            if Type.is.table(column_list) then
                local tbl = self._rules.columns.include
                for _, value in tablePairs(column_list) do
                    if Type.is.table(value) and value.as and value[1]
                    and value[1].__classtype__ == AGGREGATOR then
                        tbl[#tbl + 1] = value
                    else
                        BACKTRACE(WARNING, "Not valid aggregator syntax")
                    end
                end
            else
                BACKTRACE(WARNING, "You can include only table type data")
            end

            return self
        end,

        --------------------------------------------------------
        --              Joining tables methods                --
        --------------------------------------------------------

        -- By default, join is INNER JOIN command
        _join = function (self, left_table, MODE, right_table)
            if not right_table then
                right_table = self.own_table
            end

            if left_table.__tablename__ then
                local tbl = self._rules.columns.join
                tbl[#tbl + 1] = {left_table, right_table, MODE}
            else
                BACKTRACE(WARNING, "Not table in join")
            end

            return self
        end,

        join = function (self, left_table, right_table)
            self:_join(left_table, JOIN.INNER, right_table)
            return self
        end,

        -- left outer joining command
        left_join = function (self, left_table, right_table)
            self:_join(left_table, JOIN.LEFT, right_table)
            return self
        end,

        -- right outer joining command
        right_join = function (self, left_table, right_table)
            self:_join(left_table, JOIN.RIGHT, right_table)
            return self
        end,

        -- full outer joining command
        full_join = function (self, left_table, right_table)
            self:_join(left_table, JOIN.FULL, right_table)
            return self
        end,

        --------------------------------------------------------
        --              Select building methods               --
        --------------------------------------------------------

        -- SQL Where query rules
        where = function (self, args)
            for col, value in tablePairs(args) do
                self._rules.where[col] = value
            end

            return self
        end,

        -- Set returned data limit
        limit = function (self, count)
            if Type.is.int(count) then
                self._rules.limit = count
            else
                BACKTRACE(WARNING, "You try set limit to not integer value")
            end

            return self
        end,

        -- From which position start get data
        offset = function (self, count)
            if Type.is.int(count) then
                self._rules.offset = count
            else
                BACKTRACE(WARNING, "You try set offset to not integer value")
            end

            return self
        end,

        -- Order table
        order_by = function (self, colname)
            self:_add_col_to_table(self._rules.order, colname)
            return self
        end,

        -- Group table
        group_by = function (self, colname)
            self:_add_col_to_table(self._rules.group, colname)
            return self
        end,

        -- Having
        having = function (self, args)
            for col, value in tablePairs(args) do
                self._rules.having[col] = value
            end

            return self
        end,

        --------------------------------------------------------
        --                 Update data methods                --
        --------------------------------------------------------

        update = function (self, data)
            if Type.is.table(data) then
                local _update = "UPDATE `" .. self.own_table.__tablename__ .. "`"
                local _set = ""
                local coltype
                local _set_tbl = {}
                local i=1

                for colname, new_value in tablePairs(data) do
                    coltype = self.own_table:get_column(colname)

                    if coltype and coltype.field.validator(new_value) then
                        _set = _set .. " `" .. colname .. "` = " ..
                              coltype.field.as(new_value)
                        _set_tbl[i] = " `" .. colname .. "` = " ..
                                coltype.field.as(new_value)
                        i=i+1
                    else
                        BACKTRACE(WARNING, "Can't update value for column `" ..
                                            Type.to.str(colname) .. "`")
                    end
                end

                -- Build WHERE
                local _where
                if next(self._rules.where) then
                    _where = self:_condition(self._rules.where, "\nWHERE")
                else
                    BACKTRACE(INFO, "No 'where' statement. All data update!")
                end

                if _set ~= "" then
                    if #_set_tbl<2 then
                        _update = _update .. " SET " .. _set .. " " .. _where
                    else
                        _update = _update .. " SET " .. table.concat(_set_tbl,",") .. " " .. _where
                    end

                    dbInstance:execute(_update)
                else
                    BACKTRACE(WARNING, "No table columns for update")
                end
            else
                BACKTRACE(WARNING, "No data for global update")
            end
        end,

        --------------------------------------------------------
        --                 Delete data methods                --
        --------------------------------------------------------

        delete = function (self)
            local _delete = "DELETE FROM `" .. self.own_table.__tablename__ .. "` "

            -- Build WHERE
            if next(self._rules.where) then
                _delete = _delete .. self:_condition(self._rules.where, "\nWHERE")
            else
                BACKTRACE(WARNING, "Try delete all values")
            end

            dbInstance:execute(_delete)
        end,

        --------------------------------------------------------
        --              Get select data methods               --
        --------------------------------------------------------

        -- Return one value
        first = function (self)
            self._rules.limit = 1
            local data = self:all()

            if data:count() == 1 then
                return data[1]
            end
        end,

        -- Return list of values
        all = function (self)
            local data = self:_select()
            return QueryList(self.own_table, data)
        end
    }
end

--[[orm.class.query]]
------------------------------------------------------------------------------

-- Creates an instance to retrieve and manage a
-- string table with the database
---------------------------------------------------
-- @own_table {table} parent table instace
-- @data {table} data returned by the query to the database
--
-- @return {table} database query instance
---------------------------------------------------
function Query(own_table, data)
    local query = {
        ------------------------------------------------
        --          Table info varibles               --
        ------------------------------------------------

        -- Table instance
        own_table = own_table,

        -- Column data
        -- Structure example of one column
        -- fieldname = {
        --     old = nil,
        --     new = nil
        -- }
        _data = {},

        -- Data only for read mode
        _readonly = {},

        ------------------------------------------------
        --             Metamethods                    --
        ------------------------------------------------

        -- Get column value
        -----------------------------------------
        -- @colname {string} column name in table
        --
        -- @return {string|boolean|number|nil} column value
        -----------------------------------------
        _get_col = function (self, colname)
            if self._data[colname] and self._data[colname].new then
                return self._data[colname].new

            elseif self._readonly[colname] then
                return self._readonly[colname]
            end
        end,

        -- Set column new value
        -----------------------------------------
        -- @colname {string} column name in table
        -- @colvalue {string|number|boolean} new column value
        -----------------------------------------
        _set_col = function (self, colname, colvalue)
            local coltype

            if self._data[colname] and self._data[colname].new and colname ~= ID then
                coltype = self.own_table:get_column(colname)

                if coltype and coltype.field.validator(colvalue) then
                    self._data[colname].old = self._data[colname].new
                    self._data[colname].new = colvalue
                else
                    BACKTRACE(WARNING, "Not valid column value for update")
                end
            end
        end,

        ------------------------------------------------
        --             Private methods                --
        ------------------------------------------------

        -- Add new row to table
        _add = function (self)
            local insert = "INSERT INTO `" .. self.own_table.__tablename__ .. "` ("
            local counter = 0
            local values = ""
            local _connect
            local value
            local colname

            for _, table_column in tablePairs(self.own_table.__colnames) do
                colname = table_column.name

                if colname ~= ID then

                    -- If value exist correct value
                    if self[colname] ~= nil then
                        value = self[colname]

                        if table_column.field.validator(value) then
                            value = escapeValue(self.own_table, colname, value)
                            value = table_column.field.as(value)
                        else
                            BACKTRACE(WARNING, "Wrong type for table '" ..
                                                self.own_table.__tablename__ ..
                                                "' in column '" .. tostring(colname) .. "'")
                            return false
                        end

                    -- Set default value
                    elseif table_column.settings.default then
                        value = table_column.field.as(table_column.settings.default)

                    else
                        value = "NULL"
                    end

                    colname = "`" .. colname .. "`"

                    -- TODO: save in correct type
                    if counter ~= 0 then
                        colname = ", " .. colname
                        value = ", " .. value
                    end

                    values = values .. value
                    insert = insert .. colname

                    counter = counter + 1
                end
            end

            insert = insert .. ") \n\t    VALUES (" .. values .. ")"

            -- TODO: return valid ID
            _connect = dbInstance:insert(insert)

            self._data.id = {new = _connect}
        end,

        -- Update data in database
        _update = function (self)
            local update = "UPDATE `" .. self.own_table.__tablename__ .. "` "
            local equation_for_set = {}
            local set, coltype

            for colname, colinfo in tablePairs(self._data) do
                if colinfo.old ~= colinfo.new and colname ~= ID then
                    coltype = self.own_table:get_column(colname)

                    if coltype and coltype.field.validator(colinfo.new) then

                        local colvalue = escapeValue(self.own_table, colname, colinfo.new)
                        set = " `" .. colname .. "` = " .. coltype.field.as(colvalue)

                        equation_for_set[#equation_for_set + 1] = set
                    else
                        BACKTRACE(WARNING, "Can't update value for column `" ..
                                           Type.to.str(colname) .. "`")
                    end
                end
            end

            set = _tableJoin(equation_for_set, ",")

            if set ~= "" then
                update = update .. " SET " .. set .. "\n\t    WHERE `" .. ID .. "` = " .. self.id
                dbInstance:execute(update)
            end
        end,

        ------------------------------------------------
        --             User methods                   --
        ------------------------------------------------

        -- save row
        save = function (self)
            if self.id then
                self:_update()
            else
                self:_add()
            end
        end,

        -- delete row
        delete = function (self)
            local delete, result

            if self.id then
                delete = "DELETE FROM `" .. self.own_table.__tablename__ .. "` "
                delete = delete .. "WHERE `" .. ID .. "` = " .. self.id

                dbInstance:execute(delete)
            end
            self._data = {}
        end
    }

    if data then
        local current_table

        for colname, colvalue in tablePairs(data) do
            if query.own_table:has_column(colname) then
                colvalue = query.own_table:get_column(colname)
                                          .field.to_type(colvalue)
                query._data[colname] = {
                    new = colvalue,
                    old = colvalue
                }
            else
                if All_Tables[colname] then
                    current_table = All_Tables[colname]
                    colvalue = Query(current_table, colvalue)

                    query._readonly[colname .. "_all"] = QueryList(current_table, {})
                    query._readonly[colname .. "_all"]:add(colvalue)

                end

                query._readonly[colname] = colvalue
            end
        end
    else
        BACKTRACE(INFO, "Create empty row instance for table '" ..
                        self.own_table.__tablename__ .. "'")
    end

    setmetatable(query, {__index = query._get_col,
                         __newindex = query._set_col})

    return query
end

--[[orm.class.query_list]]
------------------------------------------------------------------------------

function QueryList(own_table, rows)
    local current_query
    local _query_list = {
        ------------------------------------------------
        --          Table info varibles               --
        ------------------------------------------------

        --class name
        __classname__ = QUERY_LIST,

        -- Own Table
        own_table = own_table,

        -- Stack of data rows
        _stack = {},

        ------------------------------------------------
        --             Metamethods                    --
        ------------------------------------------------

        -- Get n-th position value from Query stack
        ------------------------------------------------
        -- @position {integer} position element is stack
        --
        -- @return {Query Instance} Table row instance
        -- in n-th position
        ------------------------------------------------
        __index = function (self, position)
            if Type.is.int(position) and position >= 1 then
                return self._stack[position]
            end
        end,

        __call = function (self)
            return tablePairs(self._stack)
        end,

        ------------------------------------------------
        --             User methods                   --
        ------------------------------------------------

        -- Get Query instance by id
        ------------------------------------------------
        -- @id {integer} table data row identifier
        --
        -- @return {table/nil} get Query instance or nil if
        -- instance is not exists
        ------------------------------------------------
        with_id = function (self, id)
            if Type.is.int(id) then
                for _, query in tablePairs(self) do
                    if query.id == id then
                        return query
                    end
                end
            else
                BACKTRACE(WARNING, "ID `" .. id .. "` is not integer value")
            end
        end,

        -- Add new Query Instance to stack
        add = function (self, QueryInstance)
            self._stack[#self._stack + 1] = QueryInstance
        end,

        -- Get count of values in stack
        count = function (self)
            return #self._stack
        end,

        -- Remove from database all elements from stack
        delete = function (self)
            for _, query in tablePairs(self._stack) do
                query:delete()
            end

            self._stack = {}
        end
    }

    setmetatable(_query_list, {__index = _query_list.__index,
                               __len = _query_list.__len,
                               __call = _query_list.__call})

    for _, row in tablePairs(rows) do
        current_query = _query_list:with_id(Type.to.number(row.id))

        if current_query then
            for key, value in tablePairs(row) do
                if Type.is.table(value)
                and current_query._readonly[key .. "_all"] then
                    current_query._readonly[key .. "_all"]:add(
                        Query(All_Tables[key], value)
                    )
                end
            end
        else
            _query_list:add(Query(own_table, row))
        end
    end

    return _query_list
end

--[[orm.class.type]]
------------------------------------------------------------------------------

Type = {
    -- Check value for correct type
    ----------------------------------
    -- @value {any type} checked value
    --
    -- @return {boolean} get true if type is correct
    ----------------------------------
    is = {
        int = function (value)
            if type(value) == "number" then
                integer, fractional = math.modf(value)
                return fractional == 0
            end
        end,

        number = function (value)
            return type(value) == "number"
        end,

        str = function (value)
            return type(value) == "string"
        end,

        table = function (value)
            return type(value) == "table"
        end,
    },

    to = {
        number = function (value)
            return tonumber(value)
        end,

        str = function (value)
            return tostring(value)
        end
    }
}

--[[orm.class.field]]
------------------------------------------------------------------------------


local FieldBase = {
    -- Table column type
    __type__ = "varchar",

    -- Validator handler
    validator = function (self, value)
        return true
    end,

    -- Default parser
    as = function (value)
        return value
    end,

    to_type = Type.to.str,

    -- Call when create new field in some table
    register = function (self, args)
        if not args then
            args = {}
        end

        -- New field type
        -------------------------------------------
        -- @args {table}
        -- Table can have parametrs:
        --    @args.__type__ {string} some sql valid type
        --    @args.validator {function} type validator
        --    @args.as {function} return parse value
        -------------------------------------------
        local new_field_type = {
            -- some sql valid type
            __type__ = args.__type__ or self.__type__,

            -- Validator handler
            validator = args.validator or self.validator,

            -- Parse variable for equation
            as = args.as or self.as,

            -- Cast values to correct type
            to_type = args.to_type or self.to_type,

            -- Default settings for type
            settings = args.settings or {},

            -- Get new table column instance
            new = function (this, args)
                if not args then
                    args = {}
                end

                local new_self = {
                    -- link to field instance
                    field = this,

                    -- Column name
                    name = nil,

                    -- Parent table
                    __table__ = nil,

                    -- table column settings
                    settings = {
                        default = nil,
                        null = false,
                        unique = false,
                        max_length = nil,
                        primary_key = false,
                        escape_value = false
                    },

                    -- Return string for column type create
                    _create_type = function (this)
                        local _type = this.field.__type__

                        if this.settings.max_length and this.settings.max_length > 0 then
                            _type = _type .. "(" .. this.settings.max_length .. ")"
                        end

                        if this.settings.primary_key then
                            _type = _type .. " PRIMARY KEY"
                        end

                        if this.settings.auto_increment and DB.type ~= SQLITE then
                            _type = _type .. " AUTO_INCREMENT"
                        end

                        if this.settings.unique then
                            _type = _type .. " UNIQUE"
                        end

                        _type = _type .. (this.settings.null and " NULL"
                                                             or " NOT NULL")
                        return _type
                    end
                }

                -- Set Default settings

                --
                -- The content of the settings table must be copied because trying to copy a table
                -- directly will result in a reference to the original table, thus all
                -- instances of the same field type would have the same settings table.
                --
                for index, setting in tablePairs(new_self.field.settings) do
                  new_self.settings[index] = setting
                end

                -- Set settings for column
                if args.max_length then
                    new_self.settings.max_length = args.max_length
                end

                if args.null ~= nil then
                    new_self.settings.null = args.null
                end

                if new_self.settings.foreign_key and args.to then
                    new_self.settings.to = args.to
                end

                if args.escape_value then
                  new_self.settings.escape_value = true
                end

                return new_self
            end
        }

        setmetatable(new_field_type, {__call = new_field_type.new})

        return new_field_type
    end
}


--[[orm.tools.fields]]
------------------------------------------------------------------------------


------------------------------------------------------------------------------
--                                Field Types                               --
------------------------------------------------------------------------------
local function save_as_str(str)
    return "'" .. str .. "'"
end

local Field = {}

-- The "Field" class will be used to search a table index that the "field" class doesn't have.
-- This way field:register() will call the same function like Field:register() and the register
-- function has access to the default values for the field configuration.
setmetatable(Field, {__index = FieldBase});


Field.PrimaryField = FieldBase:register({
    __type__ = "integer",
    validator = Type.is.int,
    settings = {
        null = true,
        primary_key = true,
        auto_increment = true
    },
    to_type = Type.to.number
})

Field.IntegerField = FieldBase:register({
    __type__ = "integer",
    validator = Type.is.int,
    to_type = Type.to.number
})

Field.CharField = FieldBase:register({
    __type__ = "varchar",
    validator = Type.is.str,
    as = save_as_str
})

Field.TextField = FieldBase:register({
    __type__ = "text",
    validator = Type.is.str,
    as = save_as_str
})

Field.BooleandField = FieldBase:register({
    __type__ = "bool"
})

Field.DateTimeField = FieldBase:register({
    __type__ = "integer",
    validator = function (value)
        if (Type.is.table(value) and value.isdst ~= nil)
        or Type.is.int(value) then
            return true
        end
    end,
    as = function (value)
        return Type.is.int(value) and value or os.time(value)
    end,
    to_type = function (value)
        return os.date("*t", Type.to.number(value))
    end
})

Field.ForeignKey = FieldBase:register({
    __type__ = "integer",
    settings = {
        null = true,
        foreign_key = true
    },
    to_type = Type.to.number
})

--[[orm.class.table]]
------------------------------------------------------------------------------

local Table = {
    -- database table name
    __tablename__ = nil,

    -- Foreign Keys list
    foreign_keys = {},
}

-- This method create new table
-------------------------------------------
-- @table_instance {table} class Table instance
--
-- @table_instance.__tablename__ {string} table name
-- @table_instance.__colnames {table} list of column instances
-- @table_instance.__foreign_keys {table} list of foreign key
--                                        column instances
-------------------------------------------
function Table:create_table(table_instance)
    -- table information
    local tablename = table_instance.__tablename__
    local columns = table_instance.__colnames
    local foreign_keys = table_instance.__foreign_keys

    BACKTRACE(INFO, "Start create table: " .. tablename)

    -- other variables
    local create_query = "CREATE TABLE IF NOT EXISTS `" .. tablename .. "` \n("
    local counter = 0
    local column_query
    local result

    for _, coltype in tablePairs(columns) do
        column_query = "\n     `" .. coltype.name .. "` " .. coltype:_create_type()

        if counter ~= 0 then
            column_query = "," .. column_query
        end

        create_query = create_query .. column_query
        counter = counter + 1
    end

    for _, coltype in tablePairs(foreign_keys) do
        create_query = create_query .. ",\n     FOREIGN KEY(`" ..
                       coltype.name .. "`)" .. " REFERENCES `" ..
                       coltype.settings.to.__tablename__ ..
                       "`(`id`)"
    end

    create_query = create_query .. "\n)"

    dbInstance:execute(create_query)
end

-- Create new table instance
--------------------------------------
-- @args {table} must have __tablename__ key
-- and other must be a column names
--------------------------------------
function Table.new(self, args)
    local colnames = {}
    local create_query

    self.__tablename__ = args.__tablename__
    args.__tablename__ = nil

    -- Determine the column creation order
    -- This is necessary because tables in lua have no order
    self.__columnCreateOrder__ = { "id" };

    local customColumnCreateOrder = args.__columnCreateOrder__;
    args.__columnCreateOrder__ = nil;

    local tbl = self.__columnCreateOrder__    
    if (customColumnCreateOrder) then
      for _, colname in ipairs(customColumnCreateOrder) do
        -- Add only existing columns to the column create order
        if (args[colname]) then
          tbl[#tbl + 1] = colname
        end
      end
    end

    for colname, coltype in tablePairs(args) do

      -- Add the columns that are defined but missing from the column create order
      if (not _tableHasValue(self.__columnCreateOrder__, colname)) then
        tbl[#tbl + 1] = colname
      end
    end


    local Table_instance = {
        ------------------------------------------------
        --            Table info variables            --
        ------------------------------------------------

        -- SQL table name
        __tablename__ = self.__tablename__,

        -- list of column names
        __colnames = {},

        -- Foreign keys list
        __foreign_keys = {},

        ------------------------------------------------
        --                Metamethods                 --
        ------------------------------------------------

        -- If try get value by name "get" it return Select class instance
        __index = function (self, key)
            if key == "get" then
                return Select(self)
            end

            local old_index = self.__index
            setmetatable(self, {__index = nil})

            key = self[key]

            setmetatable(self, {__index = old_index, __call = self.create})

            return key
        end,

        -- Create new row instance
        -----------------------------------------
        -- @data {table} parsed query answer data
        --
        -- @retrun {table} Query instance
        -----------------------------------------
        create = function (self, data)
            return Query(self, data)
        end,

        ------------------------------------------------
        --          Methods which using               --
        ------------------------------------------------

        -- parse column in correct types
        column = function (self, column)
            local tablename = self.__tablename__

            if Type.is.table(column) and column.__classtype__ == AGGREGATOR then
                column.colname = tablename .. column.colname
                column = column .. ""
            end

            return "`" .. tablename .. "`.`" .. column .. "`",
                   tablename .. "_" .. column
        end,

        -- Check column in table
        -----------------------------------------
        -- @colname {string} column name
        --
        -- @return {boolean} get true if column exist
        -----------------------------------------
        has_column = function (self, colname)
            for _, table_column in tablePairs(self.__colnames) do
                if table_column.name == colname then
                    return true
                end
            end

            BACKTRACE(WARNING, "Can't find column '" .. tostring(colname) ..
                               "' in table '" .. self.__tablename__ .. "'")
        end,

        -- get column instance by name
        -----------------------------------------
        -- @colname {string} column name
        --
        -- @return {table} get column instance if column exist
        -----------------------------------------
        get_column = function (self, colname)
            for _, table_column in tablePairs(self.__colnames) do
                if table_column.name == colname then
                    return table_column
                end
            end

            BACKTRACE(WARNING, "Can't find column '" .. tostring(column) ..
                               "' in table '" .. self.__tablename__ .. "'")
        end
    }

    -- Add default column 'id'
    args.id = Field.PrimaryField({auto_increment = true})

    local colTbl = Table_instance.__colnames
    local keyTbl = Table_instance.__foreign_keys

    -- copy column arguments to new table instance
    for _, colname in ipairs(self.__columnCreateOrder__) do

        local coltype = args[colname];
        coltype.name = colname
        coltype.__table__ = Table_instance

        colTbl[#colTbl + 1] = coltype

        if coltype.settings.foreign_key then
            keyTbl[#keyTbl + 1] = coltype
        end
    end

    setmetatable(Table_instance, {
        __call = Table_instance.create,
        __index = Table_instance.__index
    })

    All_Tables[self.__tablename__] = Table_instance

    -- Create new table if needed
    if DB.new then
        self:create_table(Table_instance)
    end

    return Table_instance
end

setmetatable(Table, {__call = Table.new})

--[[orm.class.model]]
------------------------------------------------------------------------------

------------------------------------------------------------------------------
--                              Model Settings                              --
------------------------------------------------------------------------------

if not DB then
    print("[SQL:Startup] Can't find global database settings variable 'DB'. Creating empty one.")
    DB = {}
end

DB = {
    -- ORM settings
    new = (DB.new == true),
    DEBUG = (DB.DEBUG == true),
    backtrace = (DB.backtrace == true),
    -- database settings
    type = DB.type or "sqlite3",
    -- if you use sqlite set database path value
    -- if not set a database name
    name = DB.name or "database.db",
    -- not sqlite db settings
    host = DB.host or nil,
    port = DB.port or nil,
    username = DB.username or nil,
    password = DB.password or nil
}

local SqlEnv, _connect

-- Get database by settings
if DB.type == SQLITE then
    local luasql = require("luasql.sqlite3")
    SqlEnv = luasql.sqlite3()
    _connect = SqlEnv:connect(DB.name)

elseif DB.type == MYSQL then
    local luasql = require("luasql.mysql")
    SqlEnv = luasql.mysql()
    print(DB.name, DB.username, DB.password, DB.host, DB.port)
    _connect = SqlEnv:connect(DB.name, DB.username, DB.password, DB.host, DB.port)

elseif DB.type == POSTGRESQL then
    local luasql = require("luasql.postgres")
    SqlEnv = luasql.postgres()
    print(DB.name, DB.username, DB.password, DB.host, DB.port)
    _connect = SqlEnv:connect(DB.name, DB.username, DB.password, DB.host, DB.port)

else
    BACKTRACE(ERROR, "Database type not suported '" .. tostring(DB.type) .. "'")
end

if not _connect then
    BACKTRACE(ERROR, "Connect problem!")
end

-- if DB.new then
--     BACKTRACE(INFO, "Remove old database")

--     if DB.type == SQLITE then
--         os.remove(DB.name)
--     else
--         _connect:execute('DROP DATABASE `' .. DB.name .. '`')
--     end
-- end

------------------------------------------------------------------------------
--                               Database                                   --
------------------------------------------------------------------------------

-- Database settings
dbInstance = {
    -- Database connect instance
    connect = _connect,

    -- Execute SQL query
    execute = function (self, query)
        BACKTRACE(DEBUG, query)

        local result = self.connect:execute(query)

        if result then
            return result
        else
            BACKTRACE(WARNING, "Wrong SQL query")
        end
    end,

    -- Return insert query id
    insert = function (self, query)
        local _cursor = self:execute(query)
        return 1
    end,

    -- get parced data
    rows = function (self, query, own_table)
        local _cursor = self:execute(query)
        local data = {}
        local current_row = {}
        local current_table
        local row

        if _cursor then
            row = _cursor:fetch({}, "a")

            while row do
                for colname, value in tablePairs(row) do
                    current_table, colname = _divided_into(colname, "_")

                    if current_table == own_table.__tablename__ then
                        current_row[colname] = value
                    else
                        if not current_row[current_table] then
                            current_row[current_table] = {}
                        end

                        current_row[current_table][colname] = value
                    end
                end

                data[#data + 1] = current_row

                current_row = {}
                row = _cursor:fetch({}, "a")
            end

        end

        return data
    end
}

return { Table, Field, tablePairs, OrderBy }

