import Vapor

extension Droplet {
    func setupRoutes() throws {
        let reminderController = ReminderController()
        reminderController.addRoutes(drop: self)
    }
}
