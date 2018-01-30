# Start

`vapor new Reminder --branch=beta`

Edit Package.swift and add in Fluent, FluentSQLite, Leaf and Auth, then:

* `swift package update`
* `vapor xcode -y`
* Build and Run and hit hello

# Sample Routes

```swift
router.get("hello", "vapor") { req in
    return "Hello Vapor!"
}

router.get("hello", String.parameter) { req -> String in
    let name = try req.parameter(String.self)
    return "Hello \(name)!"
}

router.post("info") { req -> WhoamiResponse in
    let data = try req.content.decode(WhoamiData.self).await(on: req)
    return InfoResponse(request: data)
}

struct WhoamiData: Content {
  let name: String
}

struct WhoamiResponse: Content {
  let request: WhoamiData
}
```


# Reminder Model

```swift
import FluentSQLite

final class Reminder: Codable {
    var id: Int?
    var title: String
    var description: String

    init(title: String, description: String) {
        self.title = title
        self.description = description
    }
}

extension Reminder: Model {
    typealias Database = SQLiteDatabase
    static let idKey = \Reminder.id
}

extension Reminder: Content, Migration {}
```

Or even change it to:

```swift
extension Reminder: SQLiteModel {
  static let idKey = \Reminder.id
}
```

# ReminderController

```swift
import Vapor
import Fluent // needed?

struct ReminderController: RouteCollection {

    func boot(router: Router) throws {
        let reminderGroup = router.grouped("api", "reminders")
        reminderGroup.get(use: allReminders)
        reminderGroup.post("create", use: createReminder)
        reminderGroup.get(Reminder.parameter, use: getReminder)
    }

    func allReminders(_ req: Request) throws -> Future<[Reminder]> {
        return Acronym.query(on: req).all()
    }

    func createReminder(_ req: Request) throws -> Future<Reminder> {
        return try req.content.decode(Reminder.self).flatMap(to: Reminder.self) { reminder in
            return reminder.save(on: req)
        }
    }

    func getReminder(_ req: Request) throws -> Future<Reminder> {
        return try req.parameter(Reminder.self)
    }
}

extension Reminder: Parameter {}
```

To configure the database:

```swift
try services.register(FluentProvider())
try services.register(FluentSQLiteProvider())

let database = SQLiteDatabase(storage: .memory))
var databaseConfig = DatabaseConfig()
databaseConfig.add(database: database, as: .sqlite)
services.register(databaseConfig)

var migrationConfig = MigrationConfig()
migrationConfig.add(model: Reminder.self, database: .sqlite)
services.register(migrationConfig)
```

Then to setup routes:

```swift
let reminderController = ReminderController()
try router.register(collection: reminderController)
```

* Send request to http://localhost:8080/api/reminders/ and show empty array
* Send request to http://localhost:8080/api/reminders/create/ with JSON:

```json
{
    "title": "Lunch",
    "description": "Buy tuna sandwich"
}
```

Then send request to http://localhost:8080/api/reminders/1/ to show reminder created, then again to http://localhost:8080/api/reminders/ to show it in the list.

# Web App

* Create views directory: mkdir -p Resources/Views/
* Copy in base.leaf, index.leaf, login.leaf and reminder.leaf and style.css

## Configure.swift

```swift
try services.register(LeafProvider())
```

## ReminderWebController:

```swift
import Vapor
import Leaf

struct ReminderWebController: RouteCollection {

    func boot(router: Router) throws {
        router.get(use: indexHandler)
    }

    func indexHandler(_ req: Request) throws -> Future<View> {
        return Reminder.query(on: req).all().flatMap(to: View.self) { reminders in
            let context = IndexData(title: "Homepage", reminders: reminders)
            return try req.make(LeafRenderer.self).render("index", context)
        }
    }
}

struct IndexData: Encodable {
    let title: String
    let reminders: [Reminder]?
}

```

Then add to index.leaf:

```html
#if(reminders) {
    #loop(reminders, "reminder") {
        <tr><td><a href="/reminders/#(reminder.id)/">#(reminder.title)</a></td><td>#(reminder.description)</td></tr>
    }
}
```

Demo:

* Add in reminder using Rested and show in table
* Create create page: add new route and handler to just show create.leaf
* Create post and reminder handler:

```swift
import Vapor

struct ReminderWebController: RouteCollection {

    func boot(router: Router) throws {
        router.get(use: indexHandler)
        router.get("create", use: createHandler)
        router.post("create", use: createPostHandler)
        router.get("reminders", Reminder.parameter, handler: reminderHandler)
    }

    func indexHandler(_ req: Request) throws -> Future<View> {
        return Reminder.query(on: req).all().flatMap(to: View.self) { reminders in
            let context = IndexData(title: "Homepage", reminders: reminders)
            return try req.make(LeafRenderer.self).render("index", context)
        }
    }

    func createHandler(_ req: Request) throws -> Future<View> {
        return try req.make(LeafRenderer.self).render("create")
    }

    func createPostHandler(_ req: Request) throws -> Future<Response> {
        return try req.content.decode(CreateReminderData.self).flatMap(to: Response.self) { data in
            let reminder = Reminder(title: data.title, description: data.description)
            return reminder.save(on: req).map(to: Response.self) { reminder in
                guard let id = reminder.id else {
                    return req.redirect(to: "/")
                }
                return req.redirect(to: "/reminders/\(id)")
            }
        }
    }

    func reminderHandler(_ req: Request) throws -> Future<View> {
        return try req.parameter(Reminder.self).flatMap(to: View.self) { reminder in
            let context = ReminderContext(reminder: reminder)
            return try req.make(LeafRenderer.self).render("reminder", context)
        }
    }

}

struct CreateReminderData: Content {
    static let defaultMediaType = MediaType.urlEncodedForm
    let title: String
    let description: String
}

struct ReminderContext: Encodable {
    let reminder: Reminder
}
```

> The rest is to do

# User Model

```swift
import FluentProvider
import AuthProvider

final class User: Model {

    let storage = Storage()
    let username: String
    let password: Bytes

    init(row: Row) throws {
        username = try row.get("username")
        let passwordString: String = try row.get("password")
        password = passwordString.makeBytes()
    }

    init(username: String, password: Bytes) {
        self.username = username
        self.password = password
    }

    func makeRow() throws -> Row {
        var row = Row()
        try row.set("username", username)
        try row.set("password", password.makeString())
        return row
    }
}

extension User: Preparation {
    static func prepare(_ database: Database) throws {
        try database.create(self) { builder in
            builder.id()
            builder.string("username")
            builder.string("password")
        }
    }

    static func revert(_ database: Database) throws {
        try database.delete(self)
    }
}

extension User: PasswordAuthenticatable {
    static let usernameKey = "username"
    static let passwordVerifier: PasswordVerifier? = User.passwordHasher
    var hashedPassword: String? {
        return password.makeString()
    }
    static var passwordHasher: PasswordHasherVerifier = BCryptHasher(cost: 10)
}

protocol PasswordHasherVerifier: PasswordVerifier, HashProtocol {}

extension BCryptHasher: PasswordHasherVerifier {}

extension User: SessionPersistable {}

struct UserSeed: Preparation {

    static func prepare(_ database: Database) throws {
        let password = try User.passwordHasher.make("tim")
        let user = User(username: "tim", password: password)
        try user.save()
    }

    static func revert(_ database: Database) throws {}
}
```

Add the user and user seed the to preparations

Create the LoginRedirectMiddleware:

```swift
import Vapor

struct LoginRedirectMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: Responder) throws -> Response {

        guard request.auth.isAuthenticated(User.self) else {
            return Response(redirect: "/login")
        }

        return try next.respond(to: request)
    }
}
```

In the ReminderWebControler, replace the create routes with:

```swift
let redirectMiddleware = LoginRedirectMiddleware()
let protected = drop.grouped(redirectMiddleware)
protected.get("create", handler: createHandler)
protected.post("create", handler: createPostHandler)
```

And add a login route:

```swift
drop.get("login", handler: loginHandler)
drop.post("login", handler: loginPostHandler)
```

Finally add the handlers:

```swift
func loginHandler(_ req: Request) throws -> ResponseRepresentable {
    return try drop.view.make("login")
}

func loginPostHandler(_ req: Request) throws -> ResponseRepresentable {
    guard let username = req.data["username"]?.string, let password = req.data["password"]?.string else {
        throw Abort.badRequest
    }

    let credentials = Password(username: username, password: password)

    do {
        let user = try User.authenticate(credentials)
        req.auth.authenticate(user)
    } catch {
        return try drop.view.make("login")
    }

    return Response(redirect: "/")
}
```

Finally, set up sessions and persistence. Add it to the Config+Setup:

```swift
import AuthProvider
import Sessions

addConfigurable(middleware: SessionsMiddleware.init, name: "sessions")
addConfigurable(middleware: PersistMiddleware.init(User.self), name: "persist")
```

Add it to the `droplet.json` config file:

```json
"middleware": [
    "error",
    "date",
    "file",
    "sessions",
    "persist"
],
```

# Vapor Cloud

Run `vapor-beta cloud deploy` (do an incremental build)
