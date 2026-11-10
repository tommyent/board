import Foundation

enum PracticePassages {
    static let languages = ["Swift", "JavaScript", "Python"]
    static func text(mode: PracticeMode, language: String) -> String {
        let passage: String
        if mode == .english {
            passage = "The room grew quiet as the rain moved across the window. A small lamp lit the page, and the words began to find their own rhythm. Take your time with the next sentence. A steady pace leaves room to notice the details. Outside, the last light settled on the roofs and the street turned silver. There was no need to hurry. Each line was a little clearer than the one before it."
        } else {
            switch language {
            case "JavaScript": passage = """
            function greet(name) {
                const message = `Hello, ${name}!`;
                return message;
            }

            const names = ["Ada", "Sam", "Lee"];
            const greetings = names.map(greet);
            console.log(greetings.join("\\n"));
            """
            case "Python": passage = """
            def greet(name):
                message = f"Hello, {name}!"
                return message

            names = ["Ada", "Sam", "Lee"]
            greetings = [greet(name) for name in names]
            print("\\n".join(greetings))
            """
            default: passage = """
            func greet(_ name: String) -> String {
                let message = "Hello, \\(name)!"
                return message
            }

            let names = ["Ada", "Sam", "Lee"]
            let greetings = names.map(greet)
            print(greetings.joined(separator: "\\n"))
            """
            }
        }
        return Array(repeating: passage, count: 30).joined(separator: "\n\n")
    }
}
