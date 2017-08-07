# Start

`vapor new Reminder`

Edit Package.swift and add in LeafProvider and AuthProvider, then:

* `swift package update`
* `vapor xcode -y`
* Add LeafProvider to Config setup
* Build and Run
* Delete all PostStuff and routes

# Reminder Model

```swift
import FluentProvider

final class Reminder: Model {

    let storage = Storage()

    let title: String
    let description: String

    init(title: String, description: String) {
        self.title = title
        self.description = description
    }

    init(row: Row) throws {
        title = try row.get("title")
        description = try row.get("description")
    }

    func makeRow() throws -> Row {
        var row = Row()
        try row.set("title", title)
        try row.set("description", description)
        return row
    }
}

extension Reminder: Preparation {
    static func prepare(_ database: Database) throws {
        try database.create(self) { builder in
            builder.id()
            builder.string("title")
            builder.string("description")
        }
    }

    static func revert(_ database: Database) throws {
        try database.delete(self)
    }
}

extension Reminder: JSONConvertible {
    convenience init(json: JSON) throws {
        try self.init(title: json.get("title"), description: json.get("description"))
    }

    func makeJSON() throws -> JSON {
        var json = JSON()
        try json.set("id", id)
        try json.set("title", title)
        try json.set("description", description)
        return json
    }
}

extension Reminder: ResponseRepresentable {}
```

# ReminderController

```swift
import Vapor
import FluentProvider

struct ReminderController {

    func addRoutes(drop: Droplet) {
        let reminderGroup = drop.grouped("api", "reminders")
        reminderGroup.get(handler: allReminders)
        reminderGroup.post("create", handler: createReminder)
        reminderGroup.get(Reminder.parameter, handler: getReminder)
    }

    func allReminders(_ req: Request) throws -> ResponseRepresentable {
        let reminders = try Reminder.all()

        return try reminders.makeJSON()
    }

    func createReminder(_ req: Request) throws -> ResponseRepresentable {
        let reminder = try req.reminder()
        try reminder.save()
        return reminder
    }

    func getReminder(_ req: Request) throws -> ResponseRepresentable {
        let reminder = try req.parameters.next(Reminder.self)
        return reminder
    }
}

extension Request {
    /// Create a post from the JSON body
    /// return BadRequest error if invalid
    /// or no JSON
    func reminder() throws -> Reminder {
        guard let json = json else { throw Abort.badRequest }
        return try Reminder(json: json)
    }
}

```

Add the Reminder to the preparations, and then to setup routes:

```swift
let reminderController = ReminderController()
reminderController.addRoutes(drop: self)
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

## ReminderWebController:

```swift
import Vapor

struct ReminderWebController {

    let drop: Droplet

    func addRoutes() {
        drop.get(handler: indexHandler)
    }

    func indexHandler(_ req: Request) throws -> ResponseRepresentable {
        return try drop.view.make("index", [
            "reminders": try Reminder.all()
            ])
    }


}
```

Add `NodeRepresentable` extension to Reminder:

```swift
extension Reminder: NodeRepresentable {
    func makeNode(in context: Context?) throws -> Node {
        var node = Node([:], in: nil)
        try node.set("id", id)
        try node.set("title", title)
        try node.set("description", description)
        return node
    }
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

struct ReminderWebController {

    let drop: Droplet

    func addRoutes() {
        drop.get(handler: indexHandler)
        drop.get("create", handler: createHandler)
        drop.post("create", handler: createPostHandler)
        drop.get("reminder", Reminder.parameter, handler: reminderHandler)
    }

    func indexHandler(_ req: Request) throws -> ResponseRepresentable {
        return try drop.view.make("index", [
            "reminders": try Reminder.all()
            ])
    }

    func createHandler(_ req: Request) throws -> ResponseRepresentable {
        return try drop.view.make("create")
    }

    func createPostHandler(_ req: Request) throws -> ResponseRepresentable {
        guard let title = req.data["title"]?.string, let description = req.data["description"]?.string else {
            throw Abort.badRequest
        }

        let reminder = Reminder(title: title, description: description)
        try reminder.save()

        return Response(redirect: "/reminder/\(reminder.id?.string ?? "NULL")")
    }

    func reminderHandler(_ req: Request) throws -> ResponseRepresentable {
        let reminder = try req.parameters.next(Reminder.self)

        return try drop.view.make("reminder", ["reminder": reminder])
    }

}
```

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
