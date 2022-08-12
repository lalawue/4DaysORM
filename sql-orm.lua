local pairs = pairs
local type = type
local setmetatable = setmetatable
local tonumber = tonumber
local tostring = tostring
local mathmodf = math.modf
local next = next
local strsub = string.sub
local strlen = string.len
local strfind = string.find
local strchar = string.char
local strbyte = string.byte
local strfmt = string.format
local kID = "id"
local kAGGREGATOR = "aggregator"
local kDBType = { SQLITE = "sqlite3", ORACLE = "oracle", MYSQL = "mysql", POSTGRESQL = "postgresql" }
local kWhere = { LESS_THEN = "__lt", EQ_OR_LESS_THEN = "__lte", MORE_THEN = "__gt", EQ_OR_MORE_THEN = "__gte", IN = "__in", NOT_IN = "__notin", IS_NULL = "__null" }
local kJoin = { JOIN_INNER = 'i', JOIN_LEFT = 'l', JOIN_RIGHT = 'r', JOIN_FULL = 'f' }
local kLog = { ERROR = 'e', WARNING = 'w', INFO = 'i', DEBUG = 'd' }
local G_DB_Ins_Tbl = {  }
local function _endWith(ss, se)
	return se == '' or strsub(ss, -strlen(se)) == se
end
local function _cutEnd(ss, se)
	return se == '' and ss or strsub(ss, 0, -#se - 1)
end
local function _dividedInto(ss, sep)
	local s, e = strfind(ss, sep)
	return strsub(ss, 1, s - 1), strsub(ss, e + 1, #ss)
end
local function _isInt(value)
	if type(value) == "number" then
		local integer, fractional = mathmodf(value)
		return fractional == 0
	end
end
local function _isNumber(value)
	return type(value) == "number"
end
local function _isStr(value)
	return type(value) == "string"
end
local function _isTable(value)
	return type(value) == "table"
end
local function _isBool(value)
	return type(value) == "boolean"
end
local function _toNumber(value)
	return tonumber(value)
end
local function _toStr(value)
	return tostring(value)
end
local function _tableHasValue(array, value)
	if _isTable(value) and value.colname then
		value = value.colname
	end
	for _, array_value in ipairs(array) do
		if array_value == value then
			return true
		end
	end
end
local function _tableJoin(array)
	local result = ""
	local counter = 0
	local separator = ','
	for _, value in ipairs(array) do
		if counter > 0 then
			value = separator .. value
		end
		result = result .. value
		counter = counter + 1
	end
	return result
end
local function _saveAsStr(str)
	return "'" .. str .. "'"
end
local function newProperty(parse_fn)
	return function(col_name)
		local ins = { cls_type = kAGGREGATOR, col_name = col_name }
		return setmetatable(ins, { __tostring = parse_fn, __concat = function(l, r)
			return tostring(l) .. tostring(r)
		end })
	end
end
local DBOrderBy = { ASC = newProperty(function(self)
	return "`" .. self.tbl_name .. "`.`" .. self.col_name .. "` ASC"
end), DESC = newProperty(function(self)
	return "`" .. self.tbl_name .. "`.`" .. self.col_name .. "` DESC"
end), MAX = newProperty(function(self)
	return "MAX(`" .. self.tbl_name .. "`.`" .. self.col_name .. "`)"
end), MIN = newProperty(function(self)
	return "MIN(`" .. self.tbl_name .. "`.`" .. self.col_name .. "`)"
end), COUNT = newProperty(function(self)
	return "COUNT(`" .. self.tbl_name .. "`.`" .. self.col_name .. "`)"
end), SUM = newProperty(function(self)
	return "SUM(" .. self.col_name .. ")"
end) }
local function _escapeValue(db_ins, tbl_ins, colname, colvalue)
	local coltype = tbl_ins:getColumn(colname)
	if coltype and coltype.settings.escape_value then
		local ftype = coltype.field._ftype
		if ftype:find("text") or ftype:find("char") then
			colvalue = db_ins.connect:escape(colvalue)
		end
	end
	return colvalue
end
local _db_query_list = nil
local _db_table = nil
local DBSelect = { __tn = 'DBSelect', __tk = 'class', __st = nil }
do
	local __st = nil
	local __ct = DBSelect
	__ct.__ct = __ct
	__ct.isKindOf = function(c, a) return a and c and ((c.__ct == a) or (c.__st and c.__st:isKindOf(a))) or false end
	-- declare class var and methods
	__ct._config = false
	__ct._db_ins = false
	__ct._tbl_ins = false
	__ct._rules = false
	function __ct:init(tbl_ins)
		self._config = tbl_ins.config
		self._db_ins = tbl_ins.db_ins
		self._tbl_ins = tbl_ins
		self._rules = { where = {  }, having = {  }, limit = nil, offset = nil, order = {  }, group = {  }, columns = { join = {  }, include = {  } } }
	end
	function __ct:_print(ttype, msg)
		self._config:print(ttype, msg)
	end
	function __ct:buildEquation(colname, value)
		local db_ins = self._db_ins
		local tbl_ins = self._tbl_ins
		local result = ""
		if _endWith(colname, kWhere.IS_NULL) then
			colname = _cutEnd(colname, kWhere.IS_NULL)
			if value then
				result = " IS NULL"
			else 
				result = " NOT NULL"
			end
		elseif _endWith(colname, kWhere.IN) or _endWith(colname, kWhere.NOT_IN) then
			local rule = _endWith(colname, kWhere.IN) and kWhere.IN or kWhere.NOT_IN
			if _isTable(value) and #value > 0 then
				colname = _cutEnd(colname, rule)
				local tbl_column = tbl_ins:getColumn(colname)
				local tbl_in = {  }
				for counter, val in pairs(value) do
					tbl_in[#tbl_in + 1] = tbl_column.field.as(val)
				end
				if rule == kWhere.IN then
					result = " IN (" .. _tableJoin(tbl_in) .. ")"
				elseif rule == kWhere.NOT_IN then
					result = " NOT IN (" .. _tableJoin(tbl_in) .. ")"
				end
			end
		else 
			local conditionPrepend = ""
			if _endWith(colname, kWhere.LESS_THEN) and _isNumber(value) then
				colname = _cutEnd(colname, kWhere.LESS_THEN)
				conditionPrepend = " < "
			elseif _endWith(colname, kWhere.MORE_THEN) and _isNumber(value) then
				colname = _cutEnd(colname, kWhere.MORE_THEN)
				conditionPrepend = " > "
			elseif _endWith(colname, kWhere.EQ_OR_LESS_THEN) and _isNumber(value) then
				colname = _cutEnd(colname, kWhere.EQ_OR_LESS_THEN)
				conditionPrepend = " <= "
			elseif _endWith(colname, kWhere.EQ_OR_MORE_THEN) and _isNumber(value) then
				colname = _cutEnd(colname, kWhere.EQ_OR_MORE_THEN)
				conditionPrepend = " >= "
			else 
				conditionPrepend = " = "
			end
			value = _escapeValue(db_ins, tbl_ins, colname, value)
			local tbl_column = tbl_ins:getColumn(colname)
			result = conditionPrepend .. tbl_column.field.as(value)
		end
		if tbl_ins:hasColumn(colname) then
			local parse_column, _ = tbl_ins:column(colname)
			result = parse_column .. result
		end
		return result
	end
	function __ct:updateColNames(list_of_cols)
		local tbl_ins = self._tbl_ins
		local tbl_name = tbl_ins.tbl_name
		local result = {  }
		for _, col in ipairs(list_of_cols) do
			if _isTable(col) and col.cls_type == kAGGREGATOR then
				col.tbl_name = tbl_name
				result[#result + 1] = col
			else 
				local parsed_column, _ = tbl_ins:column(col)
				result[#result + 1] = parsed_column
			end
		end
		return result
	end
	function __ct:buildCondition(rules, start_with)
		local counter = 0
		local condition = start_with
		for colname, value in pairs(rules) do
			local equation = self:buildEquation(colname, value)
			if counter > 0 then
				equation = "AND " .. equation
			end
			condition = condition .. " " .. equation
			counter = counter + 1
		end
		return condition
	end
	function __ct:hasForeignKeyTable(left_table, right_table)
		local foreign_type_array = left_table:getForeignTypeArray()
		for _, coltype in ipairs(foreign_type_array) do
			if coltype.settings.to_tbl_name == right_table.tbl_name then
				return true
			end
		end
	end
	function __ct:buildJoin()
		local result_join = ""
		for _, value in ipairs(self._rules.columns.join) do
			local left_table = value[1]
			local right_table = value[2]
			local mode = value[3]
			local tbl_name = left_table.tbl_name
			local join_mode = ""
			if mode == kJoin.JOIN_INNER then
				join_mode = "INNER JOIN"
			elseif mode == kJoin.JOIN_LEFT then
				join_mode = "LEFT OUTER JOIN"
			elseif mode == kJoin.JOIN_RIGHT then
				join_mode = "RIGHT OUTER JOIN"
			elseif mode == kJoin.JOIN_FULL then
				join_mode = "FULL OUTER JOIN"
			else 
				self:_print(kLog.WARNING, "Not valid join mode " .. mode)
			end
			if self:hasForeignKeyTable(right_table, left_table) then
				left_table, right_table = right_table, left_table
				tbl_name = right_table.tbl_name
			elseif not self:hasForeignKeyTable(left_table, right_table) then
				self:_print(kLog.WARNING, "Not valid tables links")
			end
			local foreign_type_array = left_table:getForeignTypeArray()
			for _, coltype in ipairs(foreign_type_array) do
				if coltype.settings.to_tbl_name == right_table.tbl_name then
					local col_name = coltype.name
					result_join = result_join .. " \n" .. join_mode .. " `" .. tbl_name .. "` ON "
					local parsed_column, _ = left_table:column(col_name)
					result_join = result_join .. parsed_column
					parsed_column, _ = right_table:column(kID)
					result_join = result_join .. " = " .. parsed_column
					break
				end
			end
		end
		return result_join
	end
	function __ct:buildIncluding(tbl_ins)
		local inc_array = {  }
		if not tbl_ins then
			tbl_ins = self._tbl_ins
		end
		local col_type_array = tbl_ins:getColTypeArray()
		for _, column in ipairs(col_type_array) do
			local colname, colname_as = tbl_ins:column(column.name)
			inc_array[#inc_array + 1] = colname .. " AS " .. colname_as
		end
		return _tableJoin(inc_array)
	end
	function __ct:buildSelect()
		local join = ""
		local select_result = "SELECT " .. self:buildIncluding()
		if #self._rules.columns.join > 0 then
			local unique_tables = { self._tbl_ins }
			for _, values in ipairs(self._rules.columns.join) do
				local left_table = values[1]
				local right_table = values[2]
				if not _tableHasValue(unique_tables, left_table) then
					unique_tables[#unique_tables + 1] = left_table
					select_result = select_result .. ", " .. self:buildIncluding(left_table)
				end
				if not _tableHasValue(unique_tables, right_table) then
					unique_tables[#unique_tables + 1] = right_table
					select_result = select_result .. ", " .. self:buildIncluding(right_table)
				end
			end
			join = self:buildJoin()
		end
		if #self._rules.columns.include > 0 then
			local aggregators = {  }
			for _, value in ipairs(self._rules.columns.include) do
				_, as = self._tbl_ins:column(value.as)
				aggregators[#aggregators + 1] = value[1] .. " AS " .. as
			end
			select_result = select_result .. ", " .. _tableJoin(aggregators)
		end
		select_result = select_result .. " FROM `" .. self._tbl_ins.tbl_name .. "`"
		if join then
			select_result = select_result .. " " .. join
		end
		if next(self._rules.where) then
			local condition = self:buildCondition(self._rules.where, "\nWHERE")
			select_result = select_result .. " " .. condition
		end
		if #self._rules.group > 0 then
			local rule = self:updateColNames(self._rules.group)
			rule = _tableJoin(rule)
			select_result = select_result .. " \nGROUP BY " .. rule
		end
		if next(self._rules.having) and self._rules.group then
			local condition = self:buildCondition(self._rules.having, "\nHAVING")
			select_result = select_result .. " " .. condition
		end
		if #self._rules.order > 0 then
			local rule = self:updateColNames(self._rules.order)
			rule = _tableJoin(rule)
			select_result = select_result .. " \nORDER BY " .. rule
		end
		if self._rules.limit then
			select_result = select_result .. " \nLIMIT " .. self._rules.limit
		end
		if self._rules.offset then
			select_result = select_result .. " \nOFFSET " .. self._rules.offset
		end
		return self._db_ins:rows(select_result, self._tbl_ins)
	end
	function __ct:addColToTable(col_table, order_list)
		if _isStr(order_list) and self._tbl_ins:hasColumn(order_list) then
			col_table[#col_table + 1] = order_list
		elseif _isTable(order_list) then
			for _, column in ipairs(order_list) do
				if (_isTable(column) and column.cls_type == kAGGREGATOR and self._tbl_ins:hasColumn(column.col_name)) or self._tbl_ins:hasColumn(column) then
					col_table[#col_table + 1] = column
				end
			end
		else 
			self:_print(kLog.WARNING, "Not a string and not a table (" .. tostring(order_list) .. ")")
		end
	end
	function __ct:include(column_list)
		if _isTable(column_list) then
			local tbl = self._rules.columns.include
			for _, value in ipairs(column_list) do
				if _isTable(value) and value.as and value[1] and value[1]._clstype == kAGGREGATOR then
					tbl[#tbl + 1] = value
				else 
					self:_print(kLog.WARNING, "Not valid aggregator syntax")
				end
			end
		else 
			self:_print(kLog.WARNING, "You can include only table type data")
		end
		return self
	end
	function __ct:_join(left_table, mode, right_table)
		if not right_table then
			right_table = self._tbl_ins
		end
		if left_table.tbl_name then
			local tbl = self._rules.columns.join
			tbl[#tbl + 1] = { left_table, right_table, mode }
		else 
			self:_print(kLog.WARNING, "Not table in join")
		end
		return self
	end
	function __ct:join(left_table, right_table)
		self:_join(left_table, kJoin.JOIN_INNER, right_table)
		return self
	end
	function __ct:left_join(left_table, right_table)
		self:_join(left_table, kJoin.JOIN_LEFT, right_table)
		return self
	end
	function __ct:right_join(left_table, right_table)
		self:_join(left_table, kJoin.JOIN_RIGHT, right_table)
		return self
	end
	function __ct:full_join(left_table, right_table)
		self:_join(left_table, kJoin.JOIN_FULL, right_table)
		return self
	end
	function __ct:where(args)
		for col, value in pairs(args) do
			self._rules.where[col] = value
		end
		return self
	end
	function __ct:limit(count)
		if _isInt(count) then
			self._rules.limit = count
		else 
			self:_print(kLog.WARNING, "You try set limit to not integer value")
		end
		return self
	end
	function __ct:offset(count)
		if _isInt(count) then
			self._rules.offset = count
		else 
			self:_print(kLog.WARNING, "You try set offset to not integer value")
		end
		return self
	end
	function __ct:orderBy(order_list)
		self:addColToTable(self._rules.order, order_list)
		return self
	end
	function __ct:groupBy(colname)
		self:addColToTable(self._rules.group, colname)
		return self
	end
	function __ct:having(args)
		for col, value in pairs(args) do
			self._rules.having[col] = value
		end
		return self
	end
	function __ct:update(data)
		if not (_isTable(data)) then
			self:_print(kLog.WARNING, "No data for global update")
			return 
		end
		local tbl_ins = self._tbl_ins
		local _update = "UPDATE `" .. tbl_ins.tbl_name .. "`"
		local _set = ""
		local _set_tbl = {  }
		local i = 1
		for colname, new_value in pairs(data) do
			local coltype = tbl_ins:getColumn(colname)
			if coltype and coltype.field.validator(new_value) then
				_set = _set .. " `" .. colname .. "` = " .. coltype.field.as(new_value)
				_set_tbl[i] = " `" .. colname .. "` = " .. coltype.field.as(new_value)
				i = i + 1
			else 
				self:_print(kLog.WARNING, "Can't update value for column `" .. _toStr(colname) .. "`")
			end
		end
		local _where = nil
		if next(self._rules.where) then
			_where = self:buildCondition(self._rules.where, "\nWHERE")
		else 
			self:_print(kLog.INFO, "No 'where' statement. All data update!")
		end
		if _set ~= "" then
			if #_set_tbl < 2 then
				_update = _update .. " SET " .. _set .. " " .. _where
			else 
				_update = _update .. " SET " .. table.concat(_set_tbl, ",") .. " " .. _where
			end
			self._db_ins:execute(_update)
		else 
			self:_print(kLog.WARNING, "No table columns for update")
		end
	end
	function __ct:delete()
		local _delete = "DELETE FROM `" .. self._tbl_ins.tbl_name .. "` "
		if next(self._rules.where) then
			_delete = _delete .. self:buildCondition(self._rules.where, "\nWHERE")
		else 
			self:_print(kLog.WARNING, "Try delete all values")
		end
		self._db_ins:execute(_delete)
	end
	function __ct:first()
		self._rules.limit = 1
		local data = self:all()
		if data:count() == 1 then
			return data[1]
		end
	end
	function __ct:all()
		return _db_query_list(self._tbl_ins, self:buildSelect())
	end
	-- declare end
	local __imt = {
		__tostring = function(t) return string.format("<class DBSelect: %p>", t) end,
		__index = function(t, k)
			local v = __ct[k]
			if v ~= nil then rawset(t, k, v) end
			return v
		end,
	}
	setmetatable(__ct, {
		__tostring = function() return "<class DBSelect>" end,
		__index = function(t, k)
			local v = __st and __st[k]
			if v ~= nil then rawset(__ct, k, v) end
			return v
		end,
		__call = function(_, ...)
			local ins = setmetatable({}, __imt)
			if type(rawget(__ct,'init')) == 'function' and __ct.init(ins, ...) == false then return nil end
			return ins
		end,
	})
end
local DBQuery = { __tn = 'DBQuery', __tk = 'class', __st = nil }
do
	local __st = nil
	local __ct = DBQuery
	__ct.__ct = __ct
	__ct.isKindOf = function(c, a) return a and c and ((c.__ct == a) or (c.__st and c.__st:isKindOf(a))) or false end
	-- declare class var and methods
	function __ct:init(tbl_ins, row_data)
		rawset(self, 'save', DBQuery.save)
		rawset(self, 'delete', DBQuery.delete)
		rawset(self, 'foreign', DBQuery.foreign)
		rawset(self, 'references', DBQuery.references)
		self._config = tbl_ins.config
		self._db_ins = tbl_ins.db_ins
		self._tbl_ins = tbl_ins
		self._data = {  }
		self._fdata = {  }
		self._rdata = {  }
		if not row_data then
			self:_print(kLog.WARNING, "Create empty row instance for table '" .. self._tbl_ins._tbl_name .. "'")
			return false
		else 
			for colname, colvalue in pairs(row_data) do
				if tbl_ins:hasColumn(colname, true) then
					colvalue = tbl_ins:getColumn(colname).field.toType(colvalue)
					self._data[colname] = { new = colvalue, old = colvalue }
				else 
					local ftbl_ins = self._db_ins:getTableWith(colname)
					if ftbl_ins then
						self._fdata[colname] = DBQuery(ftbl_ins, colvalue)
						local rtbl = self._rdata[colname]
						rtbl = rtbl or _db_query_list(ftbl_ins, {  })
						rtbl:add(colvalue)
						self._rdata[colname] = rtbl
					end
				end
			end
		end
	end
	function __ct:_print(ttype, msg)
		self._config:print(ttype, msg)
	end
	function __ct:save()
		if self.id then
			return self:_update()
		else 
			return self:_add()
		end
	end
	function __ct:delete()
		local ret = 0
		if self.id then
			local delete = "DELETE FROM `" .. self._tbl_ins.tbl_name .. "` " .. "WHERE `" .. kID .. "` = " .. self.id
			ret = self._db_ins:execute(delete)
		end
		self._data = {  }
		self._fdata = {  }
		self._rdata = {  }
		return ret
	end
	function __ct:foreign(ftbl)
		if _isStr(ftbl) then
			return self._fdata[ftbl]
		elseif _isTable(ftbl) and ftbl:isKindOf(_db_table) then
			return self._fdata[ftbl.tbl_name]
		end
	end
	function __ct:references(rtbl)
		if _isStr(rtbl) then
			return self._rdata[rtbl]
		elseif _isTable(rtbl) and rtbl:isKindOf(_db_table) then
			return self._rdata[rtbl.tbl_name]
		end
	end
	function __ct.__ins_index(t, k)
		if strchar(strbyte(k, 1)) == "_" then
			return 
		end
		return true, t:_getCol(k)
	end
	function __ct:_getCol(colname)
		local col = self._data[colname]
		if col and col.new ~= nil then
			return col.new
		end
	end
	function __ct:_setCol(colname, colvalue, col)
		col = col or self._data[colname]
		if col and col.new ~= nil and colname ~= kID then
			local coltype = self._tbl_ins:getColumn(colname)
			if coltype and coltype.field.validator(colvalue) then
				self._data[colname].old = col.new
				self._data[colname].new = colvalue
			else 
				self:_print(kLog.WARNING, "Not valid column value for update")
			end
		end
	end
	function __ct:_add()
		local db_ins = self._db_ins
		local tbl_ins = self._tbl_ins
		local insert = "INSERT INTO `" .. tbl_ins.tbl_name .. "` ("
		local counter = 0
		local values = ""
		local col_type_array = self._tbl_ins:getColTypeArray()
		for _, tbl_column in ipairs(col_type_array) do
			local colname = tbl_column.name
			if colname ~= kID then
				local value = self:_getCol(colname)
				if value ~= nil then
					if tbl_column.field.validator(value) then
						value = _escapeValue(db_ins, tbl_ins, colname, value)
						value = tbl_column.field.as(value)
					else 
						self:_print(kLog.WARNING, "Wrong type for table '" .. tbl_ins.tbl_name .. "' in column '" .. tostring(colname) .. "'")
						return false
					end
				elseif tbl_column.settings.default_value then
					value = tbl_column.field.as(tbl_column.settings.default_value)
				else 
					value = "NULL"
				end
				colname = "`" .. colname .. "`"
				if counter ~= 0 then
					colname = ", " .. colname
					value = ", " .. value
				end
				values = values .. value
				insert = insert .. colname
				counter = counter + 1
			end
		end
		insert = insert .. ") \n\t  VALUES (" .. values .. ")"
		local ret = db_ins:insert(insert)
		self._data.id = { new = ret }
		return ret
	end
	function __ct:_update()
		local db_ins = self._db_ins
		local tbl_ins = self._tbl_ins
		local update = "UPDATE `" .. tbl_ins.tbl_name .. "` "
		local equation_for_set = {  }
		for colname, colinfo in ipairs(self._data) do
			if colinfo.old ~= colinfo.new and colname ~= kID then
				local coltype = tbl_ins:getColumn(colname)
				if coltype and coltype.field.validator(colinfo.new) then
					local colvalue = _escapeValue(db_ins, tbl_ins, colname, colinfo.new)
					local set = " `" .. colname .. "` = " .. coltype.field.as(colvalue)
					equation_for_set[#equation_for_set + 1] = set
					print("--- equaltion", set)
				else 
					self:_print(kLog.WARNING, "Can't update value for column `" .. _toStr(colname) .. "`")
				end
			end
		end
		local set = _tableJoin(equation_for_set)
		if set ~= "" then
			update = update .. " SET " .. set .. "\n\t WHERE `" .. kID .. "` =" .. self.id
			return db_ins:execute(update)
		else 
			return false
		end
	end
	-- declare end
	local __imt = {
		__index = function(t, k)
			local ok, v = __ct.__ins_index(t, k)
			if ok then return v else v = __ct[k] end
			if v ~= nil then rawset(t, k, v) end
			return v
		end,
		__tostring = function(t)
			return strfmt("<Query(%s)#%d: %p>", t._tbl_ins.tbl_name, tonumber(t.id or 0), t)
		end,
		__newindex = function(t, k, v)
			if strchar(strbyte(k, 1)) ~= "_" then
				local col = t._data[k]
				if col then
					t:_setCol(k, v, col)
					return 
				end
			end
			rawset(t, k, v)
		end,
	}
	setmetatable(__ct, {
		__tostring = function() return "<class DBQuery>" end,
		__index = function(t, k)
			local v = __st and __st[k]
			if v ~= nil then rawset(__ct, k, v) end
			return v
		end,
		__call = function(_, ...)
			local ins = setmetatable({}, __imt)
			if type(rawget(__ct,'init')) == 'function' and __ct.init(ins, ...) == false then return nil end
			return ins
		end,
	})
end
local DBQueryList = { __tn = 'DBQueryList', __tk = 'class', __st = nil }
do
	local __st = nil
	local __ct = DBQueryList
	__ct.__ct = __ct
	__ct.isKindOf = function(c, a) return a and c and ((c.__ct == a) or (c.__st and c.__st:isKindOf(a))) or false end
	-- declare class var and methods
	__ct._config = false
	__ct._tbl_ins = false
	__ct._stack = false
	function __ct:init(tbl_ins, rows)
		self._config = tbl_ins.config
		self._tbl_ins = tbl_ins
		self._tbl_name = tbl_ins.tbl_name
		self._stack = {  }
		for _, row in ipairs(rows) do
			local cur_query = self:withId(_toNumber(row.id))
			if cur_query then
				local db_ins = self._tbl_ins.db_ins
				local rdata = cur_query._rdata
				for key, value in pairs(row) do
					if _isTable(value) and rdata[key] then
						local rtbl_ins = db_ins:getTableWith(key)
						rdata[key]:add(DBQuery(rtbl_ins, value))
					end
				end
			else 
				self:add(DBQuery(tbl_ins, row))
			end
		end
	end
	function __ct:print(ttype, msg)
		self._config:print(ttype, msg)
	end
	function __ct.__ins_index(t, k)
		if _isInt(k) and k >= 1 then
			return true, t._stack[k]
		end
	end
	function __ct:count()
		return #self._stack
	end
	function __ct:list()
		return self._stack
	end
	function __ct:withId(id)
		if _isInt(id) then
			for _, query in pairs(self._stack) do
				if query.id == id then
					return query
				end
			end
		else 
			self:print(kLog.WARNING, "ID `" .. id .. "` is not integer value")
		end
	end
	function __ct:add(query_ins)
		self._stack[#self._stack + 1] = query_ins
	end
	function __ct:delete()
		for _, query in ipairs(self._stack) do
			query:delete()
		end
		self._stack = {  }
	end
	-- declare end
	local __imt = {
		__index = function(t, k)
			local ok, v = __ct.__ins_index(t, k)
			if ok then return v else v = __ct[k] end
			if v ~= nil then rawset(t, k, v) end
			return v
		end,
		__tostring = function(t)
			return strfmt("<QueryList(%s)#%d: %p>", t._tbl_ins.tbl_name, #t._stack, t)
		end,
	}
	setmetatable(__ct, {
		__tostring = function() return "<class DBQueryList>" end,
		__index = function(t, k)
			local v = __st and __st[k]
			if v ~= nil then rawset(__ct, k, v) end
			return v
		end,
		__call = function(_, ...)
			local ins = setmetatable({}, __imt)
			if type(rawget(__ct,'init')) == 'function' and __ct.init(ins, ...) == false then return nil end
			return ins
		end,
	})
end
_db_query_list = DBQueryList
local DBFieldBase = { __tn = 'DBFieldBase', __tk = 'class', __st = nil }
do
	local __st = nil
	local __ct = DBFieldBase
	__ct.__ct = __ct
	__ct.isKindOf = function(c, a) return a and c and ((c.__ct == a) or (c.__st and c.__st:isKindOf(a))) or false end
	-- declare class var and methods
	__ct.field_type = "varchar"
	__ct.field_name = "base"
	function __ct:init(args)
		self.field_name = args.field_name or DBFieldBase.field_name
		self.field_type = args.field_type or DBFieldBase.field_type
		self.validator = args.validator or DBFieldBase.validator
		self.as = args.as or DBFieldBase.as
		self.toType = args.toType or DBFieldBase.toType
		self.settings = args.settings or {  }
	end
	function __ct.validator(value)
		return true
	end
	function __ct.as(value)
		return value
	end
	function __ct.toType(value)
		return tostring(value)
	end
	function __ct.register(args)
		args = args or {  }
		return DBFieldBase(args)
	end
	-- declare end
	local __imt = {
		__index = function(t, k)
			local v = __ct[k]
			if v ~= nil then rawset(t, k, v) end
			return v
		end,
		__tostring = function(t)
			return "<DBField(" .. t.field_name .. "): " .. t.field_type .. ">"
		end,
		__call = function(t, args)
			local ins = { field = t, settings = { field_default = nil, null = false, unique = false, max_length = nil, primary_key = false, escape_value = false, foreign_key = false } }
			ins.createType = function(self, config)
				local ftype = self.field.field_type
				if self.settings.max_length and self.settings.max_length > 0 then
					ftype = ftype .. "(" .. self.settings.max_length .. ")"
				end
				if self.settings.primary_key then
					ftype = ftype .. " PRIMARY KEY"
				end
				if self.settings.auto_increment then
					if config.db_type == kDBType.SQLITE then
						ftype = ftype .. " AUTOINCREMENT"
					else 
						ftype = ftype .. " AUTO_INCREMENT"
					end
				end
				if self.settings.unique then
					ftype = ftype .. " UNIQUE"
				end
				ftype = ftype .. (self.settings.null and " NULL" or " NOT NULL")
				return ftype
			end
			for k, v in pairs(t.settings) do
				ins.settings[k] = v
			end
			if args.max_length then
				ins.settings.max_length = args.max_length
			end
			if args.null ~= nil then
				ins.settings.null = args.null
			end
			if ins.settings.foreign_key and args.to_table and args.to_table:isKindOf(_db_table) then
				ins.settings.to_tbl_name = args.to_table.tbl_name
			end
			if args.escape_value then
				ins.settings.escape_value = true
			end
			if args.unique then
				ins.settings.unique = args.unique
			end
			return ins
		end,
	}
	setmetatable(__ct, {
		__tostring = function() return "<class DBFieldBase>" end,
		__index = function(t, k)
			local v = __st and __st[k]
			if v ~= nil then rawset(__ct, k, v) end
			return v
		end,
		__call = function(_, ...)
			local ins = setmetatable({}, __imt)
			if type(rawget(__ct,'init')) == 'function' and __ct.init(ins, ...) == false then return nil end
			return ins
		end,
	})
end
local DBField = { PrimaryField = DBFieldBase.register({ field_name = "primary", field_type = "integer", validator = _isInt, settings = { null = true, primary_key = true, auto_increment = true }, toType = _toNumber }), IntegerField = DBFieldBase.register({ field_name = "integer", field_type = "integer", validator = _isInt, toType = _toNumber }), CharField = DBFieldBase.register({ field_name = "char", field_type = "varchar", validator = _isStr, as = _saveAsStr }), TextField = DBFieldBase.register({ field_name = "text", field_type = "text", validator = _isStr, as = _saveAsStr }), BooleanField = DBFieldBase.register({ field_name = "boolean", field_type = "integer", as = function(value)
	return value and 1 or 0
end, toType = function(value)
	if _isBool(value) then
		return value
	else 
		return value == 1 and true or false
	end
end }), BlobField = DBFieldBase.register({ field_name = "blob", field_type = "blob" }), DateTimeField = DBFieldBase.register({ field_name = "date_time", field_type = "integer", validator = function(value)
	if (_isTable(value) and value.isdst ~= nil) or _isInt(value) then
		return true
	end
end, as = function(value)
	return _isInt(value) and value or os.time(value)
end, toType = function(value)
	return os.date("*t", _toNumber(value))
end }), ForeignKey = DBFieldBase.register({ field_name = "foreign_key", field_type = "integer", settings = { null = true, foreign_key = true }, toType = _toNumber }), register = DBFieldBase.register }
local DBTable = { __tn = 'DBTable', __tk = 'class', __st = nil }
do
	local __st = nil
	local __ct = DBTable
	__ct.__ct = __ct
	__ct.isKindOf = function(c, a) return a and c and ((c.__ct == a) or (c.__st and c.__st:isKindOf(a))) or false end
	-- declare class var and methods
	function __ct:init(db_ins, tbl_config, tbl_column)
		self.config = db_ins.config
		self.db_ins = db_ins
		self.tbl_name = tbl_config.table_name
		self.col_names = {  }
		local db_tbl = G_DB_Ins_Tbl[self.config.db_path]
		if _isTable(db_tbl) and db_tbl[self.tbl_name] then
			for i, coltype in ipairs(db_tbl[self.tbl_name][2]) do
				self.col_names[i] = coltype.name
			end
			return 
		end
		local column_order = { "id" }
		if _isTable(tbl_config.column_order) then
			for _, v in ipairs(tbl_config.column_order) do
				column_order[#column_order + 1] = v
			end
		end
		for k, _ in pairs(tbl_column) do
			if not _tableHasValue(column_order, k) then
				column_order[#column_order + 1] = k
			end
		end
		tbl_column.id = DBField.PrimaryField({ auto_increment = true })
		local col_type_array = {  }
		local foreign_type_array = {  }
		for i, colname in ipairs(column_order) do
			local coltype = tbl_column[colname]
			coltype.name = colname
			coltype.tbl_name = self.tbl_name
			col_type_array[i] = coltype
			if coltype.settings.foreign_key then
				foreign_type_array[#foreign_type_array + 1] = coltype
			end
			self.col_names[i] = colname
		end
		db_tbl = G_DB_Ins_Tbl[self.config.db_path]
		if _isTable(db_tbl) then
			db_tbl[self.tbl_name] = { self, col_type_array, foreign_type_array }
		end
		if self.config.new_table then
			self:createTable()
		end
	end
	function __ct:print(ttype, msg)
		self.config:print(ttype, msg)
	end
	function __ct:getColTypeArray()
		local db_tbl = G_DB_Ins_Tbl[self.config.db_path]
		if _isTable(db_tbl) then
			local tbl_array = db_tbl[self.tbl_name]
			if _isTable(tbl_array) and #tbl_array > 1 then
				return tbl_array[2]
			end
		end
		return {  }
	end
	function __ct:getForeignTypeArray()
		local db_tbl = G_DB_Ins_Tbl[self.config.db_path]
		if _isTable(db_tbl) then
			local tbl_array = db_tbl[self.tbl_name]
			if _isTable(tbl_array) and #tbl_array > 2 then
				return tbl_array[3]
			end
		end
		return {  }
	end
	function __ct:createTable()
		local tbl_name = self.tbl_name
		local col_type_array = self:getColTypeArray()
		local foreign_type_array = self:getForeignTypeArray()
		self:print(kLog.INFO, "Start create table: " .. tbl_name)
		local create_query = "CREATE TABLE IF NOT EXISTS `" .. tbl_name .. "` \n("
		local counter = 0
		local column_query = ""
		for _, coltype in ipairs(col_type_array) do
			column_query = "\n     `" .. coltype.name .. "` " .. coltype:createType(self.config)
			if counter > 0 then
				column_query = "," .. column_query
			end
			create_query = create_query .. column_query
			counter = counter + 1
		end
		for _, coltype in pairs(foreign_type_array) do
			create_query = create_query .. (",\n     FOREIGN KEY(`" .. coltype.name .. "`)" .. " REFERENCES `" .. coltype.settings.to_tbl_name .. "`(`id`)")
		end
		create_query = create_query .. "\n)"
		self.db_ins:execute(create_query)
	end
	function __ct.__ins_index(t, k)
		if k == 'get' then
			return true, DBSelect(t)
		end
	end
	function __ct:column(column)
		local tbl_name = self.tbl_name
		if _isTable(column) and column._cls_type == kAGGREGATOR then
			column.col_name = tbl_name .. column.col_name
			column = column .. ""
		end
		return ("`" .. tbl_name .. "`.`" .. column .. "`"), (tbl_name .. "__" .. column)
	end
	function __ct:hasColumn(col_name, quiet)
		for _, name in ipairs(self.col_names) do
			if name == col_name then
				return true
			end
		end
		if not quiet then
			self:print(kLog.WARNING, "Can't find column '" .. tostring(col_name) .. "' in table '" .. self.tbl_name .. "'")
		end
	end
	function __ct:getColumn(col_name, quiet)
		local col_type_array = self:getColTypeArray()
		for _, tbl_column in ipairs(col_type_array) do
			if tbl_column.name == col_name then
				return tbl_column
			end
		end
		if not quiet then
			self:print(kLog.WARNING, "Can't find column '" .. tostring(col_name) .. "' in table '" .. self.tbl_name .. "'")
		end
	end
	-- declare end
	local __imt = {
		__index = function(t, k)
			local ok, v = __ct.__ins_index(t, k)
			if ok then return v else v = __ct[k] end
			if v ~= nil then rawset(t, k, v) end
			return v
		end,
		__tostring = function(t)
			return strfmt("<DBTable(%s): %p>", t.tbl_name, t)
		end,
		__call = function(t, row_data)
			return DBQuery(t, row_data)
		end,
	}
	setmetatable(__ct, {
		__tostring = function() return "<class DBTable>" end,
		__index = function(t, k)
			local v = __st and __st[k]
			if v ~= nil then rawset(__ct, k, v) end
			return v
		end,
		__call = function(_, ...)
			local ins = setmetatable({}, __imt)
			if type(rawget(__ct,'init')) == 'function' and __ct.init(ins, ...) == false then return nil end
			return ins
		end,
	})
end
_db_table = DBTable
local DBInstance = { __tn = 'DBInstance', __tk = 'class', __st = nil }
do
	local __st = nil
	local __ct = DBInstance
	__ct.__ct = __ct
	__ct.isKindOf = function(c, a) return a and c and ((c.__ct == a) or (c.__st and c.__st:isKindOf(a))) or false end
	-- declare class var and methods
	function __ct:init(config, db_env, db_conn)
		self.config = config
		self.db_env = db_env
		self.db_conn = db_conn
		G_DB_Ins_Tbl[config.db_path] = {  }
	end
	function __ct:deinit()
		self:close()
	end
	function __ct:close()
		if self.db_env and self.db_conn then
			local ret_1 = self.db_conn:close()
			local ret_2 = self.db_env:close()
			self.db_conn = nil
			self.db_env = nil
			print("[SQL-ORM] Disconnect SQLite3", self.config.db_path, ret_1, ret_2)
		end
		G_DB_Ins_Tbl[self.config.db_path] = nil
	end
	function __ct:print(ttype, msg)
		self.config:print(ttype, msg)
	end
	function __ct:execute(query)
		if not (self.db_conn ~= nil) then
			self:print(kLog.ERROR, "Database disconnected")
			return 
		end
		self:print(kLog.DEBUG, query)
		local result = self.db_conn:execute(query)
		if result then
			return result
		else 
			self:print(kLog.WARNING, "Wrong SQL query")
		end
	end
	function __ct:insert(query)
		return self:execute(query)
	end
	function __ct:rows(query, tbl_ins)
		local cursor = self:execute(query)
		local data = {  }
		if cursor then
			local row = cursor:fetch({  }, "a")
			local current_row = {  }
			while row do
				for colname, value in pairs(row) do
					local current_table, colname = _dividedInto(colname, "__")
					if current_table == tbl_ins.tbl_name then
						current_row[colname] = value
					else 
						if not current_row[current_table] then
							current_row[current_table] = {  }
						end
						current_row[current_table][colname] = value
					end
				end
				data[#data + 1] = current_row
				current_row = {  }
				row = cursor:fetch({  }, "a")
			end
			cursor:close()
		end
		return data
	end
	function __ct:getTableWith(tbl_name)
		local db_tbl = G_DB_Ins_Tbl[self.config.db_path]
		if _isTable(db_tbl) then
			return db_tbl[tbl_name][1]
		end
	end
	-- declare end
	local __imt = {
		__tostring = function(t) return string.format("<class DBInstance: %p>", t) end,
		__index = function(t, k)
			local v = __ct[k]
			if v ~= nil then rawset(t, k, v) end
			return v
		end,
		__gc = function(t) t:deinit() end,
	}
	setmetatable(__ct, {
		__tostring = function() return "<class DBInstance>" end,
		__index = function(t, k)
			local v = __st and __st[k]
			if v ~= nil then rawset(__ct, k, v) end
			return v
		end,
		__call = function(_, ...)
			local ins = setmetatable({}, __imt)
			if type(rawget(__ct,'init')) == 'function' and __ct.init(ins, ...) == false then return nil end
			if _VERSION == "Lua 5.1" then
				rawset(ins, '__gc_proxy', newproxy(true))
				getmetatable(ins.__gc_proxy).__gc = function() ins:deinit() end
			end
			return ins
		end,
	})
end
local DBConfig = { __tn = 'DBConfig', __tk = 'struct' }
do
	local __ct = DBConfig
	__ct.__ct = __ct
	-- declare struct var and methods
	__ct.new_table = false
	__ct.log_debug = true
	__ct.log_trace = true
	__ct.db_type = kDBType.SQLITE
	__ct.db_path = "database.db"
	__ct.print = 1
	function __ct:init(config)
		self.print = self._noPrint
		if not (_isTable(config)) then
			return 
		end
		local keys = { "new_table", "log_debug", "log_trace", "db_type", "db_path" }
		for _, k in ipairs(keys) do
			self[k] = config[k]
		end
		if config.log_debug or config.log_trace then
			self.print = self._ioPrint
		end
	end
	function __ct:_noPrint()
	end
	function __ct:_ioPrint(ttype, msg)
		if self.log_trace then
			local __s = ttype
			if __s == kLog.ERROR then
				print("[SQL-ORM:Error] " .. msg)
				os.exit()
			elseif __s == kLog.WARNING then
				print("[SQL-ORM:Warning] " .. msg)
			elseif __s == kLog.INFO then
				print("[SQL-ORM:Info] " .. msg)
			end
		end
		if self.log_debug and ttype == kLog.DEBUG then
			print("[SQL-ORM:Debug] " .. msg)
		end
	end
	-- declare end
	local __imt = {
		__tostring = function(t) return string.format("<struct DBConfig: %p>", t) end,
		__index = function(t, k)
			local v = rawget(__ct, k)
			if v ~= nil then rawset(t, k, v) end
			return v
		end,
		__newindex = function(t, k, v) if rawget(__ct, k) ~= nil then rawset(t, k, v) end end,
	}
	DBConfig = setmetatable({}, {
		__tostring = function() return "<struct DBConfig>" end,
		__index = function(_, k) return rawget(__ct, k) end,
		__newindex = function(_, k, v) if v ~= nil and rawget(__ct, k) ~= nil then rawset(__ct, k, v) end end,
		__call = function(_, ...)
			local ins = setmetatable({}, __imt)
			if type(rawget(__ct,'init')) == 'function' and __ct.init(ins, ...) == false then return nil end
			return ins
		end,
	})
end
local function newDatabase(_, config)
	if not config then
		print("[SQL-ORM:Startup] Using default config")
		config = DBConfig()
	else 
		config.db_type = config.db_type or DBConfig.db_type
		config.db_path = config.db_path or DBConfig.db_path
		config = DBConfig(config)
	end
	local db_tbl = G_DB_Ins_Tbl[config.db_path]
	if not (not db_tbl) then
		return db_tbl[1], db_tbl[2], DBField, DBOrderBy
	end
	local db_env = require("luasql.sqlite3").sqlite3()
	local db_conn = db_env:connect(config.db_path)
	if not (db_conn) then
		print("[SQL-ORM] Connect SQLite3", config.db_path)
		return 
	end
	print("[SQL-ORM] Connect SQLite3", config.db_path)
	local db_ins = DBInstance(config, db_env, db_conn)
	local DBTableWrapper = setmetatable({  }, { __call = function(_, tbl_config, tbl_column)
		if _isTable(tbl_config) and _isTable(tbl_column) and _isStr(tbl_config.table_name) then
			return DBTable(db_ins, tbl_config, tbl_column)
		end
	end })
	db_tbl = G_DB_Ins_Tbl[config.db_path]
	if db_tbl then
		db_tbl[1] = db_ins
		db_tbl[2] = DBTableWrapper
	end
	return db_ins, DBTableWrapper, DBField, DBOrderBy
end
return setmetatable({  }, { __call = newDatabase })
