import SwiftUI
import AppKit

@main struct RenderPreviews {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let destination = root.appendingPathComponent("Assets/ThemePreviews")
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        for theme in ["Dark","Light","Glass Dark","Glass Clear"] {
            let view = KeyboardView(layout:"ANSI",held:[0,1,2,3,38],theme:theme,accent:Accent(nil)).padding(12).frame(width:600,height:252).background(theme.contains("Dark") ? Color(white:0.18) : Color(white:0.9))
            let renderer = ImageRenderer(content:view); renderer.scale = 2
            if let cg = renderer.cgImage { let rep = NSBitmapImageRep(cgImage:cg); try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(theme.replacingOccurrences(of:" ",with:"-")+".png")) }
        }
        let thumbnails = root.appendingPathComponent("Assets/SwitchThumbnails")
        try FileManager.default.createDirectory(at:thumbnails,withIntermediateDirectories:true)
        for profile in SoundProfile.catalog {
            let renderer = ImageRenderer(content:SwitchMark(color:Color(hex:profile.color)).padding(4)); renderer.scale = 4
            if let cg = renderer.cgImage { let rep = NSBitmapImageRep(cgImage:cg); try rep.representation(using:.png,properties:[:])!.write(to:thumbnails.appendingPathComponent(profile.id+".png")) }
        }
        let app = AppState(defaults:UserDefaults(suiteName:"com.tommyent.Board.asset-render")!)
        app.settings = AppSettings()
        app.pills = ["⌘ S","⇧ K","space"]
        for _ in 0..<42 { _ = app.combo.press(at:0,settings:app.settings.visualizer) }
        for theme in ["Monochrome","Amber","Neon"] {
            app.settings.visualizer.style = "Combo"; app.settings.visualizer.comboTheme = theme
            let renderer = ImageRenderer(content:OverlayContent(app:app).frame(width:210,height:170)); renderer.scale = 2
            if let cg = renderer.cgImage { let rep = NSBitmapImageRep(cgImage:cg); try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent("Combo-"+theme+".png")) }
        }
        print("Rendered live keyboard/combo themes and switch thumbnails")
    }
}
