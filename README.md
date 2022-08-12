
All local variable version and all in one Lua4DaysORM from [itdxer/4DaysORM](https://github.com/itdxer/4DaysORM/), rewriten with [MoonCake](https://github.com/lalawue/mooncake).

# Lua-ORM 10 minutes tutorial #

support Lua 5.1 or LuaJIT.

## Database configuration ##

first get DatabaseClass after require:

```lua
local DBClass = require("sql-orm")
```

then create instance:

```lua
local DBIns, Table, Field, OrderBy = DBClass({
    new_table = true,
    db_path = "database.db",
    db_type = "sqlite3",
    log_debug = true,
    log_trace = true
})
```
and you can disconnect in the end:

```lua
DBIns:close()
```

options below:

**Development configurations:**

1. `new_table` - if this value is `true`, then new table was created if not exsit (*`true` by default*).
2. `log_trace` - if this value is `true`, than you will be able to see in console all Warnings, Errors and Information messages (*`true` by default*).
3. `log_debug` - if this value is `true`, you will be able to see in console all SQL queries (*`true` by default*).

**Database configurations**

1. `db_type` - by default `"sqlite3"`. Also it can be:
    - `"mysql"` - for MySQL database (NOT SUPPORTED right now)
    - `"postgresql"` - for PostgreSQL database (NOT SUPPORTED right now)
2. `db_path` - this is a path to database file for `"sqlite3"`. For other databases this value contains database name. (*by default `"database.db"`*)


database instance creation also return tools to create Table, Field, and group them


## Create table ##


```lua
local User = Table(
{
    table_name = "user_t",
},
{
    username = Field.CharField({max_length = 100, unique = true}),
    password = Field.CharField({max_length = 50, unique = true}),
    age = Field.IntegerField({max_length = 2, null = true}),
    job = Field.CharField({max_length = 50, null = true}),
    time_create = Field.DateTimeField({null = true})
    -- data = Field.BlobField({null = true}),
})
```

For every table is created a column `id` with `PRIMARY KEY` field by default.

`table_name` is required value which should contain the name of the table.
`column_order` is optional and can be used to define the order in which the columns will be created in the database table (the value must be a table of column names)

Also you can add different settings to your table fields

1. `max_length` - it is a maximum allowable value of symbols that you can use in a string
2. `unique` - if this value is `true ` then all the column's values are unique
3. `null` - can be `true` or `false`. If value is `true` then value in table will be saved as `NULL`.
4. `default_value` - if you didn't add any value to this field - it is going to be saved as default value.
5. `escape_value` - If this value is `true` and the column type is a string type special characters will be escaped to prevent sql injection
6. `primary_key` can not set, will be used in id column with auto increment

## Types of table fields ##

Supported types of table fields

1. `CharField` - Creates `VARCHAR` field
2. `IntegerField` - Creates `INTEGER` field
3. `TextField` - Creates `TEXT` field
4. `BlobField` - Creates `BLOB` field
5. `BooleanField` - Creates `BOOLEAN` field
6. `DateTimeField` - Creates `INTEGER` field but brings back `os.date` instance
8. `ForeignKey` - Creates relationships between tables.

Also you can create your types of table fields. But about it later.

## Create data ##

Try to create a new user:

```lua
local user = User({
    username = "Bob Smith",
    password = "SuperSecretPassword",
    time_create = os.time()
})
```

Now you created new user, but it was not added to database. You can add him.


```lua
user:save()
```

Now this user with all the information is in database. We can get his `id`

```lua
print("User " .. user.username .. " has id " .. user.id)
-- User Bob Smith has id 1
```

## Update data ##

You can change your data:


```lua
user.username = "John Smith"
```

This value was changed in model, but it has not been changed in database table.


```lua
user:save()
```

Now try to get new username for user:


```lua
print("New user name is " .. user.username) -- New user name is John Smith
```

You have updated in database only the column that you changed.
You can also edit columns for the value by another terms:


```lua
User.get:where({time_create__null = true})
        :update({time_create = os.time()})
```

*The conditions will be described in the next chapter*

## Remove data ##

And also you can remove your data from table.


```lua
user:delete()
```

You can also delete columns for the value by another terms:


```lua
-- add test user
user = User({username = "SomebodyNew", password = "NotSecret"})
user:save()

User.get:where({username = "SomebodyNew"}):delete()
```

*The conditions will be described in the next chapter*

## Get data ##

Also we can get data from table. But before this let's create 5 test users.


```lua
user = User({username = "First user", password = "secret1", age = 22})
user:save()

user = User({username = "Second user", password = "secret_test", job = "Lua developer"})
user:save()

user = User({username = "Another user", password = "old_test", age = 44})
user:save()

user = User({username = "New user", password = "some_passwd", age = 23, job = "Manager"})
user:save()

user = User({username = "Old user", password = "secret_passwd", age = 44})
user:save()
```

And now try get **one of them**:


```lua
local first_user = User.get:first()
print("First user name is: " .. first_user.username)
-- First user name is: First user
```

But also we can **get all users** from table:


```lua
local users = User.get:all()
print("We get " .. users:count() .. " users")
-- We get 5 users
```

Method `count` returns number of users in the list.

### Limit and Offset ###

Sometime we need to get not one but not all users. For the first, try to get first 2 users from the table.


```lua
users = User.get:limit(2):all()
print("We get " .. users:count() .. " users")
-- We get 2 users
print("Second user name is: " .. users[2].username)
-- Second user name is: Second user
```

Great! But if we want to get next two users? We can do this by using following example:

```lua
users = User.get:limit(2):offset(2):all()
print("Second user name is: " .. users[2].username)
-- Second user name is: New user
```

### Order result ###

Also you can sort your result by order. We want to sort users from the oldest to the youngest.


```lua
users = User.get:orderBy({OrderBy.DESC('age')}):all()
print("First user id: " .. users[1].id)
-- First user id: 3
```

But we have 2 users with age 44. We can order them by name.

```lua
users = User.get:orderBy({OrderBy.DESC('age'), OrderBy.ASC('username')}):all()
```

You can order your table query by other parameters too.

### Group result ###

And now try to group your results:

```lua
users = User.get:groupBy({'age'}):all()
print('Find ' .. users:count() ..' users')
-- Find 4 users
```

### Where and Having ###

These two methods have the same syntax. But `having` you can use only with `group_by `method. There's one simple example:


```lua
user = User.get:where({username = "First user"}):first()
print("User id is: " .. user.id) -- User id is: 1
```

And the same for `having`:

```lua
users = User.get:groupBy({'id'}):having({age = 44}):all()
print("We get " .. users:count() .. " users with age 44")
-- We get 2 users with age 44
```

Great! But what if we need to do more operations than just a differentiation of table fields. We can do that! This is the list with some rules:

*For example we use for default `colname`. It can be any column in your model*

1. `colname = value` - the same as `colname = value`
2. `colname__lt = value` - the same as `colname < value` *(`value` must be a number)*
3. `colname__lte = value` - the same as `colname <= value` *(`value` must be a number)*
4. `colname__gt = value` - the same as `colname > value` *(`value` must be a number)*
5. `colname__gte = value` - the same as `colname >= value` *(`value` must be a number)*
6. `colname__in = {v1, v2,...,vn}` - the same as `colname in (value1, value2,...,vn)` *(`vn` can be number, string)*
7. `colname__notin = {v1, v2,...,vn}` - the same as `colname not in (value1, value2,...,vn)` *(`vn` can be number, string)*
8. `colname__null = value` - if value is `true` then result is `colname is NULL`, but if value is `false` then result is `colname is not NULL`

### Super SELECT ###

But if we do ...

```lua
user = User.get:where({age__lt = 30,
                       age__lte = 30,
                       age__gt = 10,
                       age__gte = 10
                })
                :orderBy({OrderBy.ASC('id')})
                :groupBy({'age', 'password'})
                :having({id__in = {1, 3, 5},
                         id__notin = {2, 4, 6},
                         username__null = false
                    })
                :limit(2)
                :offset(1)
                :all()
```

This example doesn't make sense. But it works!

### JOIN TABLES ###

Now we can create a join of tables. But before that we create some table with  `foreign key` column:


```lua
local News = Table(
{
    table_name = "group",
},
{
    title = fields.CharField({max_length = 100, unique = false, null = false}),
    text = fields.TextField({null = true}),
    create_user_id = fields.ForeignKey({to_table = User})
})
```

And add two test news:


```lua
local user = User.get:first()

local news = News({title = "Some news", create_user_id = user.id})
news:save()

news = News({title = "Other title", create_user_id = user.id})
news:save()
```

Now try to get all the news from the owner.

```lua
local news = News.get:join(User):all()
print("First news user id is: " .. news[1]:foreign(User).id) -- First news user id is: 1
```

But if we want to get all users and also to get three news for each user . We can do this by following example:

```lua
local user = User.get:join(News):first()
print("User " .. user.id .. " has " .. user:references(News):count() .. " news")
-- User 1 has 2 news

for _, user_news in ipairs(user:references(News):list()) do
    print(user_news.title)
end
-- Some news
-- Other title
```

If you want to get all the foreign/references values in your table, you can use use below

```lua
local user_one = new_one:foreign(User) -- get News foreign value combine with one news
local news_all = user_one:references(News) -- get User references News value List combine with one user
```

## Create column types ##

We can create a field type for every table. Try to create EmailField type:

```lua
fields.EmailField = fields:register({
    field_name = "email",
    field_type = "varchar",
    settings = {
        max_length = 100
    },
    validator = function (value)
        return value:match("[A-Za-z0-9%.%%%+%-]+@[A-Za-z0-9%.%%%+%-]+%.%w%w%w?%w?")
    end,
    toType = function (value)
        return value
    end,
    as = function (value)
        return "'" .. value .. "'"
    end
})
```

Let's make it step by step:

`field_name` - show in table `__tostring`

`field_type` - this variable creates the appropriate type in the database (`"varchar"`, `"integer"`, `"boolean"`, `"date"`, `"datetime"`, `"text"`, ...).
By default this value is `"varchar"`.

`settings` -set a field value as default (*fields settings was describe later*). By default this value is empty.

`validator` - validates the value of the variable. If value is correct - returns `true`. If value is not correct it returns `false` and doesn't update or add rows. By default it always returns `true`.

`toType` - parses value for correct sql save. By default it is not parsed value

`as` - returns the value from lua to SQL. By default it is not parsed value.

```lua
local UserEmails = Table(
{
    table_name = 'user_emails
},
{
    email = fields.EmailField(),
    user_id = fields.ForeignKey({ to_table = User })
})

local user_email = UserEmails({
    email = "mailexample.com",
    user_id = user.id
})
user_email:save() -- This email wasn't added!

-- And try again
local user_email = UserEmails({
    email = "mail@example.com",
    user_id = user.id
})
user_email:save() -- This email was added!

user_email.email = "not email"
user_email:save() -- This email wasn't updated

user_email.email = "valid@email.com"
user_email:save() -- This email was updated
```

## Final ##

All code you can see in `example-orm.lua` file. Feel free to use it! Good luck!
