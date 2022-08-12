local function testDatabase()
    os.remove("database.db")
    local DBClass = require("sql-orm")

    print("---------------- CREATE Database Instance")
    local DBIns, Table, Field, Or = DBClass({
        new_table = true,
        db_path = "database.db",
        db_type = "sqlite3",
        log_debug = true,
        log_trace = true
    })

    print("---------------- CREATE TABLE")
    local User = Table({
        table_name = "user_t",
        column_order = {"username", "password", "age", "job", "time_create", "active"}
    }, {
        username = Field.CharField({
            max_length = 100,
            primary_key = true
        }),
        password = Field.CharField({
            max_length = 50,
            unique = true
        }),
        age = Field.IntegerField({
            max_length = 2,
            null = true
        }),
        job = Field.CharField({
            max_length = 50,
            null = true
        }),
        time_create = Field.DateTimeField({
            null = true
        }),
        active = Field.BooleanField({
            null = true
        })
    })

    do
        print("---------------- CREATE / UPDATE / DELETE DATA")
        local user = User({
            username = "Bob Smith",
            password = "SuperSecretPassword",
            time_create = os.time()
        })
        user:save()
        print("User " .. user.username .. " has id " .. user.id)
        user.username = "John Smith"
        user:save()
        print("New user name is " .. user.username)
        User.get:where({
            password = "SuperSecretPassword"
        }):update({
            time_create = os.time()
        })
        user:delete()
        user = User({
            username = "SomebodyNew",
            password = "NotSecret"
        })
        user:save()
        User.get:where({
            username = "SomebodyNew"
        }):delete()
        print("users count", User.get:all():count())
    end

    do
        print("---------------- ADD TEST DATA")
        local user = User({
            username = "First user",
            password = "secret1",
            age = 22,
            active = true
        })
        user:save()
        user = User({
            username = "Second user",
            password = "secret_test",
            job = "Lua developer",
            active = false
        })
        user:save()
        user = User({
            username = "Another user",
            password = "old_test",
            age = 44
        })
        user:save()
        user = User({
            username = "New user",
            password = "some_passwd",
            age = 23,
            job = "Manager"
        })
        user:save()
        user = User({
            username = "Old user",
            password = "secret_passwd",
            age = 44
        })
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
        print("Second user name is: " .. users[2].username)
        print("Second user active is: " .. tostring(users[2].active))
        users = User.get:limit(2):offset(2):all()
        print("Second user name is: " .. users[2].username)
    end

    do
        print("---------------- SORT DATA")
        local users = User.get:orderBy({Or.DESC('age')}):all()
        print("-- 1 orderBy", users:count(), users[users:count()].id)
        for k, v in pairs(users:list()) do
            print(k, v.username)
        end
        users = User.get:orderBy({Or.DESC('age'), Or.DESC('username')}):all()
        print("-- 2 orderBy", users:count(), users[users:count()].id)
        for k, v in ipairs(users:list()) do
            print(k, v.username)
        end
    end

    do
        print("---------------- GROUP DATA")
        local users = User.get:groupBy({'age'}):all()
        print('Find ' .. users:count() .. ' users')
    end

    do
        print("---------------- WHERE AND HAVING")
        local user = User.get:where({
            username = "First user"
        }):first()
        print("User id is: " .. user.id)
        local users = User.get:groupBy({'id'}):having({
            age = 44
        }):all()
        print("We get " .. users:count() .. " users with age 44")
    end

    do
        print("---------------- SUPER SELECT")
        local users = User.get:where({
            age__lt = 30,
            age__lte = 30,
            age__gt = 10,
            age__gte = 10
        }):orderBy({Or.ASC('id')}):groupBy({'age', 'password'}):having({
            id__in = {1, 3, 5},
            id__notin = {2, 4, 6},
            username__null = false
        }):limit(2):offset(1):all()
        print("users count", users:count())
    end

    do
        print("---------------- JOIN TABLES")
        DBIns:execute("PRAGMA FOREIGN_KEYS=ON;")
        local News = Table({
            table_name = "news_t"
        }, {
            title = Field.CharField({
                max_length = 100,
                unique = false,
                null = false
            }),
            text = Field.TextField({
                null = true
            }),
            create_user_id = Field.ForeignKey({
                to_table = User
            })
        })
        local user = User.get:first()
        local news = News({
            title = "Some news",
            create_user_id = user.id
        })
        news:save()
        news = News({
            title = "Other title",
            create_user_id = user.id
        })
        news:save()
        local news_all = News.get:join(User):all()
        print("First news user id is: " .. news_all[1]:foreign("user_t").id)
        print("First news user id is: " .. news_all[1]:foreign(User).id)
        user = User.get:join(News):all()[1]
        print("User " .. user.id .. " has " .. user:references('news_t'):count() .. " news")
        print("User " .. user.id .. " has " .. user:references(News):count() .. " news")
        for i, user_news in ipairs(user:references(News):list()) do
            print("news " .. i .. ": ", user_news.title)
        end
    end

    print("---------------- END")

    DBIns:close()
    collectgarbage()
end
for i = 1, 5 do
    testDatabase()
end
