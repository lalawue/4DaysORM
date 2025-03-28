----------------------------- REQUIRE --------------------------------

local DBClass = require("old_version.sql-orm-old-version")

local instance = DBClass.new({
    newtable = true,
    path = "database.db",
    type = "sqlite3",
    DEBUG = true,
    TRACE = true
})

local Table, Field, tpairs, Or = instance.Table, instance.Field, instance.tablePairs, instance.OrderBy

----------------------------- CREATE TABLE --------------------------------

local User = Table({
    __tablename__ = "user_t",
    username = Field.CharField({max_length = 100, primary_key = true}),
    password = Field.CharField({max_length = 50, unique = true}),
    age = Field.IntegerField({max_length = 2, null = true}),
    job = Field.CharField({max_length = 50, null = true}),
    time_create = Field.DateTimeField({null = true}),
    active = Field.BooleanField({null = true}),
})

----------------------------- CREATE DATA --------------------------------

local user = User({
    username = "Bob Smith",
    password = "SuperSecretPassword",
    time_create = os.time(),
})

user:save()
print("User " .. user.username .. " has id " .. user.id)
-- User Bob Smith has id 1

----------------------------- UPDATE DATA --------------------------------

user.username = "John Smith"
user:save()

print("New user name is " .. user.username)
-- New user name is John Smith

-- Update fields with where statement
User.get:where({time_create__null = true})
        :update({time_create = os.time()})

----------------------------- DELETE DATA --------------------------------

user:delete()

user = User({username = "SomebodyNew", password = "NotSecret"})
user:save()

User.get:where({username = "SomebodyNew"}):delete()

----------------------------- ADD TEST DATA --------------------------------

user = User({username = "First user", password = "secret1", age = 22, active = true})
user:save()

user = User({username = "Second user", password = "secret_test", job = "Lua developer", active = false})
user:save()

user = User({username = "Another user", password = "old_test", age = 44})
user:save()

user = User({username = "New user", password = "some_passwd", age = 23, job = "Manager"})
user:save()

user = User({username = "Old user", password = "secret_passwd", age = 44})
user:save()

----------------------------- GET DATA --------------------------------

local first_user = User.get:first()
print("First user name is: " .. first_user.username)
-- First user name is: First user

print("First user active is: " .. tostring(first_user.active))
-- First user active is: true

local users = User.get:all()
print("We get " .. users:count() .. " users")
-- We get 5 users

----------------------------- LIMIT AND OFFSET --------------------------------

users = User.get:limit(2):all()
print("We get " .. users:count() .. " users")
-- We get 2 users
print("Second user name is: " .. users[2].username)
-- Second user name is: Second user

print("Second user active is: " .. tostring(users[2].active))
-- Second user active is: false

users = User.get:limit(2):offset(2):all()
print("Second user name is: " .. users[2].username)
-- Second user name is: New user

----------------------------- SORT DATA --------------------------------

users = User.get:order_by({Or.DESC('age')}):all()
print("First user id: " .. users[1].id)
-- First user id: 3

users = User.get:order_by({Or.DESC('age'), Or.ASC('username')}):all()

----------------------------- GROUP DATA --------------------------------

users = User.get:group_by({'age'}):all()
print('Find ' .. users:count() ..' users')
-- Find 4 users

----------------------------- WHERE AND HAVING --------------------------------

user = User.get:where({username = "First user"}):first()
print("User id is: " .. user.id)
-- User id is: 1

users = User.get:group_by({'id'}):having({age = 44}):all()
print("We get " .. users:count() .. " users with age 44")
-- We get 2 users with age 44

----------------------------- SUPER SELECT --------------------------------

user = User.get:where({age__lt = 30,
                       age__lte = 30,
                       age__gt = 10,
                       age__gte = 10
                })
                :order_by({Or.ASC('id')})
                :group_by({'age', 'password'})
                :having({id__in = {1, 3, 5},
                         id__notin = {2, 4, 6},
                         username__null = false
                })
                :limit(2)
                :offset(1)
                :all()

----------------------------- JOIN TABLES --------------------------------

local News = Table({
    __tablename__ = "news",
    title = Field.CharField({max_length = 100, unique = false, null = false}),
    text = Field.TextField({null = true}),
    create_user_id = Field.ForeignKey({to = User})
})

local user = User.get:first()

local news = News({title = "Some news", create_user_id = user.id})
news:save()

news = News({title = "Other title", create_user_id = user.id})
news:save()

news = News.get:join(User):all()
print("First news user id is: " .. news[1].user_t.id)
-- First news user id is: 1

local user = User.get:join(News):all()[1]
print("User " .. user.id .. " has " .. user.news_all:count() .. " news")
-- User 1 has 2 news

for _, user_news in tpairs(user.news_all) do
    print(user_news.title)
end
-- Some news
-- Other title


----------------------------- CREATE NEW FIRLD TYPE --------------------------------

Field.EmailField = Field:register({
    __type__ = "varchar",
    settings = {
        max_length = 100
    },
    validator = function (value)
        return value:match("[A-Za-z0-9%.%%%+%-]+@[A-Za-z0-9%.%%%+%-]+%.%w%w%w?%w?")
    end,
    to_type = function (value)
        return value
    end,
    as = function (value)
        return "'" .. value .. "'"
    end
})

local UserEmails = Table({
    __tablename__ = "user_emails",
    email = Field.EmailField(),
    user_id = Field.ForeignKey({ to = User })
})

local user_email = UserEmails({
    email = "mailexample.com",
    user_id = user.id
})
user_email:save()
-- Not save!

-- And try again
local user_email = UserEmails({
    email = "mail@example.com",
    user_id = user.id
})
user_email:save()
-- This email added!

user_email.email = "not email"
user_email:save()
-- Not update

user_email.email = "valid@email.com"
user_email:save()
-- Update!

instance:close()
