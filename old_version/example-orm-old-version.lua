

-- database testing
local function testDatabase()
    os.remove("database.db")

    local DBClass = require("old_version.sql-orm-old-version")

    print("---------------- CREATE Database Instance")

    local instance = DBClass.new({
        newtable = true,
        path = "database.db",
        type = "sqlite3",
        DEBUG = true,
        TRACE = true
    })

    print("---------------- CREATE TABLE")

    local Table, Field, tpairs, Or = instance.Table, instance.Field, instance.tablePairs, instance.OrderBy

    local User = Table({
        __tablename__ = "user_t",
        __columnCreateOrder__ = { "username", "password", "age", "job", "time_create", "active" },
        username = Field.CharField({max_length = 100, primary_key = true}),
        password = Field.CharField({max_length = 50, unique = true}),
        age = Field.IntegerField({max_length = 2, null = true}),
        job = Field.CharField({max_length = 50, null = true}),
        time_create = Field.DateTimeField({null = true}),
        active = Field.BooleanField({null = true}),
    })

    do
        print("---------------- CREATE / UPDATE / DELETE DATA")

        local user = User({
            username = "Bob Smith",
            password = "SuperSecretPassword",
            time_create = os.time(),
        })

        user:save()
        print("User " .. user.username .. " has id " .. user.id)
        -- User Bob Smith has id 1

        user.username = "John Smith"
        user:save()

        print("New user name is " .. user.username)
        -- New user name is John Smith

        -- Update fields with where statement
        User.get:where({time_create__null = true})
                :update({time_create = os.time()})

        user:delete()

        user = User({username = "SomebodyNew", password = "NotSecret"})
        user:save()

        User.get:where({username = "SomebodyNew"}):delete()
        print("users count", User.get:all():count())
    end

    do
        print("---------------- ADD TEST DATA")

        local user = User({username = "First user", password = "secret1", age = 22, active = true})
        user:save()

        user = User({username = "Second user", password = "secret_test", job = "Lua developer", active = false})
        user:save()

        user = User({username = "Another user", password = "old_test", age = 44})
        user:save()

        user = User({username = "New user", password = "some_passwd", age = 23, job = "Manager"})
        user:save()

        user = User({username = "Old user", password = "secret_passwd", age = 44})
        user:save()
    end

    do
        print("---------------- GET DATA")

        local first_user = User.get:first()
        print("First user name is: " .. first_user.username)

        local users = User.get:all()
        print("We get " .. users:count() .. " users")
    end

    do
        print("---------------- LIMIT AND OFFSET")

        local users = User.get:limit(2):all()
        print("We get " .. users:count() .. " users")
        -- We get 2 users
        print("Second user name is: " .. users[2].username)
        -- Second user name is: Second user

        print("Second user active is: " .. tostring(users[2].active))
        -- Second user active is: false

        users = User.get:limit(2):offset(2):all()
        print("Second user name is: " .. users[2].username)
        -- Second user name is: New user
    end

    do
        print("---------------- SORT DATA")

        local users = User.get:order_by({Or.DESC('age')}):all()
        print("-- 1 order_by", #users, users[math.max(#users,1)].id)
        for k, v in tpairs(users) do
            print(k, v.username)
        end

        local users = User.get:order_by({Or.DESC('age'), Or.DESC('username')}):all()
        print("-- 2 order_by", #users, users[math.max(#users,1)].id)
        for k, v in tpairs(users) do
            print(k, v.username)
        end
    end

    do
        print("---------------- GROUP DATA")

        local users = User.get:group_by({'age'}):all()
        print('Find ' .. users:count() ..' users')
        -- Find 4 users
    end

    do
        print("---------------- WHERE AND HAVING")

        local user = User.get:where({username = "First user"}):first()
        print("User id is: " .. user.id)
        -- User id is: 1

        local users = User.get:group_by({'id'}):having({age = 44}):all()
        print("We get " .. users:count() .. " users with age 44")
        -- We get 2 users with age 44
    end

    do
        print("---------------- SUPER SELECT")

        local users = User.get:where({
            age__lt = 30,
            age__lte = 30,
            age__gt = 10,
            age__gte = 10
        })
        :order_by({Or.ASC('id')})
        :group_by({'age', 'password'})
        :having({
            id__in = {1, 3, 5},
            id__notin = {2, 4, 6},
            username__null = false
        })
        :limit(2)
        :offset(1)
        :all()

        print("users count", users:count())
    end

    do
        print("---------------- JOIN TABLES")

        --instance:execute("PRAGMA FOREIGN_KEYS=ON;")

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
    end

    print("---------------- END")
    instance:close()
    collectgarbage()
end

--for i=1, 5000 do
for i=1, 5 do
    testDatabase()
end
